import XCTest
@testable import cmux_models

final class RpcDedupTests: XCTestCase {

    func testDuplicateRequestIdIsRejected() {
        let dedup = RpcDedupCache()
        XCTAssertTrue(dedup.shouldSend("req-1"))
        XCTAssertFalse(dedup.shouldSend("req-1"))
    }

    func testDifferentRequestIdsAllowed() {
        let dedup = RpcDedupCache()
        XCTAssertTrue(dedup.shouldSend("req-1"))
        XCTAssertTrue(dedup.shouldSend("req-2"))
    }

    func testExpiredRequestIdAllowed() {
        let dedup = RpcDedupCache(ttlSeconds: 0)
        XCTAssertTrue(dedup.shouldSend("req-1"))
        dedup.cleanupExpired()
        XCTAssertTrue(dedup.shouldSend("req-1"))
    }

    func testCleanupRemovesExpiredOnly() {
        let longLived = RpcDedupCache(ttlSeconds: 3600)
        _ = longLived.shouldSend("req-long")

        let shortLived = RpcDedupCache(ttlSeconds: 0)
        _ = shortLived.shouldSend("req-short")

        longLived.cleanupExpired()
        shortLived.cleanupExpired()

        XCTAssertFalse(longLived.shouldSend("req-long"))  // 未过期
        XCTAssertTrue(shortLived.shouldSend("req-short"))  // 已过期
    }
}
