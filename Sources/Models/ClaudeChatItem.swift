import Foundation

/// Claude 聊天消息项（持久化在 MessageStore 中）
struct ClaudeChatItem: Identifiable, Equatable {
    let id: String
    let role: Role
    let content: String
    let timestamp: Date
    /// 工具执行结果（仅 tool 角色有值）
    var toolResult: String?
    /// 工具状态
    var toolState: ToolState
    /// 工具调用 ID（用于关联 tool_use 和 tool_result）
    var toolUseId: String?

    enum Role: Equatable {
        case user
        case assistant
        case tool(name: String)
        case system
    }

    enum ToolState: Equatable {
        case running
        case completed
        case error
        case none
    }

    init(id: String, role: Role, content: String, timestamp: Date,
         toolResult: String? = nil, toolState: ToolState = .none, toolUseId: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolResult = toolResult
        self.toolState = toolState
        self.toolUseId = toolUseId
    }

    static func == (lhs: ClaudeChatItem, rhs: ClaudeChatItem) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.toolState == rhs.toolState
    }
}
