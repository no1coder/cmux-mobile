import Testing
import Foundation
@testable import cmux_mobile

@Suite("ApprovalManager Tests")
struct ApprovalManagerTests {

    // MARK: - 测试辅助方法

    private func makeRequest(
        id: String = "req-1",
        agent: String = "cmux-omx",
        action: String = "bash: ls",
        context: String = "工作目录",
        timeoutSeconds: Int = 30
    ) -> ApprovalRequest {
        ApprovalRequest(
            requestID: id,
            agent: agent,
            surfaceID: "surf-1",
            action: action,
            context: context,
            timestamp: Date(),
            timeoutSeconds: timeoutSeconds
        )
    }

    // MARK: - addRequest 测试

    @Test("添加待处理请求")
    func addPendingRequest() {
        let manager = ApprovalManager()
        let request = makeRequest()
        manager.addRequest(request)

        #expect(manager.pendingRequests.count == 1)
        #expect(manager.pendingRequests.first?.requestID == "req-1")
    }

    @Test("重复 requestID 不重复添加")
    func noDuplicateRequest() {
        let manager = ApprovalManager()
        let request = makeRequest()
        manager.addRequest(request)
        manager.addRequest(request)

        #expect(manager.pendingRequests.count == 1)
    }

    // MARK: - 审批/拒绝测试

    @Test("审批请求后移入已解决列表")
    func approveRequest() {
        let manager = ApprovalManager()
        manager.addRequest(makeRequest(id: "req-approve"))
        manager.markResolved(requestID: "req-approve", resolution: .approved)

        #expect(manager.pendingRequests.isEmpty)
        #expect(manager.resolvedRequests.count == 1)
        #expect(manager.resolvedRequests.first?.resolution == .approved)
    }

    @Test("拒绝请求后移入已解决列表")
    func rejectRequest() {
        let manager = ApprovalManager()
        manager.addRequest(makeRequest(id: "req-reject"))
        manager.markResolved(requestID: "req-reject", resolution: .rejected)

        #expect(manager.pendingRequests.isEmpty)
        #expect(manager.resolvedRequests.count == 1)
        #expect(manager.resolvedRequests.first?.resolution == .rejected)
    }

    // MARK: - 过期测试

    @Test("cleanExpired 将超时请求标记为 expired")
    func expiredRequest() {
        let manager = ApprovalManager()
        // 创建已过期的请求（timestamp 早于 timeoutSeconds）
        let expiredRequest = ApprovalRequest(
            requestID: "req-expired",
            agent: "agent",
            surfaceID: "surf-1",
            action: "action",
            context: "ctx",
            timestamp: Date().addingTimeInterval(-60),  // 60 秒前
            timeoutSeconds: 30                           // 30 秒超时
        )
        manager.addRequest(expiredRequest)
        #expect(expiredRequest.isExpired == true)

        manager.cleanExpired()

        #expect(manager.pendingRequests.isEmpty)
        #expect(manager.resolvedRequests.first?.resolution == .expired)
    }

    // MARK: - JSON-RPC Payload 测试

    @Test("buildApprovePayload 生成正确的 JSON-RPC")
    func buildApprovePayload() {
        let manager = ApprovalManager()
        let payload = manager.buildApprovePayload(requestID: "req-42")

        #expect(payload["method"] as? String == "agent.approve")
        let params = payload["params"] as? [String: Any]
        #expect(params?["request_id"] as? String == "req-42")
    }

    @Test("buildRejectPayload 生成正确的 JSON-RPC")
    func buildRejectPayload() {
        let manager = ApprovalManager()
        let payload = manager.buildRejectPayload(requestID: "req-43")

        #expect(payload["method"] as? String == "agent.reject")
        let params = payload["params"] as? [String: Any]
        #expect(params?["request_id"] as? String == "req-43")
    }

    // MARK: - 事件解析测试

    @Test("从事件载荷解析 ApprovalRequest")
    func parseApprovalEvent() {
        let payload: [String: Any] = [
            "request_id": "req-parse",
            "agent": "cmux-omc",
            "surface_id": "surf-2",
            "action": "rm -rf /tmp/test",
            "context": "清理临时文件",
            "timeout_seconds": 60
        ]

        let request = ApprovalRequest.from(eventPayload: payload)
        #expect(request != nil)
        #expect(request?.requestID == "req-parse")
        #expect(request?.agent == "cmux-omc")
        #expect(request?.action == "rm -rf /tmp/test")
        #expect(request?.timeoutSeconds == 60)
    }

    @Test("载荷缺少必填字段时返回 nil")
    func parseApprovalEventMissingFields() {
        let payload: [String: Any] = [
            "agent": "cmux-omc"
            // 缺少 request_id 等必填字段
        ]
        let request = ApprovalRequest.from(eventPayload: payload)
        #expect(request == nil)
    }
}
