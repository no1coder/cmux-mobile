import Foundation

/// 处理并存储来自 Relay 的消息，维护 surface 列表和屏幕快照
@MainActor
final class MessageStore: ObservableObject {

    @Published var surfaces: [Surface] = []
    @Published var snapshots: [String: ScreenSnapshot] = [:]
    @Published var lastSeq: UInt64 = 0

    /// 关联的审批管理器，由外部注入（弱引用避免循环）
    weak var approvalManager: ApprovalManager?

    // MARK: - 消息处理

    /// 解析原始 JSON 数据，更新 seq 并按类型分发
    func processRawMessage(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(RelayEnvelope.self, from: data) else {
            return
        }

        // 更新最新序列号
        if envelope.seq > lastSeq {
            lastSeq = envelope.seq
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
        guard case .object(let result) = payload["result"],
              case .array(let surfacesArray) = result["surfaces"] else { return }

        // 将 AnyCodable 数组重新编码为 Surface 模型数组
        let decoded = surfacesArray.compactMap { item -> Surface? in
            guard case .object(let dict) = item else { return nil }
            guard let data = try? JSONEncoder().encode(dict),
                  let surface = try? JSONDecoder().decode(Surface.self, from: data) else {
                return nil
            }
            return surface
        }

        surfaces = decoded
    }
}
