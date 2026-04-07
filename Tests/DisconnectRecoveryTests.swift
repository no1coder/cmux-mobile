import Testing
@testable import cmux_mobile

@MainActor
struct DisconnectRecoveryTests {

    // MARK: - 测试1：有 lastSeq 时应发送 resume

    @Test func shouldResumeWithLastSeq() {
        let recovery = DisconnectRecovery()
        recovery.lastSeq = 42

        let payload = recovery.buildResumePayload()

        #expect(payload["method"] as? String == "resume")

        let params = payload["params"] as? [String: Any]
        #expect(params != nil)
        #expect(params?["last_seq"] as? UInt64 == 42)
    }

    // MARK: - 测试2：lastSeq == 0 时应请求 read_screen（缓冲区已过期）

    @Test func shouldRequestScreenOnBufferExpired() {
        let recovery = DisconnectRecovery()
        // 默认 lastSeq == 0，表示没有历史缓冲

        #expect(recovery.shouldFallbackToReadScreen == true)

        let payload = recovery.buildReadScreenPayload(surfaceID: "surf-abc")
        #expect(payload["method"] as? String == "read_screen")

        let params = payload["params"] as? [String: Any]
        #expect(params?["surface_id"] as? String == "surf-abc")
    }

    // MARK: - 测试3：有 lastSeq 时不应回退到 read_screen

    @Test func shouldNotFallbackWhenHasSeq() {
        let recovery = DisconnectRecovery()
        recovery.lastSeq = 1

        #expect(recovery.shouldFallbackToReadScreen == false)
    }

    // MARK: - 测试4：buildReadScreenPayload 包含正确的 surfaceID 和 jsonrpc 字段

    @Test func buildReadScreenPayload() {
        let recovery = DisconnectRecovery()
        let surfaceID = "surf-xyz-999"

        let payload = recovery.buildReadScreenPayload(surfaceID: surfaceID)

        #expect(payload["jsonrpc"] as? String == "2.0")
        #expect(payload["method"] as? String == "read_screen")

        let params = payload["params"] as? [String: Any]
        #expect(params?["surface_id"] as? String == surfaceID)
    }

    // MARK: - 测试5：追踪断线持续时间

    @Test func trackDisconnectDuration() async throws {
        let recovery = DisconnectRecovery()

        // 断线前 duration 应为 0
        #expect(recovery.disconnectDuration == 0)
        #expect(recovery.isDisconnected == false)

        // 标记断线
        recovery.markDisconnected()
        #expect(recovery.isDisconnected == true)

        // 等待一小段时间，duration 应大于 0
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        #expect(recovery.disconnectDuration > 0)

        // 标记恢复后 duration 清零
        recovery.markReconnected()
        #expect(recovery.isDisconnected == false)
        #expect(recovery.disconnectDuration == 0)
    }
}
