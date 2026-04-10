import Foundation
import CryptoKit

/// 管理与 Relay 服务器的 WebSocket 连接，包含认证、心跳和自动重连
@MainActor
final class RelayConnection: NSObject, ObservableObject {

    // MARK: - Published 属性

    @Published var status: ConnectionStatus = .disconnected
    @Published var latencyMs: Int?

    // MARK: - 配置

    var serverURL: String = ""
    var phoneID: String = ""
    var pairSecret: String = ""

    /// E2E 加密管理器，设置后自动加密发送载荷、解密接收载荷
    var e2eCrypto: E2ECryptoManager?

    /// 离线消息队列：断线时缓存，重连后自动发送
    let offlineQueue = OfflineMessageQueue()

    /// 收到消息时的回调（在主线程调用）
    var onMessage: ((Data) -> Void)?

    /// 远端解除配对时的回调（Mac 端解除配对）
    var onRemoteUnpair: (() -> Void)?

    // MARK: - DisconnectRecovery 接入

    /// 断线恢复管理器，由外部注入（弱引用避免循环）
    var recovery: DisconnectRecovery?

    // MARK: - 私有状态

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1
    private var pingStartTime: Date?

    /// C4: 响应回调注册表，key 为请求 id
    private var responseHandlers: [Int: ([String: Any]) -> Void] = [:]
    /// 自增请求 ID 计数器，避免时间戳碰撞
    private var nextRequestID: Int = 1
    /// RPC 请求去重缓存
    let rpcDedup = RpcDedupCache()

    // MARK: - 连接管理

    /// 建立 WebSocket 连接
    func connect() {
        guard !serverURL.isEmpty, !phoneID.isEmpty else {
            print("[relay] connect 跳过: serverURL=\(serverURL) phoneID=\(phoneID)")
            return
        }

        // E2E: pairSecret 可用时初始化加密管理器
        if !pairSecret.isEmpty {
            e2eCrypto = E2ECryptoManager(pairSecret: pairSecret)
        }

        cancelReconnect()
        status = .connecting

        print("[relay] 正在连接: wss://\(serverURL)/ws/phone/\(phoneID) pairSecret长度=\(pairSecret.count)")
        let urlString = "wss://\(serverURL)/ws/phone/\(phoneID)"
        guard let url = URL(string: urlString) else {
            status = .disconnected
            return
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        // 启动认证握手监听
        receiveNext()
    }

    /// 断开连接并停止重连
    func disconnect() {
        cancelReconnect()
        stopHeartbeat()
        clearPendingHandlers()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession = nil
        status = .disconnected
        reconnectDelay = 1
    }

    /// 切换到新设备：断开当前连接，更新凭据并重新连接
    func switchDevice(serverURL: String, phoneID: String, pairSecret: String) {
        disconnect()
        self.serverURL = serverURL
        self.phoneID = phoneID
        self.pairSecret = pairSecret
        connect()
    }

    // MARK: - 消息发送

    /// 发送 RPC 请求消息（断线时自动入队，重连后批量发送）
    func send(_ payload: [String: Any]) {
        // 离线时入队，等待重连后发送
        guard status == .connected else {
            offlineQueue.enqueue(payload)
            return
        }

        sendPayload(payload)
    }

    /// 内部发送逻辑：加密 + 封装 envelope
    private func sendPayload(_ payload: [String: Any]) {
        // E2E: 如果加密管理器已配置，加密内层载荷
        let finalPayload: [String: Any]
        if let crypto = e2eCrypto, let encrypted = crypto.encrypt(payload) {
            finalPayload = encrypted
        } else {
            finalPayload = payload
        }

        let envelope: [String: Any] = [
            "seq": 0,
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "from": "phone",
            "type": "rpc_request",
            "payload": finalPayload
        ]
        sendRaw(envelope)
    }

    /// C4: 发送 RPC 请求并注册响应回调，响应到达时在主线程调用 handler
    /// 30 秒超时自动移除 handler，防止内存泄漏
    func sendWithResponse(_ payload: [String: Any], handler: @escaping ([String: Any]) -> Void) {
        // 去重检查
        if let requestId = payload["request_id"] as? String {
            guard rpcDedup.shouldSend(requestId) else {
                print("[relay] 去重拦截: request_id=\(requestId.prefix(8))")
                return
            }
        }

        let id = payload["id"] as? Int ?? {
            let current = nextRequestID
            nextRequestID += 1
            return current
        }()
        responseHandlers[id] = handler
        var payloadWithID = payload
        payloadWithID["id"] = id
        send(payloadWithID)

        // 30 秒超时：自动清除未响应的 handler
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self else { return }
            if let expiredHandler = self.responseHandlers.removeValue(forKey: id) {
                expiredHandler(["error": "timeout", "message": "响应超时（30秒）"])
            }
        }
    }

    /// 连接成功后主动请求 surface 列表
    /// 直接通知 onSurfacesUpdated 回调，不依赖 MessageStore 解析
    var onSurfacesUpdated: (([[String: Any]]) -> Void)?

    /// Claude 消息推送回调（Mac 端 JSONL 文件变化时触发）
    var onClaudeUpdate: (([String: Any]) -> Void)?

    func requestSurfaceList() {
        sendWithResponse([
            "method": "surface.list",
        ]) { [weak self] result in
            print("[relay] surface.list 回调, keys=\(result.keys.sorted())")
            // 从响应中提取 surfaces 数组
            if let surfacesArr = result["surfaces"] as? [[String: Any]] {
                print("[relay] 直接获取到 \(surfacesArr.count) 个 surface (dict)")
                self?.onSurfacesUpdated?(surfacesArr)
            } else if let resultDict = result["result"] as? [String: Any],
                      let surfacesArr = resultDict["surfaces"] as? [[String: Any]] {
                print("[relay] 从 result 获取到 \(surfacesArr.count) 个 surface")
                self?.onSurfacesUpdated?(surfacesArr)
            }
        }
    }

    /// 发送断点续传恢复消息
    func sendResume(lastSeq: UInt64) {
        let envelope: [String: Any] = [
            "seq": lastSeq,
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "from": "phone",
            "type": "resume"
        ]
        sendRaw(envelope)
    }

    // MARK: - 私有辅助方法

    /// 序列化并发送字典消息
    private func sendRaw(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                Task { @MainActor [weak self] in
                    self?.handleDisconnect(error: error)
                }
            }
        }
    }

    /// 持续接收 WebSocket 消息
    private func receiveNext() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    print("[relay] 收到消息")
                    self.handleMessage(message)
                    self.receiveNext()
                case .failure(let error):
                    print("[relay] 接收失败: \(error)")
                    self.handleDisconnect(error: error)
                }
            }
        }
    }

    /// 处理接收到的 WebSocket 消息
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        var data: Data?

        switch message {
        case .string(let text):
            data = text.data(using: .utf8)
        case .data(let raw):
            data = raw
        @unknown default:
            return
        }

        guard let data else { return }

        // 尝试解析认证挑战或 rpc_response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msgType = json["type"] as? String {
            switch msgType {
            case "auth_challenge":
                handleAuthChallenge(json)
                return
            case "auth_ok":
                // 认证成功，更新状态并启动心跳
                status = .connected
                reconnectDelay = 1
                startHeartbeat()
                print("[relay] 认证成功，已连接")
                // C4: 通知 recovery 连接已恢复，并发送 resume（如有历史序列号）
                if let r = recovery {
                    r.markReconnected()
                    if r.lastSeq > 0 {
                        sendResume(lastSeq: r.lastSeq)
                    }
                }
                // 重连后批量发送离线队列中的消息
                offlineQueue.flush { [weak self] msg in
                    self?.sendPayload(msg)
                }
                // 连接成功后，主动请求 surface 列表（带重试）
                requestSurfaceList()
                // 3 秒后再试一次（防止首次请求丢失）
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run { requestSurfaceList() }
                }
                return
            case "auth_fail":
                disconnect()
                return
            case "pair_deleted":
                // Mac 端解除了配对，清除本地凭据并断开连接
                handleRemoteUnpair()
                return
            case "rpc_response":
                // 从 payload 中提取 id（Envelope 格式的 id 在 payload 内部）
                // E2E: 如果载荷已加密，先解密
                let rawPayload = json["payload"] as? [String: Any]
                let payloadDict: [String: Any]? = {
                    guard let raw = rawPayload else { return nil }
                    if let crypto = e2eCrypto, E2ECryptoManager.isEncrypted(raw) {
                        return crypto.decrypt(raw)
                    }
                    return raw
                }()
                print("[relay] rpc_response 到达, payload keys=\(payloadDict?.keys.sorted().joined(separator: ",") ?? "nil"), handlers=\(responseHandlers.count)")
                // 支持 Int / Double / String 等多种 id 类型
                let rawID = payloadDict?["id"] ?? json["id"]
                let msgID: Int? = {
                    if let intID = rawID as? Int { return intID }
                    if let doubleID = rawID as? Double { return Int(doubleID) }
                    if let strID = rawID as? String { return Int(strID) }
                    return nil
                }()
                if let msgID, let handler = responseHandlers.removeValue(forKey: msgID) {
                    handler(payloadDict ?? json)
                    // 仍然转发给上层，供 MessageStore 更新状态
                }
            default:
                break
            }
        }

        // 转发给上层处理
        // E2E: 如果消息载荷已加密，解密后重新序列化再转发
        if let crypto = e2eCrypto,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let encryptedPayload = json["payload"] as? [String: Any],
           E2ECryptoManager.isEncrypted(encryptedPayload),
           let decryptedPayload = crypto.decrypt(encryptedPayload) {
            var decryptedJson = json
            decryptedJson["payload"] = decryptedPayload
            if let decryptedData = try? JSONSerialization.data(withJSONObject: decryptedJson) {
                onMessage?(decryptedData)
                return
            }
        }
        onMessage?(data)
    }

    /// 处理认证挑战，计算 HMAC-SHA256 并回复
    private func handleAuthChallenge(_ json: [String: Any]) {
        // C1: 服务端 challenge 只含 nonce，不含 timestamp；timestamp 由客户端生成
        guard let nonce = json["nonce"] as? String else { return }

        // 时间戳使用秒（与 Mac 端和服务器一致）
        let timestamp = Int64(Date().timeIntervalSince1970)

        // 计算 HMAC-SHA256(key=SHA256(pairSecret) hex, msg=phoneID:nonce:timestamp)
        // C7: 消息各字段用 ":" 分隔，避免拼接歧义
        let secretHex = SHA256.hash(data: Data(pairSecret.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        guard let keyData = secretHex.data(using: .utf8) else { return }
        let message = phoneID + ":" + nonce + ":" + String(timestamp)
        let messageData = Data(message.utf8)

        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)
        let signatureHex = mac.compactMap { String(format: "%02x", $0) }.joined()

        // C1: 字段名用 "signature"（不是 "hmac"），类型用 "auth"（不是 "auth_response"）
        let authResponse: [String: Any] = [
            "type": "auth",
            "device_id": phoneID,
            "nonce": nonce,
            "timestamp": timestamp,
            "signature": signatureHex
        ]
        sendRaw(authResponse)
    }

    /// 处理远端解除配对：清除凭据并断开连接
    private func handleRemoteUnpair() {
        // 从 DeviceStore 移除当前活跃设备
        if let activeDevice = DeviceStore.getActiveDevice() {
            DeviceStore.removeDevice(id: activeDevice.id)
        }

        disconnect()

        // 如果还有其他设备，自动切换到下一个
        if let nextDevice = DeviceStore.getActiveDevice() {
            let phoneID = KeychainHelper.load(key: "phoneID") ?? ""
            switchDevice(
                serverURL: nextDevice.serverURL,
                phoneID: phoneID,
                pairSecret: nextDevice.pairSecret
            )
        }

        onRemoteUnpair?()
    }

    /// 处理连接断开，触发自动重连
    private func handleDisconnect(error: Error?) {
        guard status != .disconnected else { return }
        status = .disconnected
        stopHeartbeat()
        clearPendingHandlers()
        webSocketTask = nil
        // C4: 通知 recovery 连接已断开
        recovery?.markDisconnected()
        scheduleReconnect()
    }

    /// 清除所有待响应的 handler，通知调用方连接已断开
    private func clearPendingHandlers() {
        let pending = responseHandlers
        responseHandlers.removeAll()
        rpcDedup.reset()
        for (_, handler) in pending {
            handler(["error": "disconnected", "message": "连接已断开"])
        }
    }

    // MARK: - 心跳

    /// 每 30 秒发送 ping 并追踪延迟
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                self?.sendPing()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    @MainActor
    private func sendPing() {
        pingStartTime = Date()
        webSocketTask?.sendPing { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.handleDisconnect(error: error)
                } else if let start = self.pingStartTime {
                    self.latencyMs = Int(Date().timeIntervalSince(start) * 1000)
                }
            }
        }
    }

    // MARK: - 自动重连（指数退避）

    /// 使用指数退避调度重连（1s → 60s 上限）
    private func scheduleReconnect() {
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            let delay = self.currentReconnectDelay()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.bumpReconnectDelay()
            self.connect()
        }
    }

    @MainActor
    private func currentReconnectDelay() -> TimeInterval {
        reconnectDelay
    }

    @MainActor
    private func bumpReconnectDelay() {
        reconnectDelay = min(reconnectDelay * 2, 60)
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }
}

// MARK: - URLSessionWebSocketDelegate

extension RelayConnection: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        // 连接已建立，认证握手在 receiveNext 中处理
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            self?.handleDisconnect(error: nil)
        }
    }
}
