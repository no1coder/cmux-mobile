import Foundation

/// 对话轮次 — 一个用户问题 + Claude 的所有回复（直到下一个用户消息）
struct ConversationTurn: Identifiable {
    let id: String
    let question: ClaudeChatItem?
    let replies: [ClaudeChatItem]
    /// 是否为会话开始（无用户问题，仅有助手初始消息）
    var isSessionStart: Bool { question == nil }
    /// 回复总数
    var replyCount: Int { replies.count }
    /// 该轮次在原始消息列表中的起始下标
    let firstIndex: Int

    /// 将消息列表按轮次分组
    /// 规则：每个 .user 消息开启新轮次；轮次前的非用户消息归入 session-start 轮次
    static func group(_ items: [ClaudeChatItem]) -> [ConversationTurn] {
        guard !items.isEmpty else { return [] }

        var turns: [ConversationTurn] = []
        /// 当前轮次的问题（.user 消息）
        var currentQuestion: ClaudeChatItem?
        /// 当前轮次收集到的回复
        var currentReplies: [ClaudeChatItem] = []
        /// 当前轮次在原始列表中的起始下标
        var currentFirstIndex = 0
        /// 第一个用户消息之前的非用户消息（session-start）
        var pendingReplies: [ClaudeChatItem] = []

        for (index, item) in items.enumerated() {
            if item.role == .user {
                if let question = currentQuestion {
                    // 保存上一个用户轮次
                    turns.append(ConversationTurn(
                        id: question.id,
                        question: question,
                        replies: currentReplies,
                        firstIndex: currentFirstIndex
                    ))
                } else if !pendingReplies.isEmpty {
                    // 保存 session-start 轮次
                    turns.append(ConversationTurn(
                        id: "__session_start__",
                        question: nil,
                        replies: pendingReplies,
                        firstIndex: 0
                    ))
                    pendingReplies = []
                }
                // 开启新轮次
                currentQuestion = item
                currentReplies = []
                currentFirstIndex = index
            } else {
                if currentQuestion != nil {
                    currentReplies.append(item)
                } else {
                    pendingReplies.append(item)
                }
            }
        }

        // 提交最后一个轮次
        if let question = currentQuestion {
            turns.append(ConversationTurn(
                id: question.id,
                question: question,
                replies: currentReplies,
                firstIndex: currentFirstIndex
            ))
        } else if !pendingReplies.isEmpty {
            turns.append(ConversationTurn(
                id: "__session_start__",
                question: nil,
                replies: pendingReplies,
                firstIndex: 0
            ))
        }

        return turns
    }
}
