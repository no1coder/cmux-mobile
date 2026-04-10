import Testing
import Foundation
@testable import cmux_mobile

@Suite("OfflineMessageQueue Tests")
@MainActor
struct OfflineMessageQueueTests {

    // MARK: - 入队测试

    @Test("入队后 pendingCount 增加")
    func enqueueIncrementsCount() {
        let queue = OfflineMessageQueue()
        queue.enqueue(["msg": "hello"])
        #expect(queue.pendingCount == 1)
        #expect(queue.isEmpty == false)
    }

    @Test("多次入队计数正确")
    func multipleEnqueue() {
        let queue = OfflineMessageQueue()
        for i in 0..<5 {
            queue.enqueue(["index": i])
        }
        #expect(queue.pendingCount == 5)
    }

    @Test("超过 maxQueueSize 时静默丢弃")
    func enqueueOverflowDrops() {
        let queue = OfflineMessageQueue()
        for i in 0..<110 {
            queue.enqueue(["index": i])
        }
        // 最大 100 条
        #expect(queue.pendingCount == 100)
    }

    // MARK: - flush 测试

    @Test("flush 按顺序发送所有消息")
    func flushSendsInOrder() {
        let queue = OfflineMessageQueue()
        for i in 0..<3 {
            queue.enqueue(["index": i])
        }

        var received: [[String: Any]] = []
        queue.flush { msg in
            received.append(msg)
        }

        #expect(received.count == 3)
        #expect(received[0]["index"] as? Int == 0)
        #expect(received[1]["index"] as? Int == 1)
        #expect(received[2]["index"] as? Int == 2)
        #expect(queue.pendingCount == 0)
        #expect(queue.isEmpty == true)
    }

    @Test("flush 空队列不调用回调")
    func flushEmptyQueueNoop() {
        let queue = OfflineMessageQueue()
        var callCount = 0
        queue.flush { _ in callCount += 1 }
        #expect(callCount == 0)
    }

    // MARK: - clear 测试

    @Test("clear 清空队列")
    func clearResetsQueue() {
        let queue = OfflineMessageQueue()
        queue.enqueue(["a": 1])
        queue.enqueue(["b": 2])
        #expect(queue.pendingCount == 2)

        queue.clear()
        #expect(queue.pendingCount == 0)
        #expect(queue.isEmpty == true)
    }

    @Test("clear 后可重新入队")
    func clearThenReenqueue() {
        let queue = OfflineMessageQueue()
        queue.enqueue(["first": true])
        queue.clear()
        queue.enqueue(["second": true])

        #expect(queue.pendingCount == 1)

        var received: [[String: Any]] = []
        queue.flush { msg in received.append(msg) }
        #expect(received.count == 1)
        #expect(received[0]["second"] as? Bool == true)
    }

    // MARK: - isEmpty 测试

    @Test("新建队列为空")
    func newQueueIsEmpty() {
        let queue = OfflineMessageQueue()
        #expect(queue.isEmpty == true)
        #expect(queue.pendingCount == 0)
    }
}
