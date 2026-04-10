import SwiftUI

/// 通用工具渲染器 - 未知工具的回退显示
struct GenericToolView: View {
    let name: String
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    @State private var isInputExpanded = false
    @State private var isOutputExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 输入参数（可折叠）
            if !input.isEmpty {
                collapsibleSection(
                    title: "输入",
                    isExpanded: $isInputExpanded
                ) {
                    codeBlock(input)
                }
            }

            // 状态
            if state == .running {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(.gray)
                    Text("执行中…")
                        .font(.system(size: 12))
                        .foregroundStyle(CMColors.textTertiary)
                }
                .padding(.horizontal, 12)
            }

            // 输出
            if let result, !result.isEmpty {
                collapsibleSection(
                    title: state == .error ? "错误" : "输出",
                    isExpanded: $isOutputExpanded
                ) {
                    codeBlock(result, isError: state == .error)
                }
            }
        }
    }

    private func collapsibleSection(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(CMColors.textTertiary)
                .textCase(.uppercase)
            }
            .padding(.horizontal, 16)

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private func codeBlock(_ text: String, isError: Bool = false) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isError ? .red.opacity(0.8) : CMColors.textSecondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CMColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
}
