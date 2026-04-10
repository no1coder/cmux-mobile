import ActivityKit
import WidgetKit
import SwiftUI

struct CmuxLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CmuxActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.projectName)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            if context.state.activeSessions > 1 {
                                Text("\(context.state.activeSessions) 个会话")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let tool = context.state.toolName, context.state.phase == "tool_running" {
                            Label(String(tool.prefix(12)), systemImage: toolIcon(tool))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(phaseColor(context.state.phase))
                        } else {
                            Text(phaseLabel(context.state.phase))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(phaseColor(context.state.phase))
                        }
                        Text(context.state.startedAtDate, style: .timer)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let summary = context.state.lastAssistantSummary, !summary.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Circle()
                                .fill(phaseColor(context.state.phase))
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)
                            Text(summary)
                                .font(.system(size: 12))
                                .lineLimit(2)
                                .foregroundStyle(.primary.opacity(0.85))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
            } compactTrailing: {
                Text(compactTrailingText(context.state))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(phaseColor(context.state.phase))
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
            }
            .keylineTint(phaseColor(context.state.phase))
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<CmuxActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)
                Text(context.state.projectName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(phaseLabel(context.state.phase))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(phaseColor(context.state.phase))
                Text(context.state.startedAtDate, style: .timer)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            let hasMessages = (context.state.lastUserMessage != nil || context.state.lastAssistantSummary != nil)
            if hasMessages {
                Divider().background(.white.opacity(0.2))
                if let userMsg = context.state.lastUserMessage, !userMsg.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("You:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(userMsg)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                }
                if let assistant = context.state.lastAssistantSummary, !assistant.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("Claude:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.purple.opacity(0.8))
                        Text(assistant)
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                }
            }
        }
        .padding(14)
    }

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "thinking": return .purple
        case "tool_running": return .cyan
        case "waiting_approval": return .orange
        case "idle": return .gray
        case "ended": return .green
        case "error": return .red
        default: return .gray
        }
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "thinking": return "思考中"
        case "tool_running": return "执行工具"
        case "waiting_approval": return "需要审批"
        case "idle": return "空闲"
        case "ended": return "完成"
        case "error": return "出错"
        default: return phase
        }
    }

    private func compactTrailingText(_ state: CmuxActivityAttributes.ContentState) -> String {
        if let tool = state.toolName, state.phase == "tool_running" {
            return String(tool.prefix(7))
        }
        return String(phaseLabel(state.phase).prefix(7))
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder.badge.magnifyingglass"
        default: return "wrench"
        }
    }
}
