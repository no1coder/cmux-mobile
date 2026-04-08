import Foundation

/// 离线消息队列：断线时缓存消息，重连后按序发送
@MainActor
final class OfflineMessageQueue: ObservableObject {
    /// 队列中待发送的消息
    @Published private(set) var pendingCount: Int = 0

    private var queue: [[String: Any]] = []
    private let maxQueueSize = 100

    /// 入队消息（断线时调用）
    func enqueue(_ message: [String: Any]) {
        guard queue.count < maxQueueSize else { return }
        queue.append(message)
        pendingCount = queue.count
    }

    /// 重连后批量发送所有排队消息
    func flush(using send: ([String: Any]) -> Void) {
        let messages = queue
        queue = []
        pendingCount = 0
        for msg in messages {
            send(msg)
        }
    }

    /// 清空队列
    func clear() {
        queue = []
        pendingCount = 0
    }

    var isEmpty: Bool { queue.isEmpty }
}
