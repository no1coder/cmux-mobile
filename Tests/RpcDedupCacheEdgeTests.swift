import XCTest
@testable import cmux_models

final class RpcDedupCacheEdgeTests: XCTestCase {

    func testResetClearsAll() {
        let cache = RpcDedupCache()
        _ = cache.shouldSend("r1")
        _ = cache.shouldSend("r2")
        cache.reset()
        // reset 后同样 id 应被允许通过
        XCTAssertTrue(cache.shouldSend("r1"))
        XCTAssertTrue(cache.shouldSend("r2"))
    }

    func testHighVolume() {
        let cache = RpcDedupCache()
        // 首次发送 200 个不同 id，全部通过
        for i in 0..<200 {
            XCTAssertTrue(cache.shouldSend("req-\(i)"), "req-\(i) 首次应通过")
        }
        // 第二次发送相同 id，全部拒绝
        for i in 0..<200 {
            XCTAssertFalse(cache.shouldSend("req-\(i)"), "req-\(i) 重复应被拒绝")
        }
    }

    func testEmptyStringRequestId() {
        let cache = RpcDedupCache()
        // 空字符串也是合法 requestId，应正常去重
        XCTAssertTrue(cache.shouldSend(""))
        XCTAssertFalse(cache.shouldSend(""))
    }

    func testResetAllowsReuseAfterHighVolume() {
        // 大量写入后 reset，保证状态被完全清空
        let cache = RpcDedupCache()
        for i in 0..<50 {
            _ = cache.shouldSend("id-\(i)")
        }
        cache.reset()
        for i in 0..<50 {
            XCTAssertTrue(cache.shouldSend("id-\(i)"), "reset 后 id-\(i) 应再次通过")
        }
    }
}
