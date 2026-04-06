import SwiftUI

/// 终端内容视图，渲染带 ANSI 颜色的终端输出，并在 inputEnabled 时显示输入工具栏
struct TerminalView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    // 追踪行数变化，用于触发滚动
    @State private var lineCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
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

            // 仅在输入启用时显示输入工具栏
            if inputManager.isInputEnabled {
                TerminalInputBar(
                    onSendText: { text in
                        let payload = inputManager.buildSendTextPayload(
                            surfaceID: surfaceID,
                            text: text
                        )
                        relayConnection.send(payload)
                    },
                    onSendKey: { key, mods in
                        let payload = inputManager.buildSendKeyPayload(
                            surfaceID: surfaceID,
                            key: key,
                            mods: mods
                        )
                        relayConnection.send(payload)
                    }
                )
                .environmentObject(inputManager)
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
