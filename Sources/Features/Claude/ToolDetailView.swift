import SwiftUI

/// 工具执行详情页 — 显示完整的输入参数和执行结果
struct ToolDetailView: View {
    let toolName: String
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 工具头部
                header

                // 输入参数
                if !input.isEmpty {
                    section(title: "输入") {
                        codeBlock(input)
                    }
                }

                // 执行结果
                if let result, !result.isEmpty {
                    section(title: state == .error ? "错误" : "输出") {
                        codeBlock(result, isError: state == .error)
                    }
                } else if state == .running {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7).tint(.purple)
                        Text("执行中…")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                } else if state == .completed && (result == nil || result?.isEmpty == true) {
                    Text("执行完成，无输出")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 16)
                }

                Spacer()
            }
            .padding(.vertical, 16)
        }
        .background(CMColors.backgroundPrimary)
        .navigationTitle(toolName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            // 工具图标
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(toolColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: toolIcon)
                    .font(.system(size: 18))
                    .foregroundStyle(toolColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(toolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(stateLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(stateColor)
            }

            Spacer()

            // 状态图标
            stateIcon
        }
        .padding(.horizontal, 16)
    }

    private var stateLabel: String {
        switch state {
        case .running: return "执行中"
        case .completed: return "已完成"
        case .error: return "执行失败"
        case .none: return ""
        }
    }

    private var stateColor: Color {
        switch state {
        case .running: return .orange
        case .completed: return .green
        case .error: return .red
        case .none: return .gray
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .running:
            ProgressView().scaleEffect(0.8).tint(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20)).foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20)).foregroundStyle(.red)
        case .none:
            EmptyView()
        }
    }

    // MARK: - 代码块

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .padding(.horizontal, 16)
            content()
        }
    }

    private func codeBlock(_ text: String, isError: Bool = false) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isError ? .red.opacity(0.8) : .white.opacity(0.7))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white.opacity(isError ? 0.04 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    // MARK: - 工具图标和颜色

    private var toolIcon: String {
        switch toolName {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil.line"
        case "Bash": return "terminal"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder.badge.questionmark"
        case "Agent": return "person.2"
        case "Task": return "list.bullet"
        case "WebSearch": return "globe"
        case "WebFetch": return "globe.badge.chevron.backward"
        default: return "wrench"
        }
    }

    private var toolColor: Color {
        switch toolName {
        case "Read": return .blue
        case "Write", "Edit": return .orange
        case "Bash": return .green
        case "Grep", "Glob": return .cyan
        case "Agent", "Task": return .purple
        case "WebSearch", "WebFetch": return .indigo
        default: return .gray
        }
    }
}
