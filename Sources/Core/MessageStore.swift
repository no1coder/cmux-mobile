import Combine
import Foundation
import UIKit
import UserNotifications

private struct ClaudeChatCacheFile: Codable {
    let version: Int
    let sessions: [String: ClaudeChatCacheRecord]

    init(version: Int = 1, sessions: [String: ClaudeChatCacheRecord]) {
        self.version = version
        self.sessions = sessions
    }
}

private struct ClaudeChatCacheRecord: Codable {
    let messages: [ClaudeChatItem]
    let totalSeq: Int
    let updatedAt: Date
    let hasCompleteHistory: Bool?
}

/// 处理并存储来自 Relay 的消息，维护 surface 列表和屏幕快照
@MainActor
final class MessageStore: ObservableObject {

    @Published var surfaces: [Surface] = []
    @Published var snapshots: [String: ScreenSnapshot] = [:]
    @Published var lastSeq: UInt64 = 0
    /// 累计解码失败计数（envelope / surface / claude 消息等），用于设置页"诊断"区块展示
    /// 非 0 时提示用户"N 条消息解析失败"，帮助定位与 Mac 端协议漂移
    @Published var decodeFailures: Int = 0
    /// 最近一次解码失败的简短描述（前 120 字符），方便上报/排障
    @Published var lastDecodeFailure: String?

    /// Claude 聊天消息（按 surfaceID 索引，跨视图持久化）
    /// 写入请走 `setClaudeChat(_:messages:)` 以便自动裁剪到 maxClaudeChatSize
    @Published var claudeChats: [String: [ClaudeChatItem]] = [:]

    /// Claude 聊天的最近同步序号（按 surfaceID 索引）
    private var claudeChatSequences: [String: Int] = [:]

    /// Claude 聊天缓存是否包含完整历史（未被本地裁剪）
    private var claudeChatCompleteHistory: [String: Bool] = [:]

    /// 单个 surface 最多缓存多少条 Claude 消息。
    /// 这里采用更保守的裁剪策略，优先保证 Claude 聊天页能够回看更长历史，
    /// 再配合 UI 层的分页展示控制首屏渲染成本。
    static let maxClaudeChatSize = 16000

    /// 最多持久化多少个 Claude 会话缓存，避免缓存文件无限增长
    private static let maxPersistedClaudeSessions = 20

    /// Claude 聊天缓存文件路径
    private let claudeChatCacheURL: URL

    /// Claude 聊天缓存保存任务（防抖）
    private var claudeChatCacheSaveWorkItem: DispatchWorkItem?

    /// 超过此时间未刷新的 snapshot 视为过期，`pruneStaleSnapshots` 时清理
    /// 15 分钟是个保守阈值，足以覆盖用户切出去做别的事再回来的场景
    static let snapshotStalenessInterval: TimeInterval = 15 * 60

    /// 清理过期 snapshot，避免长期后台常驻时内存缓慢膨胀
    /// 调用时机：App 从后台回到前台时执行一次即可
    func pruneStaleSnapshots() {
        let cutoff = Date().addingTimeInterval(-Self.snapshotStalenessInterval)
        let fresh = snapshots.filter { $0.value.timestamp >= cutoff }
        if fresh.count != snapshots.count {
            print("[messageStore] 清理 \(snapshots.count - fresh.count) 条过期 snapshot")
            snapshots = fresh
        }
    }

    /// 写入指定 surface 的 Claude 聊天消息，自动裁剪到 maxClaudeChatSize
    /// 按时间顺序保留末尾（最新）部分
    func setClaudeChat(_ surfaceID: String, messages: [ClaudeChatItem], totalSeq: Int? = nil) {
        let trimmed: [ClaudeChatItem]
        if messages.count > Self.maxClaudeChatSize {
            trimmed = Array(messages.suffix(Self.maxClaudeChatSize))
        } else {
            trimmed = messages
        }

        let previousMessages = claudeChats[surfaceID] ?? []
        let previousSeq = claudeChatSequences[surfaceID]
        let previousHistoryCompleteness = claudeChatCompleteHistory[surfaceID]
        let nextSeq = totalSeq ?? previousSeq

        if trimmed.isEmpty {
            claudeChats.removeValue(forKey: surfaceID)
        } else {
            claudeChats[surfaceID] = trimmed
        }

        if let nextSeq {
            claudeChatSequences[surfaceID] = nextSeq
        } else if trimmed.isEmpty {
            claudeChatSequences.removeValue(forKey: surfaceID)
        }

        if trimmed.isEmpty {
            claudeChatCompleteHistory.removeValue(forKey: surfaceID)
        } else if messages.count > Self.maxClaudeChatSize {
            claudeChatCompleteHistory[surfaceID] = false
        }

        guard previousMessages != trimmed
            || previousSeq != claudeChatSequences[surfaceID]
            || previousHistoryCompleteness != claudeChatCompleteHistory[surfaceID] else { return }
        scheduleClaudeChatCacheSave()
    }

    /// 仅更新某个 Claude 会话的增量序号，用于下次进入会话时只拉取差量
    func setClaudeChatSequence(_ surfaceID: String, totalSeq: Int) {
        guard totalSeq >= 0 else { return }
        guard claudeChatSequences[surfaceID] != totalSeq else { return }
        claudeChatSequences[surfaceID] = totalSeq
        scheduleClaudeChatCacheSave()
    }

    /// 获取某个 Claude 会话最近一次持久化的总序号
    func claudeChatSequence(for surfaceID: String) -> Int {
        claudeChatSequences[surfaceID] ?? 0
    }

    func setClaudeChatHistoryCompleteness(_ surfaceID: String, hasCompleteHistory: Bool) {
        guard claudeChatCompleteHistory[surfaceID] != hasCompleteHistory else { return }
        claudeChatCompleteHistory[surfaceID] = hasCompleteHistory
        scheduleClaudeChatCacheSave()
    }

    func hasCompleteClaudeChatHistory(for surfaceID: String) -> Bool {
        claudeChatCompleteHistory[surfaceID] ?? false
    }

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

    /// Mac 端推送的能力快照（slash 命令列表）
    @Published var slashCommands: [[String: Any]] = []
    /// Mac 端推送的允许访问目录列表
    @Published var allowedDirectories: [String] = []

    /// C4: 关联的断线恢复管理器，由外部注入（弱引用避免循环）
    weak var recovery: DisconnectRecovery?

    // MARK: - file.list / browser.screenshot 响应数据

    /// C4: 最近一次 browser.screenshot 响应数据（content + encoding）
    @Published var lastScreenshotContent: String?
    @Published var lastScreenshotEncoding: String?

    init() {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        claudeChatCacheURL = cacheDirectory.appendingPathComponent("claude-chat-cache.json")

        let cache = Self.loadClaudeChatCache(from: claudeChatCacheURL)
        claudeChats = cache.messages
        claudeChatSequences = cache.sequences
        claudeChatCompleteHistory = cache.completeHistory
    }

    // MARK: - 消息处理

    /// 解析原始 JSON 数据，更新 seq 并按类型分发
    func processRawMessage(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(RelayEnvelope.self, from: data) else {
            // 计入解码失败计数并保留最近错误摘要，便于用户/诊断面板看到
            decodeFailures += 1
            if let text = String(data: data, encoding: .utf8) {
                lastDecodeFailure = String(text.prefix(120))
                #if DEBUG
                print("[messageStore] 解码失败: \(text.prefix(200))")
                #endif
            } else {
                lastDecodeFailure = "<binary>"
            }
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
        case "phase.update":
            handlePhaseUpdate(payload)
            return
        case "claude.messages.update":
            // 将 AnyCodable 转为原生字典，通过 onClaudeUpdate 分发
            let rawDict = anyCodableToRawDict(payload)
            onClaudeUpdate?(rawDict)

            // 驱动 Live Activity（从 status 字段推断阶段）
            let status: String
            if case .string(let s) = payload["status"] { status = s } else { status = "idle" }
            let surfaceId: String
            if case .string(let sid) = payload["surface_id"] { surfaceId = sid } else { surfaceId = "" }
            if !surfaceId.isEmpty {
                let phase: String
                switch status {
                case "thinking", "tool_running":
                    phase = status
                default:
                    phase = "idle"
                }
                LiveActivityManager.shared.updateGlobal(
                    activeSessionId: surfaceId,
                    projectName: "",
                    phase: phase
                )
            }
            return
        case "claude.model_switching", "claude.model_switched":
            // 模型切换事件：转发给 onClaudeUpdate 回调
            let rawDict = anyCodableToRawDict(payload)
            onClaudeUpdate?(rawDict)
            return
        case "capabilities.snapshot":
            handleCapabilitiesSnapshot(payload)
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
                decodeFailures += 1
                lastDecodeFailure = "surface: \(error.localizedDescription)"
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

    // MARK: - 阶段更新（驱动 Live Activity）

    /// 处理 Mac 端推送的阶段变化事件
    private func handlePhaseUpdate(_ payload: [String: AnyCodable]) {
        let surfaceId: String
        if case .string(let v) = payload["surface_id"] { surfaceId = v } else { surfaceId = "" }
        let phase: String
        if case .string(let v) = payload["phase"] { phase = v } else { phase = "idle" }
        let toolName: String?
        if case .string(let v) = payload["tool_name"] { toolName = v } else { toolName = nil }
        let projectName: String
        if case .string(let v) = payload["project_name"] { projectName = v } else { projectName = "" }
        let lastUserMessage: String?
        if case .string(let v) = payload["last_user_message"] { lastUserMessage = v } else { lastUserMessage = nil }
        let lastAssistantSummary: String?
        if case .string(let v) = payload["last_assistant_summary"] { lastAssistantSummary = v } else { lastAssistantSummary = nil }

        // 统计活跃 Claude session 数
        let claudeCount = surfaces.filter { $0.title.contains("Claude") }.count

        LiveActivityManager.shared.updateGlobal(
            activeSessionId: surfaceId,
            projectName: projectName,
            phase: phase,
            toolName: toolName,
            lastUserMessage: lastUserMessage,
            lastAssistantSummary: lastAssistantSummary,
            totalSessions: claudeCount,
            activeSessions: claudeCount
        )
    }

    // MARK: - 能力快照

    /// 处理 Mac 端推送的能力快照
    private func handleCapabilitiesSnapshot(_ payload: [String: AnyCodable]) {
        // 提取 slash_commands 数组
        guard case .array(let commands) = payload["slash_commands"] else { return }

        let parsed: [[String: Any]] = commands.compactMap { cmd -> [String: Any]? in
            guard case .object(let dict) = cmd else { return nil }
            var result: [String: Any] = [:]
            for (k, v) in dict {
                switch v {
                case .string(let s):  result[k] = s
                case .bool(let b):    result[k] = b
                case .int(let i):     result[k] = i
                case .double(let d):  result[k] = d
                case .array(let arr):
                    // 嵌套数组（如 args 列表）转为 [[String: Any]]
                    result[k] = arr.compactMap { item -> [String: Any]? in
                        guard case .object(let d) = item else { return nil }
                        var r: [String: Any] = [:]
                        for (dk, dv) in d {
                            if case .string(let s) = dv { r[dk] = s }
                        }
                        return r
                    }
                default: break
                }
            }
            return result
        }
        slashCommands = parsed
        print("[capabilities] 收到 \(parsed.count) 个 slash 命令")

        // 提取允许访问的目录列表
        if case .array(let dirs) = payload["allowed_directories"] {
            let dirList = dirs.compactMap { item -> String? in
                if case .string(let s) = item { return s }
                return nil
            }
            if !dirList.isEmpty {
                allowedDirectories = dirList
                print("[capabilities] 收到 \(dirList.count) 个允许目录")
            }
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
        activityStore?.add(type: .info, title: title, detail: displayBody)

        // 应用在后台时触发本地通知
        scheduleLocalNotification(title: title, body: displayBody)
    }

    /// 在应用后台时发送本地通知（前台时跳过，避免与活动日志重复）
    private func scheduleLocalNotification(title: String, body: String) {
        guard AppFeatureFlags.notificationsEnabled else { return }
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

    // MARK: - Claude 聊天缓存

    private func scheduleClaudeChatCacheSave() {
        claudeChatCacheSaveWorkItem?.cancel()

        let snapshot = makeClaudeChatCacheFile()
        let url = claudeChatCacheURL
        let workItem = DispatchWorkItem {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("[messageStore] Claude 聊天缓存保存失败: \(error)")
                #endif
            }
        }

        claudeChatCacheSaveWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func makeClaudeChatCacheFile() -> ClaudeChatCacheFile {
        let sessions = claudeChats.map { key, messages in
            let seq = claudeChatSequences[key] ?? 0
            let updatedAt = messages.last?.timestamp ?? .distantPast
            return (
                key,
                ClaudeChatCacheRecord(
                    messages: messages,
                    totalSeq: seq,
                    updatedAt: updatedAt,
                    hasCompleteHistory: claudeChatCompleteHistory[key]
                )
            )
        }
        .sorted { $0.1.updatedAt > $1.1.updatedAt }

        let limited = Dictionary(uniqueKeysWithValues: sessions.prefix(Self.maxPersistedClaudeSessions))
        return ClaudeChatCacheFile(sessions: limited)
    }

    private static func loadClaudeChatCache(from url: URL) -> (
        messages: [String: [ClaudeChatItem]],
        sequences: [String: Int],
        completeHistory: [String: Bool]
    ) {
        guard let data = try? Data(contentsOf: url) else {
            return ([:], [:], [:])
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(ClaudeChatCacheFile.self, from: data)
            let messages = file.sessions.mapValues(\.messages)
            let sequences = file.sessions.mapValues(\.totalSeq)
            let completeHistory = file.sessions.reduce(into: [String: Bool]()) { partial, entry in
                if let value = entry.value.hasCompleteHistory {
                    partial[entry.key] = value
                }
            }
            return (messages, sequences, completeHistory)
        } catch {
            #if DEBUG
            print("[messageStore] Claude 聊天缓存加载失败: \(error)")
            #endif
            return ([:], [:], [:])
        }
    }
}
