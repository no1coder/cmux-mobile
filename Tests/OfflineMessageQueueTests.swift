import Testing
import Foundation
#if canImport(cmux_mobile)
@testable import cmux_mobile
#elseif canImport(cmux_core)
@testable import cmux_core
#endif

@Suite("OfflineMessageQueue Tests")
@MainActor
struct OfflineMessageQueueTests {

    /// 每个测试使用独立的 storageURL，避免相互污染
    private func makeIsolatedURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-offline-queue-tests-\(UUID().uuidString).json")
    }

    private func makeQueue(url: URL) -> OfflineMessageQueue {
        OfflineMessageQueue(storageURL: url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 等待防抖写盘完成（saveDebounceInterval = 0.2s）
    private func waitForDiskWrite() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    // MARK: - 入队测试

    @Test("入队后 pendingCount 增加")
    func enqueueIncrementsCount() {
        let url = makeIsolatedURL()
        defer { cleanup(url) }
        let queue = makeQueue(url: url)
        queue.enqueue(["msg": "hello"])
        #expect(queue.pendingCount == 1)
        #expect(queue.isEmpty == false)
    }

    @Test("多次入队计数正确")
    func multipleEnqueue() {
        let url = makeIsolatedURL()
        defer { cleanup(url) }
        let queue = makeQueue(url: url)
        for i in 0..<5 {
            queue.enqueue(["index": i])
        }
        #expect(queue.pendingCount == 5)
    }

    @Test("超过 maxQueueSize 时静默丢弃")
    func enqueueOverflowDrops() {
        let url = makeIsolatedURL()
        defer { cleanup(url) }
        let queue = makeQueue(url: url)
        for i in 0..<110 {
            queue.enqueue(["index": i])
        }
        #expect(queue.pendingCount == 100)
    }

    // MARK: - flush 测试

    @Test("flush 按顺序发送所有消息")
    func flushSendsInOrder() {
        let url = makeIsolatedURL()
        defer { cleanup(url) }
        let queue = makeQueue(url: url)
        for i in 0..<3 {
            queue.enqueue(["index": i])
        }

        var received: [[String: Any]] = []
        queue.flush { msg in
            received.append(msg)
            return true
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
        let url = makeIsolatedURL()
        defer { cleanup(url) }
        let queue = makeQueue(url: url)
        var callCount = 0
        queue.flush { _ in
            callCount += 1
            return true
        }
        #expect(callCount == 0)
    }

    @Test("flush 遇到发送失败时保留未发送消息")
    func flushRetainsMessagesWhenSendFails() {
        let url = makeIsolatedURL()
        defer { cleanup(url) }
        let queue = makeQueue(url: url)
        for i in 0..<3 {
            queue.enqueue(["index": i])
        }

        var received: [Int] = []
        queue.flush { msg in
            let index = msg["index"] as? Int ?? -1
            guard index == 0 else { return false }
            received.append(index)
            return true
        }

        #expect(received == [0])
        #expect(queue.pendingCount == 2)
        #expect(queue.isEmpty == false)
    }

    // MARK: - clear 测试

    @Test("clear 清空队列")
    func clearResetsQueue() {
        let url = makeIsolatedURL()
        defer { cleanup(url) }
        let queue = makeQueue(url: url)
        queue.enqueue(["a": 1])
        queue.enqueue(["b": 2])
        #expect(queue.pendingCount == 2)

        queue.clear()
        #expect(queue.pendingCount == 0)
        #expect(queue.isEmpty == true)
    }

    @Test("clear 后可重新入队")
    func clearThenReenqueue() {
        let url = makeIsolatedURL()
        defer { cleanup(url) }
        let queue = makeQueue(url: url)
        queue.enqueue(["first": true])
        queue.clear()
        queue.enqueue(["second": true])

        #expect(queue.pendingCount == 1)

        var received: [[String: Any]] = []
        queue.flush { msg in
            received.append(msg)
            return true
        }
        #expect(received.count == 1)
        #expect(received[0]["second"] as? Bool == true)
    }

    // MARK: - isEmpty 测试

    @Test("新建队列为空")
    func newQueueIsEmpty() {
        let url = makeIsolatedURL()
        defer { cleanup(url) }
        let queue = makeQueue(url: url)
        #expect(queue.isEmpty == true)
        #expect(queue.pendingCount == 0)
    }

    // MARK: - 持久化测试

    @Test("enqueue 后重新构造同 URL 的 queue，内容应恢复")
    func persistenceAcrossInstances() async {
        let url = makeIsolatedURL()
        defer { cleanup(url) }

        let first = makeQueue(url: url)
        first.enqueue(["msg": "a", "index": 1])
        first.enqueue(["msg": "b", "index": 2])
        #expect(first.pendingCount == 2)

        // 等待防抖写盘完成
        await waitForDiskWrite()

        // 构造第二个实例读取同一文件
        let second = makeQueue(url: url)
        #expect(second.pendingCount == 2)

        var received: [[String: Any]] = []
        second.flush { msg in
            received.append(msg)
            return true
        }
        #expect(received.count == 2)
        #expect(received[0]["msg"] as? String == "a")
        #expect(received[1]["msg"] as? String == "b")
    }

    @Test("含非 JSON-safe 值（NaN/无穷）的消息会被持久化层过滤")
    func nonJSONSafeValuesFiltered() async {
        let url = makeIsolatedURL()
        defer { cleanup(url) }

        let first = makeQueue(url: url)
        // 第一条合法
        first.enqueue(["msg": "ok", "value": 42])
        // 第二条含 NaN，不是 JSON-safe
        first.enqueue(["msg": "bad", "value": Double.nan])
        // 第三条含无穷大，不是 JSON-safe
        first.enqueue(["msg": "bad2", "value": Double.infinity])

        // 运行时计数仍然包含所有入队项（过滤仅发生在写盘快照）
        #expect(first.pendingCount == 3)

        // 等写盘完成
        await waitForDiskWrite()

        // 重新构造：从磁盘加载应只剩 JSON-safe 的一条
        let second = makeQueue(url: url)
        #expect(second.pendingCount == 1)

        var received: [[String: Any]] = []
        second.flush { msg in
            received.append(msg)
            return true
        }
        #expect(received.count == 1)
        #expect(received[0]["msg"] as? String == "ok")
    }
}
