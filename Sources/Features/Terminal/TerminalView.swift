import SwiftUI

/// 终端内容视图，全屏显示终端输出 + 底部输入工具栏
struct TerminalView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    /// 是否正在加载屏幕内容
    @State private var isLoading = true
    /// 加载错误信息
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // 终端输出区域
            terminalContent

            // 输入工具栏
            TerminalInputBar(
                onSendText: { text in
                    sendText(text + "\n")
                    // 发送后刷新屏幕
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        requestScreenContent()
                    }
                },
                onSendKey: { key, mods in
                    sendKey(key: key, mods: mods)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        requestScreenContent()
                    }
                }
            )
            .environmentObject(inputManager)
        }
        .background(Color.black)
        .navigationTitle(surfaceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            inputManager.enableInput()
            requestScreenContent()
        }
        .onDisappear {
            inputManager.disableInput()
        }
    }

    // MARK: - 终端内容

    @ViewBuilder
    private var terminalContent: some View {
        let lines = messageStore.snapshots[surfaceID]?.lines ?? []

        if isLoading && lines.isEmpty {
            // 加载中
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.green)
                Text("加载终端内容…")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        } else if let error = errorMessage, lines.isEmpty {
            // 错误状态
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.gray)
                Button("重试") { requestScreenContent() }
                    .buttonStyle(.bordered)
                    .tint(.green)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        } else {
            // 终端内容
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(ANSIParser.parse(line))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .background(Color.black)
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .task(id: lines.count) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
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

            // 优先从 result 字典中提取
            let resultDict = result["result"] as? [String: Any] ?? result

            if let linesArray = resultDict["lines"] as? [String] {
                let snapshot = ScreenSnapshot(
                    surfaceID: surfaceID,
                    lines: linesArray,
                    dimensions: ScreenSnapshot.Dimensions(rows: linesArray.count, cols: 80),
                    timestamp: Date()
                )
                var updated = messageStore.snapshots
                updated[surfaceID] = snapshot
                messageStore.snapshots = updated
                errorMessage = nil
            } else if let error = resultDict["error"] as? String {
                errorMessage = error
                print("[terminal] read_screen 失败: \(error)")
            } else {
                errorMessage = "未知响应格式"
                print("[terminal] read_screen 未知响应: \(result.keys)")
            }
        }
    }

    // MARK: - 输入发送

    private func sendText(_ text: String) {
        relayConnection.send([
            "method": "surface.send_text",
            "params": [
                "surface_id": surfaceID,
                "text": text,
            ],
        ])
    }

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
