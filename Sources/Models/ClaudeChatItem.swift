import Foundation

/// Claude 聊天消息项（持久化在 MessageStore 中）
struct ClaudeChatItem: Identifiable, Equatable {
    let id: String
    let role: Role
    let content: String
    let timestamp: Date
    /// 工具执行结果（仅 tool 角色有值）
    let toolResult: String?
    /// 工具状态
    let toolState: ToolState
    /// 工具调用 ID（用于关联 tool_use 和 tool_result）
    let toolUseId: String?
    /// 工具完成时间（用于计算耗时）
    let completedAt: Date?
    /// 使用的模型名称（仅 assistant 消息有值）
    let modelName: String?

    enum Role: Equatable {
        case user
        case assistant
        case thinking  // Claude 的思考过程（extended thinking）
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
         toolResult: String? = nil, toolState: ToolState = .none, toolUseId: String? = nil,
         completedAt: Date? = nil, modelName: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolResult = toolResult
        self.toolState = toolState
        self.toolUseId = toolUseId
        self.completedAt = completedAt
        self.modelName = modelName
    }

    /// 工具执行耗时（秒），仅已完成的工具有值
    var durationSeconds: Double? {
        guard let completed = completedAt else { return nil }
        return completed.timeIntervalSince(timestamp)
    }

    static func == (lhs: ClaudeChatItem, rhs: ClaudeChatItem) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.toolState == rhs.toolState
    }
}
