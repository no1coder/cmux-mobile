import Foundation

/// 处理并存储来自 Relay 的消息，维护 surface 列表和屏幕快照
@MainActor
final class MessageStore: ObservableObject {

    @Published var surfaces: [Surface] = []
    @Published var snapshots: [String: ScreenSnapshot] = [:]
    @Published var lastSeq: UInt64 = 0

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
        guard case .string(let event) = payload["event"],
              event == "screen.snapshot" else { return }

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
