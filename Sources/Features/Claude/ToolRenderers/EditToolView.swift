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
        VStack(alignment: .leading, spacing: 0) {
            // 删除的行
            ForEach(Array(oldString.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                HStack(spacing: 4) {
                    Text("-")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.red.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
            }

            // 新增的行
            ForEach(Array(newString.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                HStack(spacing: 4) {
                    Text("+")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.green.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
}
