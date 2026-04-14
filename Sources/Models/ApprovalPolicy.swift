import Foundation

/// 审批策略：控制哪些工具自动批准
public struct ApprovalPolicy: Codable, Equatable {
    /// 自动批准的工具列表（如 Read, Glob, Grep 等只读工具）
    public var autoApproveTools: Set<String> = ["Read", "Glob", "Grep", "WebSearch"]
    /// 是否为整个会话自动批准所有工具
    public var approveAllForSession: Bool = false

    public static let `default` = ApprovalPolicy()

    /// 默认的只读工具列表
    public static let readOnlyTools: Set<String> = ["Read", "Glob", "Grep", "WebSearch"]

    public init(
        autoApproveTools: Set<String> = ["Read", "Glob", "Grep", "WebSearch"],
        approveAllForSession: Bool = false
    ) {
        self.autoApproveTools = autoApproveTools
        self.approveAllForSession = approveAllForSession
    }

    /// 判断指定工具是否应该自动批准
    public func shouldAutoApprove(toolName: String) -> Bool {
        if approveAllForSession { return true }
        return autoApproveTools.contains(toolName)
    }
}
