import SwiftUI

/// 终端内容视图，渲染带 ANSI 颜色的终端输出，底部带输入工具栏
struct TerminalView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    /// 是否正在加载屏幕内容
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // 终端输出区域
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let lines = messageStore.snapshots[surfaceID]?.lines ?? []

                        if isLoading && lines.isEmpty {
                            ProgressView("加载终端内容…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(ANSIParser.parse(line))
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }

                        // 底部锚点
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .background(Color.black)
                .onAppear {
                    // 进入详情页时请求终端屏幕内容
                    requestScreenContent()
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .task(id: messageStore.snapshots[surfaceID]?.lines.count) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // 输入工具栏（始终显示）
            TerminalInputBar(
                onSendText: { text in
                    sendText(text + "\n")
                },
                onSendKey: { key, mods in
                    sendKey(key: key, mods: mods)
                }
            )
            .environmentObject(inputManager)
        }
        .navigationTitle(surfaceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 进入终端详情时启用输入
            inputManager.enableInput()
        }
        .onDisappear {
            inputManager.disableInput()
        }
    }

    // MARK: - 数据请求

    /// 请求终端屏幕内容
    private func requestScreenContent() {
        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
            isLoading = false

            // 解析 read_screen 响应
            // Mac Bridge 会返回 V1 text 响应或 JSON result
            if let resultDict = result["result"] as? [String: Any],
               let text = resultDict["text"] as? String {
                parseScreenText(text)
            } else if let text = result["text"] as? String {
                parseScreenText(text)
            }
        }
    }

    /// 解析 read_screen 返回的文本（base64 或纯文本）
    private func parseScreenText(_ text: String) {
        // read_screen 返回 "OK {base64}" 格式
        let content: String
        if text.hasPrefix("OK ") {
            let base64 = String(text.dropFirst(3))
            if let data = Data(base64Encoded: base64),
               let decoded = String(data: data, encoding: .utf8) {
                content = decoded
            } else {
                content = text
            }
        } else {
            content = text
        }

        let lines = content.components(separatedBy: "\n")
        let snapshot = ScreenSnapshot(
            surfaceID: surfaceID,
            lines: lines,
            dimensions: ScreenSnapshot.Dimensions(rows: lines.count, cols: 80),
            timestamp: Date()
        )
        var updated = messageStore.snapshots
        updated[surfaceID] = snapshot
        messageStore.snapshots = updated
    }

    // MARK: - 输入发送

    /// 发送文本到终端
    private func sendText(_ text: String) {
        relayConnection.send([
            "method": "surface.send_text",
            "params": [
                "surface_id": surfaceID,
                "text": text,
            ],
        ])
    }

    /// 发送按键到终端
    private func sendKey(key: String, mods: String) {
        relayConnection.send([
            "method": "surface.send_key",
            "params": [
                "surface_id": surfaceID,
                "key": key,
                "mods": mods,
            ],
        ])
    }

    private var surfaceTitle: String {
        messageStore.surfaces.first { $0.id == surfaceID }?.title ?? "终端"
    }
}
