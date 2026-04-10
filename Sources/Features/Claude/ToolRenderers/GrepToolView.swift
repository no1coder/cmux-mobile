import SwiftUI

/// Grep 工具渲染器 - 搜索结果高亮
struct GrepToolView: View {
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 搜索参数
            searchHeader

            // 状态
            if state == .running {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(.cyan)
                    Text("搜索中…")
                        .font(.system(size: 12))
                        .foregroundStyle(CMColors.textTertiary)
                }
                .padding(.horizontal, 12)
            }

            // 搜索结果
            if let result, !result.isEmpty {
                resultList(result)
            } else if state == .completed {
                Text("无匹配结果")
                    .font(.system(size: 12))
                    .foregroundStyle(CMColors.textTertiary)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var pattern: String {
        ToolInputParser.string(from: input, key: "pattern") ?? input
    }

    private var searchPath: String {
        ToolInputParser.string(from: input, key: "path") ?? ""
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.cyan)
                Text(pattern)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            if !searchPath.isEmpty {
                Text("在 \(searchPath)")
                    .font(.system(size: 11))
                    .foregroundStyle(CMColors.textTertiary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func resultList(_ text: String) -> some View {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        let displayLines = Array(lines.prefix(100))

        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CMColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if lines.count > 100 {
                Text("… 共 \(lines.count) 条结果")
                    .font(.system(size: 10))
                    .foregroundStyle(CMColors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
        .background(CMColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
}
