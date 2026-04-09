import Foundation
import UIKit
import UserNotifications

/// 处理并存储来自 Relay 的消息，维护 surface 列表和屏幕快照
@MainActor
final class MessageStore: ObservableObject {

    @Published var surfaces: [Surface] = []
    @Published var snapshots: [String: ScreenSnapshot] = [:]
    @Published var lastSeq: UInt64 = 0

    /// Claude 聊天消息（按 surfaceID 索引，跨视图持久化）
    @Published var claudeChats: [String: [ClaudeChatItem]] = [:]

    /// 上一次终端内容哈希（按 surfaceID 索引）
    var lastTerminalHash: [String: Int] = [:]
    /// 上一次干净文本（按 surfaceID 索引）
    var lastCleanText: [String: String] = [:]

    /// 关联的审批管理器，由外部注入（弱引用避免循环）
    weak var approvalManager: ApprovalManager?

    /// 关联的活动日志存储，由外部注入（弱引用避免循环）
    weak var activityStore: ActivityStore?

    /// Claude 推送事件回调（Mac 端 JSONL 文件变化时触发）
    var onClaudeUpdate: (([String: Any]) -> Void)?

    /// C4: 关联的断线恢复管理器，由外部注入（弱引用避免循环）
    weak var recovery: DisconnectRecovery?

    // MARK: - file.list / browser.screenshot 响应数据

    /// C4: 最近一次 browser.screenshot 响应数据（content + encoding）
    @Published var lastScreenshotContent: String?
    @Published var lastScreenshotEncoding: String?

    // MARK: - 消息处理

    /// 解析原始 JSON 数据，更新 seq 并按类型分发
    func processRawMessage(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(RelayEnvelope.self, from: data) else {
            // 调试：打印解码失败的原始数据
            #if DEBUG
            if let text = String(data: data, encoding: .utf8) {
                print("[messageStore] 解码失败: \(text.prefix(200))")
            }
            #endif
            return
        }
        #if DEBUG
        print("[messageStore] 收到消息: type=\(envelope.type) from=\(envelope.from)")
        #endif

        // 更新最新序列号
        if envelope.seq > lastSeq {
            lastSeq = envelope.seq
            // C4: 同步 lastSeq 到 DisconnectRecovery
            recovery?.lastSeq = lastSeq
        }

        switch envelope.type {
        case "event":
            handleEvent(envelope.payload)
        case "rpc_response":
            handleRPCResponse(envelope.payload)
        default:
            break
        }
    }

    // MARK: - 私有处理逻辑

    /// 处理事件类型消息
    private func handleEvent(_ payload: [String: AnyCodable]) {
        guard case .string(let event) = payload["event"] else { return }

        switch event {
        case "agent.approval_required":
            handleApprovalRequired(payload)
            return
        case "agent.approval_resolved":
            handleApprovalResolved(payload)
            return
        case "surface.list_update":
            handleSurfaceListUpdate(payload)
            return
        case "workspace.list_update":
            handleWorkspaceListUpdate(payload)
            return
        case "claude.messages.update":
            // 将 AnyCodable 转为原生字典，通过 onClaudeUpdate 分发
            let rawDict = anyCodableToRawDict(payload)
            onClaudeUpdate?(rawDict)
            return
        case "claude.model_switching", "claude.model_switched":
            // 模型切换事件：转发给 onClaudeUpdate 回调
            let rawDict = anyCodableToRawDict(payload)
            onClaudeUpdate?(rawDict)
            return
        case "notification":
            handleTerminalNotification(payload)
            return
        default:
            break
        }

        guard event == "screen.snapshot" else { return }

        // 解析快照数据
        guard case .string(let surfaceID) = payload["surface_id"],
              case .array(let linesArray) = payload["lines"] else { return }

        let lines = linesArray.compactMap { item -> String? in
            if case .string(let s) = item { return s }
            return nil
        }

        // 解析尺寸
        let rows: Int
        let cols: Int
        if case .object(let dims) = payload["dimensions"],
           case .int(let r) = dims["rows"],
           case .int(let c) = dims["cols"] {
            rows = r
            cols = c
        } else {
            rows = 0
            cols = 0
        }

        let snapshot = ScreenSnapshot(
            surfaceID: surfaceID,
            lines: lines,
            dimensions: ScreenSnapshot.Dimensions(rows: rows, cols: cols),
            timestamp: Date()
        )

        // 创建新字典而非修改现有字典（不可变原则）
        var updated = snapshots
        updated[surfaceID] = snapshot
        snapshots = updated
    }

    // MARK: - Surface/Workspace 列表更新

    /// 处理 Mac 推送的 surface 列表更新
    private func handleSurfaceListUpdate(_ payload: [String: AnyCodable]) {
        #if DEBUG
        print("[messageStore] handleSurfaceListUpdate, payload keys=\(payload.keys.sorted()), surfaces type=\(payload["surfaces"].map { "\($0)" } ?? "nil")")
        #endif
        // surfaces 可能是 AnyCodable 数组
        guard case .array(let surfacesArray) = payload["surfaces"] else {
            #if DEBUG
            print("[messageStore] surfaces 不是数组！")
            #endif
            // 也可能是嵌套在 result 中
            if case .object(let result) = payload["surfaces"],
               case .array(let arr) = result["surfaces"] {
                decodeSurfaces(arr)
            }
            return
        }
        decodeSurfaces(surfacesArray)
    }

    /// 将 AnyCodable 数组解码为 Surface 列表
    private func decodeSurfaces(_ surfacesArray: [AnyCodable]) {
        let decoded = surfacesArray.compactMap { item -> Surface? in
            guard case .object(let dict) = item else { return nil }
            do {
                let data = try JSONEncoder().encode(dict)
                let surface = try JSONDecoder().decode(Surface.self, from: data)
                return surface
            } catch {
                print("[messageStore] surface 解码失败: \(error)")
                print("[messageStore] surface dict keys: \(dict.keys.sorted())")
                return nil
            }
        }
        print("[messageStore] decodeSurfaces: \(surfacesArray.count) 条输入, \(decoded.count) 条成功")
        surfaces = decoded

        // 清理已消失 surface 的缓存数据，避免内存泄漏和显示陈旧数据
        let activeIDs = Set(decoded.map(\.id))
        snapshots = snapshots.filter { activeIDs.contains($0.key) }
        lastTerminalHash = lastTerminalHash.filter { activeIDs.contains($0.key) }
        lastCleanText = lastCleanText.filter { activeIDs.contains($0.key) }
        claudeChats = claudeChats.filter { activeIDs.contains($0.key) }
    }

    /// 处理 Mac 推送的 workspace 列表更新
    private func handleWorkspaceListUpdate(_ payload: [String: AnyCodable]) {
        // 暂时只打印，后续 workspace UI 接入时处理
        // workspace 数据会在终端列表中间接使用
    }

    // MARK: - Agent 审批事件处理

    /// 处理 agent.approval_required 事件，将请求交给 approvalManager
    private func handleApprovalRequired(_ payload: [String: AnyCodable]) {
        // 将 AnyCodable payload 转换为原始字典供 ApprovalRequest.from 使用
        let rawDict = anyCodableToRawDict(payload)
        guard let request = ApprovalRequest.from(eventPayload: rawDict) else { return }
        approvalManager?.addRequest(request)
    }

    /// 处理 agent.approval_resolved 事件（由对端解决，非本机操作）
    private func handleApprovalResolved(_ payload: [String: AnyCodable]) {
        guard case .string(let requestID) = payload["request_id"],
              case .string(let resolutionRaw) = payload["resolution"],
              let resolution = ApprovalResolution(rawValue: resolutionRaw) else { return }
        approvalManager?.markResolved(requestID: requestID, resolution: resolution)
    }

    /// 将 AnyCodable 字典转换为 [String: Any]
    private func anyCodableToRawDict(_ dict: [String: AnyCodable]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            switch value {
            case .null:         result[key] = NSNull()
            case .bool(let v):  result[key] = v
            case .int(let v):   result[key] = v
            case .double(let v): result[key] = v
            case .string(let v): result[key] = v
            case .array(let arr): result[key] = arr.map { anyCodableToAny($0) }
            case .object(let obj): result[key] = anyCodableToRawDict(obj)
            }
        }
        return result
    }

    /// 将单个 AnyCodable 值转换为 Any
    private func anyCodableToAny(_ value: AnyCodable) -> Any {
        switch value {
        case .null:         return NSNull()
        case .bool(let v):  return v
        case .int(let v):   return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let arr): return arr.map { anyCodableToAny($0) }
        case .object(let obj): return anyCodableToRawDict(obj)
        }
    }

    /// 处理 RPC 响应类型消息
    private func handleRPCResponse(_ payload: [String: AnyCodable]) {
        #if DEBUG
        print("[messageStore] rpc_response payload keys: \(payload.keys.sorted())")
        #endif
        // Mac Bridge 返回的格式：payload 直接包含 result 字段
        // 也可能 result 嵌套在 payload 中
        let result: [String: AnyCodable]
        if case .object(let r) = payload["result"] {
            result = r
            #if DEBUG
            print("[messageStore] result keys: \(r.keys.sorted())")
            #endif
        } else {
            // 尝试直接把 payload 当 result 用
            result = payload
            #if DEBUG
            print("[messageStore] 直接用 payload 作 result, keys: \(payload.keys.sorted())")
            #endif
        }

        // 处理 surface 列表响应
        if case .array(let surfacesArray) = result["surfaces"] {
            #if DEBUG
            print("[messageStore] 找到 surfaces 数组, 元素数=\(surfacesArray.count)")
            #endif
            let decoded = surfacesArray.compactMap { item -> Surface? in
                guard case .object(let dict) = item else {
                    #if DEBUG
                    print("[messageStore] surface 元素不是 object")
                    #endif
                    return nil
                }
                do {
                    let data = try JSONEncoder().encode(dict)
                    let surface = try JSONDecoder().decode(Surface.self, from: data)
                    return surface
                } catch {
                    #if DEBUG
                    print("[messageStore] surface 解码失败: \(error)")
                    // 打印原始 key 帮助调试
                    print("[messageStore] surface dict keys: \(dict.keys.sorted())")
                    #endif
                    return nil
                }
            }
            #if DEBUG
            print("[messageStore] 成功解码 \(decoded.count) 个 surface")
            #endif
            surfaces = decoded
            return
        }

        // C4: 处理 browser.screenshot / file.read 响应
        if case .string(let content) = result["content"] {
            let encoding: String
            if case .string(let enc) = result["encoding"] {
                encoding = enc
            } else {
                encoding = "utf8"
            }
            lastScreenshotContent = content
            lastScreenshotEncoding = encoding
            return
        }
    }

    // MARK: - 终端通知处理

    /// 处理 Mac 端转发的终端通知
    private func handleTerminalNotification(_ payload: [String: AnyCodable]) {
        let title: String
        if case .string(let t) = payload["title"] { title = t }
        else { title = "终端通知" }

        let body: String
        if case .string(let b) = payload["body"] { body = b }
        else { body = "" }

        let subtitle: String
        if case .string(let s) = payload["subtitle"] { subtitle = s }
        else { subtitle = "" }

        let displayBody = subtitle.isEmpty ? body : (body.isEmpty ? subtitle : "\(subtitle) — \(body)")

        // 添加到活动日志
        activityStore?.add(type: .notification, title: title, detail: displayBody)

        // 应用在后台时触发本地通知
        scheduleLocalNotification(title: title, body: displayBody)
    }

    /// 在应用后台时发送本地通知（前台时跳过，避免与活动日志重复）
    private func scheduleLocalNotification(title: String, body: String) {
        // 前台时不弹本地通知，活动日志已展示
        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "TERMINAL_NOTIFICATION"

        // 使用内容哈希作为标识符，相同内容覆盖而非堆叠
        let identifier = "notif-\(title.hashValue ^ body.hashValue)"

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[notification] 本地通知发送失败: \(error.localizedDescription)")
            }
        }
    }
}
