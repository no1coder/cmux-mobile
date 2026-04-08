import Foundation

// MARK: - 枚举和模型

/// 审批结果
enum ApprovalResolution: String {
    case approved
    case rejected
    case expired
}

/// 待处理的审批请求
struct ApprovalRequest: Identifiable, Equatable {
    let requestID: String
    let agent: String
    let surfaceID: String
    let action: String
    let context: String
    let timestamp: Date
    let timeoutSeconds: Int

    var id: String { requestID }

    /// 是否已超过超时时间
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > Double(timeoutSeconds)
    }

    /// 从事件载荷字典构建 ApprovalRequest；字段缺失则返回 nil
    static func from(eventPayload: [String: Any]) -> ApprovalRequest? {
        guard
            let requestID = eventPayload["request_id"] as? String,
            let agent = eventPayload["agent"] as? String,
            let surfaceID = eventPayload["surface_id"] as? String,
            let action = eventPayload["action"] as? String,
            let context = eventPayload["context"] as? String
        else { return nil }

        let timeoutSeconds = eventPayload["timeout_seconds"] as? Int ?? 60

        return ApprovalRequest(
            requestID: requestID,
            agent: agent,
            surfaceID: surfaceID,
            action: action,
            context: context,
            timestamp: Date(),
            timeoutSeconds: timeoutSeconds
        )
    }
}

/// 已解决的审批请求记录
struct ResolvedRequest: Identifiable {
    let request: ApprovalRequest
    let resolution: ApprovalResolution
    let resolvedAt: Date

    var id: String { request.requestID }
}

// MARK: - ApprovalManager

/// 管理 Agent 审批流程，维护待处理和已解决的请求列表
@MainActor
final class ApprovalManager: ObservableObject {

    @Published var pendingRequests: [ApprovalRequest] = []
    @Published var resolvedRequests: [ResolvedRequest] = []
    @Published var policy: ApprovalPolicy = ApprovalPolicy.default

    /// 从 UserDefaults 加载审批策略
    func loadPolicy() {
        let autoReadOnly = UserDefaults.standard.bool(forKey: "approvalAutoReadOnly")
        let approveAll = UserDefaults.standard.bool(forKey: "approvalApproveAll")
        var newPolicy = ApprovalPolicy.default
        if !autoReadOnly {
            newPolicy.autoApproveTools = []
        }
        newPolicy.approveAllForSession = approveAll
        policy = newPolicy
    }

    /// 保存审批策略到 UserDefaults
    func savePolicy() {
        let hasReadOnly = policy.autoApproveTools.isSuperset(of: ApprovalPolicy.readOnlyTools)
        UserDefaults.standard.set(hasReadOnly, forKey: "approvalAutoReadOnly")
        UserDefaults.standard.set(policy.approveAllForSession, forKey: "approvalApproveAll")
    }

    // MARK: - 请求管理

    /// 添加新审批请求；相同 requestID 的请求不重复添加
    func addRequest(_ request: ApprovalRequest) {
        guard !pendingRequests.contains(where: { $0.requestID == request.requestID }) else {
            return
        }
        pendingRequests = pendingRequests + [request]
    }

    /// 将指定请求从待处理移至已解决列表
    func markResolved(requestID: String, resolution: ApprovalResolution) {
        guard let request = pendingRequests.first(where: { $0.requestID == requestID }) else {
            return
        }
        let resolved = ResolvedRequest(
            request: request,
            resolution: resolution,
            resolvedAt: Date()
        )
        pendingRequests = pendingRequests.filter { $0.requestID != requestID }
        resolvedRequests = resolvedRequests + [resolved]
    }

    /// 将所有已超时的待处理请求标记为 expired
    func cleanExpired() {
        let expiredIDs = pendingRequests
            .filter(\.isExpired)
            .map(\.requestID)

        for id in expiredIDs {
            markResolved(requestID: id, resolution: .expired)
        }
    }

    // MARK: - JSON-RPC Payload 构建

    /// 构建 agent.approve 的 JSON-RPC 载荷
    func buildApprovePayload(requestID: String) -> [String: Any] {
        [
            "method": "agent.approve",
            "params": ["request_id": requestID] as [String: Any]
        ]
    }

    /// 构建 agent.reject 的 JSON-RPC 载荷
    func buildRejectPayload(requestID: String) -> [String: Any] {
        [
            "method": "agent.reject",
            "params": ["request_id": requestID] as [String: Any]
        ]
    }
}
