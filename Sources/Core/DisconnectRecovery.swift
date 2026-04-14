import Combine
import Foundation

/// 管理断线恢复逻辑：追踪最后接收的序列号，判断是否需要读屏回退
@MainActor
final class DisconnectRecovery: ObservableObject {

    // MARK: - Published 属性

    /// 最后一次成功接收的消息序列号
    @Published var lastSeq: UInt64 = 0

    /// 当前是否处于断线状态
    @Published var isDisconnected: Bool = false

    // MARK: - 私有状态

    /// 断线发生时间
    private(set) var disconnectedAt: Date?

    // MARK: - 计算属性

    /// 当 lastSeq == 0 时，表示没有任何历史缓冲，需要回退到 read_screen
    var shouldFallbackToReadScreen: Bool {
        lastSeq == 0
    }

    /// 断线持续时间（秒），未断线或未记录时为 0
    var disconnectDuration: TimeInterval {
        guard let at = disconnectedAt else { return 0 }
        return Date().timeIntervalSince(at)
    }

    // MARK: - 状态变更

    /// 标记连接已断开，记录断线时间
    func markDisconnected() {
        isDisconnected = true
        disconnectedAt = Date()
    }

    /// 标记连接已恢复，清除断线时间
    func markReconnected() {
        isDisconnected = false
        disconnectedAt = nil
    }

    // MARK: - Payload 构建

    /// 构建断点续传 resume JSON-RPC payload
    func buildResumePayload() -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "method": "resume",
            "params": [
                "last_seq": lastSeq
            ]
        ]
    }

    /// 构建 read_screen JSON-RPC payload
    /// - Parameter surfaceID: 目标 surface 的 ID
    func buildReadScreenPayload(surfaceID: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "method": "read_screen",
            "params": [
                "surface_id": surfaceID
            ]
        ]
    }
}
