import SwiftUI

/// Glob 工具渲染器 - 文件列表以紧凑标签展示
struct GlobToolView: View {
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 匹配模式
            patternHeader

            // 状态
            if state == .running {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(.cyan)
                    Text("匹配中…")
                        .font(.system(size: 12))
                        .foregroundStyle(CMColors.textTertiary)
                }
                .padding(.horizontal, 12)
            }

            // 文件列表
            if let result, !result.isEmpty {
                fileChips(result)
            } else if state == .completed {
                Text("无匹配文件")
                    .font(.system(size: 12))
                    .foregroundStyle(CMColors.textTertiary)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var pattern: String {
        ToolInputParser.string(from: input, key: "pattern") ?? input
    }

    private var patternHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 12))
                .foregroundStyle(.cyan)
            Text(pattern)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.cyan)
        }
        .padding(.horizontal, 16)
    }

    private func fileChips(_ text: String) -> some View {
        let files = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        let displayFiles = Array(files.prefix(50))

        return VStack(alignment: .leading, spacing: 8) {
            // 使用 FlowLayout 风格 - 简化版用 VStack 包 HStack
            WrappingHStack(items: displayFiles) { file in
                Text(fileName(from: file))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CMColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CMColors.backgroundSecondary)
                    .clipShape(Capsule())
            }

            if files.count > 50 {
                Text("… 共 \(files.count) 个文件")
                    .font(.system(size: 10))
                    .foregroundStyle(CMColors.textTertiary)
            }
        }
        .padding(.horizontal, 12)
    }

    /// 从完整路径提取文件名
    private func fileName(from path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return (trimmed as NSString).lastPathComponent
    }
}

/// 简单的流式布局 - 将元素排成多行
private struct WrappingHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        // 简化实现：使用 LazyVGrid
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
