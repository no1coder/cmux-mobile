import Foundation

/// Claude Code 会话中的消息类型
enum ClaudeMessageKind: String, Codable {
    /// 用户输入的文本
    case userText = "user-text"
    /// Claude 的回复文本
    case agentText = "agent-text"
    /// 工具调用（读文件、写文件、执行命令等）
    case toolCall = "tool-call"
    /// 系统事件（模式切换、状态变更等）
    case systemEvent = "system-event"
    /// 思考中状态
    case thinking = "thinking"
}

/// 工具调用状态
enum ToolCallState: String, Codable {
    case running
    case completed
    case error
    case permissionRequired = "permission_required"
}

/// Claude Code 聊天消息
struct ClaudeMessage: Identifiable, Equatable {
    let id: String
    let kind: ClaudeMessageKind
    let content: String
    let timestamp: Date
    /// 工具调用名称（仅 toolCall 类型有效）
    var toolName: String?
    /// 工具调用状态
    var toolState: ToolCallState?
    /// 工具输出结果
    var toolResult: String?

    static func == (lhs: ClaudeMessage, rhs: ClaudeMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.toolState == rhs.toolState
    }
}

/// Claude Code 会话状态
struct ClaudeSessionStatus: Equatable {
    var model: String = ""
    var contextUsage: String = ""
    var isActive: Bool = false
}
