import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 聊天消息行视图 — 根据角色（用户/助手/工具/系统）渲染不同样式
struct ChatMessageRow: View {
    let msg: ClaudeChatItem
    let onToolTap: (ClaudeChatItem) -> Void

    var body: some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 50)
                Text(msg.content).font(.system(size: 15)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(CMColors.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                claudeAvatar
                VStack(alignment: .leading, spacing: 4) {
                    MarkdownView(content: msg.content).equatable()
                    // 模型名标签
                    if let model = msg.modelName, !model.isEmpty {
                        Text(model)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.purple.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                Spacer(minLength: 20)
            }
        case .thinking:
            ThinkingBlockView(content: msg.content)
        case .tool(name: let name):
            Button {
                onToolTap(msg)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Color.clear.frame(width: 26)
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: toolIcon(name)).font(.system(size: 10)).foregroundStyle(toolColor(name))
                                Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(CMColors.textSecondary)
                                // 工具执行耗时
                                if let duration = msg.durationSeconds {
                                    Text(formatDuration(duration))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(CMColors.textTertiary)
                                } else if msg.toolState == .running {
                                    // 运行中显示计时（隔离到独立视图，避免每秒刷新污染整个 ChatMessageRow）
                                    RunningDurationView(startTime: msg.timestamp)
                                }
                            }
                            if !msg.content.isEmpty {
                                Text(msg.content).font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(CMColors.textTertiary).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            // 工具执行 >60s 时显示"等待响应"提示，避免用户盯着 spinner 以为卡死
                            if msg.toolState == .running {
                                StaleToolBadge(startTime: msg.timestamp)
                            }
                        }
                        Spacer(minLength: 8)
                        // 状态图标
                        toolStateIcon(msg.toolState)
                    }
                    .padding(10).background(CMColors.tertiarySystemFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer(minLength: 20)
                }
            }
            .buttonStyle(.plain)
        case .system:
            HStack {
                Spacer()
                Text(msg.content).font(.system(size: 11)).foregroundStyle(CMColors.textTertiary)
                Spacer()
            }
        case .tuiOutput(let command):
            tuiOutputCard(command: command, content: msg.content)
        }
    }

    // MARK: - TUI 命令输出卡片

    @ViewBuilder
    private func tuiOutputCard(command: String, content: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear.frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(command)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CMColors.textSecondary)
                    Spacer(minLength: 0)
                }
                Text(content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CMColors.textPrimary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(CMColors.tertiarySystemFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
            )
            Spacer(minLength: 20)
        }
    }

    // MARK: - 辅助视图

    private var claudeAvatar: some View {
        ZStack {
            Circle().fill(Color.purple.opacity(0.15)).frame(width: 26, height: 26)
            Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.purple)
        }
    }

    @ViewBuilder
    private func toolStateIcon(_ state: ClaudeChatItem.ToolState) -> some View {
        switch state {
        case .running:
            ProgressView().scaleEffect(0.5).tint(.orange).frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green.opacity(0.6))
        case .error:
            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.red.opacity(0.6))
        case .none:
            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(CMColors.textTertiary)
        }
    }

    private func toolColor(_ name: String) -> Color {
        switch name {
        case "Read": return .blue
        case "Write", "Edit": return .orange
        case "Bash": return .green
        case "Grep", "Glob": return .cyan
        case "Agent", "Task": return .purple
        default: return .gray
        }
    }

    /// 格式化耗时（秒 → 可读文本）
    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 1 { return "<1s" }
        if seconds < 60 { return "\(Int(seconds))s" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m\(secs)s"
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder.badge.questionmark"
        case "Agent": return "person.2"
        default: return "terminal"
        }
    }
}

// MARK: - 超时警示

/// 工具执行 >60 秒仍未完成时显示"等待响应"徽标，>180 秒升级为"无响应"
private struct StaleToolBadge: View {
    let startTime: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 5)) { _ in
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 180 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("无响应超过 3 分钟，可尝试 Ctrl+C 中止")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.red.opacity(0.85))
                .padding(.top, 2)
            } else if elapsed > 60 {
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 9))
                    Text("等待响应中（\(Int(elapsed))s）")
                        .font(.system(size: 10))
                }
                .foregroundStyle(Color.orange.opacity(0.75))
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - 运行中耗时视图（隔离 TimelineView 的每秒刷新）

/// 独立的运行计时视图，避免 TimelineView 的 1 秒周期刷新传播到整个 ChatMessageRow
private struct RunningDurationView: View {
    let startTime: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            let elapsed = Date().timeIntervalSince(startTime)
            Text(Self.formatDuration(elapsed))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.7))
        }
    }

    /// 格式化耗时（秒 → 可读文本）
    static func formatDuration(_ seconds: Double) -> String {
        if seconds < 1 { return "<1s" }
        if seconds < 60 { return "\(Int(seconds))s" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m\(secs)s"
    }
}
