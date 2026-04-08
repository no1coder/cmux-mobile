import SwiftUI

/// Edit 工具渲染器 - 简单 diff 视图，红色删除绿色新增
struct EditToolView: View {
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 文件路径
            filePathHeader

            // Diff 视图
            if !oldString.isEmpty || !newString.isEmpty {
                diffView
            }

            // 执行状态
            if state == .running {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(.orange)
                    Text("编辑中…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
            } else if state == .completed {
                Label("编辑完成", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var filePath: String {
        ToolInputParser.string(from: input, key: "file_path") ?? ""
    }

    private var oldString: String {
        ToolInputParser.string(from: input, key: "old_string") ?? ""
    }

    private var newString: String {
        ToolInputParser.string(from: input, key: "new_string") ?? ""
    }

    private var filePathHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.line")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
            Text(filePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
    }

    private var diffView: some View {
        DiffCodeView(oldText: oldString, newText: newString, showLineNumbers: true)
            .padding(.horizontal, 12)
    }
}
