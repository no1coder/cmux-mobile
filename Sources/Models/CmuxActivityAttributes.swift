import ActivityKit
import Foundation

/// Live Activity 属性 — app 和 Widget Extension 共享
struct CmuxActivityAttributes: ActivityAttributes {
    /// 动态状态（通过 push 或本地更新）
    struct ContentState: Codable, Hashable {
        var activeSessionId: String
        var projectName: String
        var phase: String            // thinking | tool_running | waiting_approval | idle | ended | error
        var toolName: String?
        var lastUserMessage: String?
        var lastAssistantSummary: String?
        var totalSessions: Int
        var activeSessions: Int
        var startedAt: TimeInterval

        var startedAtDate: Date {
            Date(timeIntervalSince1970: startedAt)
        }
    }

    /// 静态属性（创建时设置，不再变化）
    var serverName: String
}
