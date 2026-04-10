import SwiftUI

/// 对话轮次视图 — 折叠态显示问题摘要 + 回复数，展开态显示全部回复
struct TurnView: View {
    let turn: ConversationTurn
    let isExpanded: Bool
    let onToggle: () -> Void
    let onToolTap: (ClaudeChatItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            turnHeader
            if isExpanded {
                repliesSection
            }
        }
    }

    // MARK: - Turn Header

    private var turnHeader: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 8) {
                // 左侧竖线
                RoundedRectangle(cornerRadius: 1)
                    .fill(turn.isSessionStart ? Color.purple.opacity(0.5) : Color.purple)
                    .frame(width: 2)
                    .frame(height: headerContentHeight)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // 角色标签
                        Text(turn.isSessionStart
                            ? String(localized: "turn.session_start", defaultValue: "会话开始")
                            : "YOU")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(CMColors.textTertiary)

                        Spacer()

                        // 回复计数
                        if turn.replyCount > 0 {
                            Text("\(turn.replyCount) 条回复")
                                .font(.system(size: 10))
                                .foregroundStyle(CMColors.textTertiary)
                        }

                        // 展开/折叠箭头
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CMColors.textTertiary)
                    }

                    // 问题文本预览
                    if let question = turn.question {
                        Text(question.content)
                            .font(.system(size: 14))
                            .foregroundStyle(CMColors.textPrimary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headerContentHeight: CGFloat {
        turn.question != nil ? 44 : 20
    }

    // MARK: - Replies Section

    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(turn.replies.enumerated()), id: \.element.id) { index, reply in
                VStack(spacing: 0) {
                    // 节奏间距：同类消息 2pt，类型切换 10pt
                    if index > 0 {
                        let prevRole = turn.replies[index - 1].role
                        let spacing: CGFloat = isSameRoleGroup(prevRole, reply.role) ? 2 : 10
                        Spacer().frame(height: spacing)
                    }

                    HStack(alignment: .top, spacing: 0) {
                        // 左侧连接线
                        Rectangle()
                            .fill(CMColors.textTertiary.opacity(0.15))
                            .frame(width: 1)
                            .padding(.leading, 1)

                        Spacer().frame(width: 9)

                        ChatMessageRow(msg: reply, onToolTap: onToolTap)
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    /// 判断两个 role 是否属于同一组
    private func isSameRoleGroup(_ a: ClaudeChatItem.Role, _ b: ClaudeChatItem.Role) -> Bool {
        switch (a, b) {
        case (.tool, .tool): return true
        case (.assistant, .assistant): return true
        case (.thinking, .thinking): return true
        default: return false
        }
    }
}
