import SwiftUI

/// Write 工具渲染器 - 文件写入预览
struct WriteToolView: View {
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    private let maxPreviewLines = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 文件路径 + 标签
            filePathHeader

            // 内容预览
            if !content.isEmpty {
                contentPreview
            }

            // 状态
            if state == .running {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(.orange)
                    Text("写入中…")
                        .font(.system(size: 12))
                        .foregroundStyle(CMColors.textTertiary)
                }
                .padding(.horizontal, 12)
            } else if state == .completed {
                Label("写入完成", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var filePath: String {
        ToolInputParser.string(from: input, key: "file_path") ?? ""
    }

    private var content: String {
        ToolInputParser.string(from: input, key: "content") ?? ""
    }

    private var filePathHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
            Text(filePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CMColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("新建/覆写")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
    }

    private var contentPreview: some View {
        let allLines = content.components(separatedBy: "\n")
        let visibleLines = Array(allLines.prefix(maxPreviewLines))
        let truncated = allLines.count > maxPreviewLines

        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CMColors.textSecondary)
                    }
                }
                .padding(8)
            }
            .textSelection(.enabled)

            if truncated {
                Text("… 共 \(allLines.count) 行")
                    .font(.system(size: 10))
                    .foregroundStyle(CMColors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
        .background(CMColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
}
