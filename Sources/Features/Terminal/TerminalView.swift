import SwiftUI

/// 终端内容视图，渲染带 ANSI 颜色的终端输出
struct TerminalView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore

    // 追踪行数变化，用于触发滚动
    @State private var lineCount: Int = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let lines = messageStore.snapshots[surfaceID]?.lines ?? []

                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(ANSIParser.parse(line))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }

                    // 底部锚点，用于自动滚动
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color.black)
            .onAppear {
                lineCount = messageStore.snapshots[surfaceID]?.lines.count ?? 0
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            // 使用 task 监听行数变化来自动滚动（跨平台兼容）
            .task(id: messageStore.snapshots[surfaceID]?.lines.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .navigationTitle(surfaceTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var surfaceTitle: String {
        messageStore.surfaces.first { $0.id == surfaceID }?.title ?? "终端"
    }
}
