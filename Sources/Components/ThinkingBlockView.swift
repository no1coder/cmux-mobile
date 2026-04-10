import SwiftUI

/// 思考过程展示视图 — 可折叠的 thinking 内容块
struct ThinkingBlockView: View {
    let content: String
    @State private var isExpanded = false

    /// 折叠时显示的预览行数
    private let previewLineCount = 3
    /// 折叠时显示的最大字符数
    private let previewCharCount = 150

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 思考图标
            thinkingIcon

            VStack(alignment: .leading, spacing: 6) {
                // 头部：标题 + 展开/折叠按钮
                headerView

                // 内容区域
                if isExpanded {
                    expandedContent
                } else {
                    collapsedPreview
                }
            }

            Spacer(minLength: 20)
        }
    }

    // MARK: - 子视图

    private var thinkingIcon: some View {
        ZStack {
            Circle()
                .fill(Color.purple.opacity(0.1))
                .frame(width: 26, height: 26)
            Image(systemName: "brain.head.profile")
                .font(.system(size: 11))
                .foregroundStyle(.purple.opacity(0.7))
        }
    }

    private var headerView: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.purple.opacity(0.6))

                Text(String(localized: "thinking.title", defaultValue: "思考过程"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.purple.opacity(0.7))

                // 字符数提示
                Text("(\(content.count) 字)")
                    .font(.system(size: 10))
                    .foregroundStyle(CMColors.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    /// 折叠时的预览
    private var collapsedPreview: some View {
        Group {
            let preview = makePreview()
            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(CMColors.textTertiary)
                    .lineLimit(previewLineCount)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
            }
        }
    }

    /// 展开时的完整内容
    private var expandedContent: some View {
        ScrollView {
            Text(content)
                .font(.system(size: 13))
                .foregroundStyle(CMColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(maxHeight: 400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - 辅助

    private func makePreview() -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= previewCharCount {
            return trimmed
        }
        return String(trimmed.prefix(previewCharCount)) + "…"
    }
}
