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

    /// 收到消息时的回调（在主线程调用）
    var onMessage: ((Data) -> Void)?

    // MARK: - 私有状态

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1
    private var pingStartTime: Date?

    // MARK: - 连接管理

    /// 建立 WebSocket 连接
    func connect() {
        guard !serverURL.isEmpty, !phoneID.isEmpty else { return }

        cancelReconnect()
        status = .connecting

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
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession = nil
        status = .disconnected
        reconnectDelay = 1
    }

    // MARK: - 消息发送

    /// 发送 RPC 请求消息
    func send(_ payload: [String: Any]) {
        let envelope: [String: Any] = [
            "seq": 0,
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "from": "phone",
            "type": "rpc_request",
            "payload": payload
        ]
        sendRaw(envelope)
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
                    self.handleMessage(message)
                    self.receiveNext()
                case .failure(let error):
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

        // 尝试解析认证挑战
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
                return
            case "auth_fail":
                disconnect()
                return
            default:
                break
            }
        }

        // 转发给上层处理
        onMessage?(data)
    }

    /// 处理认证挑战，计算 HMAC-SHA256 并回复
    private func handleAuthChallenge(_ json: [String: Any]) {
        guard let nonce = json["nonce"] as? String,
              let timestamp = json["timestamp"] as? String else { return }

        // 计算 HMAC-SHA256(key=SHA256(pairSecret) hex, msg=phoneID+nonce+timestamp)
        let secretHex = SHA256.hash(data: Data(pairSecret.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        guard let keyData = secretHex.data(using: .utf8) else { return }
        let message = phoneID + nonce + timestamp
        let messageData = Data(message.utf8)

        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)
        let hmacHex = mac.compactMap { String(format: "%02x", $0) }.joined()

        let authResponse: [String: Any] = [
            "type": "auth",
            "phone_id": phoneID,
            "nonce": nonce,
            "timestamp": timestamp,
            "hmac": hmacHex
        ]
        sendRaw(authResponse)
    }

    /// 处理连接断开，触发自动重连
    private func handleDisconnect(error: Error?) {
        guard status != .disconnected else { return }
        status = .disconnected
        stopHeartbeat()
        webSocketTask = nil
        scheduleReconnect()
    }

    // MARK: - 心跳

    /// 每 30 秒发送 ping 并追踪延迟
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.sendPing()
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
            let delay = await self.currentReconnectDelay()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.bumpReconnectDelay()
            await self.connect()
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
