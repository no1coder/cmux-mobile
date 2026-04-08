import Foundation

/// 审批策略：控制哪些工具自动批准
struct ApprovalPolicy: Codable, Equatable {
    /// 自动批准的工具列表（如 Read, Glob, Grep 等只读工具）
    var autoApproveTools: Set<String> = ["Read", "Glob", "Grep", "WebSearch"]
    /// 是否为整个会话自动批准所有工具
    var approveAllForSession: Bool = false

    static let `default` = ApprovalPolicy()

    /// 默认的只读工具列表
    static let readOnlyTools: Set<String> = ["Read", "Glob", "Grep", "WebSearch"]

    /// 判断指定工具是否应该自动批准
    func shouldAutoApprove(toolName: String) -> Bool {
        if approveAllForSession { return true }
        return autoApproveTools.contains(toolName)
    }
}
