import Foundation

/// Claude 聊天消息项（持久化在 MessageStore 中）
struct ClaudeChatItem: Identifiable, Equatable {
    let id: String
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: Equatable {
        case user
        case assistant
        case tool(name: String)
        case system
    }

    static func == (lhs: ClaudeChatItem, rhs: ClaudeChatItem) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content
    }
}
