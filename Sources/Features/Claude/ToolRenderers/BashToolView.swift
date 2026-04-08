import SwiftUI

/// Bash 工具渲染器 - 终端风格显示命令和输出
struct BashToolView: View {
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 命令输入 - 终端风格
            commandBlock

            // 执行状态
            if state == .running {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(.green)
                    Text("执行中…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.6))
                }
                .padding(.horizontal, 12)
            }

            // 输出结果
            if let result, !result.isEmpty {
                outputBlock(result)
            }
        }
    }

    /// 解析 JSON 输入中的 command 字段
    private var command: String {
        ToolInputParser.string(from: input, key: "command") ?? input
    }

    private var commandBlock: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("$")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.green.opacity(0.9))
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    private func outputBlock(_ text: String) -> some View {
        let isError = state == .error
        return ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isError ? .red.opacity(0.8) : .white.opacity(0.7))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white.opacity(isError ? 0.04 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
}
