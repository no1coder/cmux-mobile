import SwiftUI

/// Read 工具渲染器 - 文件内容预览，带行号
struct ReadToolView: View {
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    /// 默认最多显示行数
    private let maxPreviewLines = 50
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 文件路径
            filePathHeader

            // 文件内容
            if state == .running {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(.blue)
                    Text("读取中…")
                        .font(.system(size: 12))
                        .foregroundStyle(CMColors.textTertiary)
                }
                .padding(.horizontal, 12)
            } else if let result, !result.isEmpty {
                contentPreview(result)
            }
        }
    }

    private var filePath: String {
        ToolInputParser.string(from: input, key: "file_path") ?? input
    }

    private var filePathHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(.blue)
            Text(filePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CMColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
    }

    private func contentPreview(_ text: String) -> some View {
        let allLines = text.components(separatedBy: "\n")
        let visibleLines = isExpanded ? allLines : Array(allLines.prefix(maxPreviewLines))
        let needsExpand = allLines.count > maxPreviewLines

        return VStack(alignment: .leading, spacing: 0) {
            // 带行号的内容
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { idx, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(CMColors.textTertiary)
                                .frame(width: 36, alignment: .trailing)
                            Text(" \(line)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(CMColors.textSecondary)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .textSelection(.enabled)

            // 展开/折叠按钮
            if needsExpand {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded ? "收起" : "显示全部 (\(allLines.count) 行)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(CMColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
}
