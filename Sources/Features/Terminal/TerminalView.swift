import SwiftUI

/// read_screen 降频状态（引用类型，确保 Task 闭包能读到最新值）
@MainActor
final class ReadScreenState: ObservableObject {
    @Published var failCount: Int = 0
}

/// 终端内容视图，全屏显示终端输出 + 底部输入工具栏
struct TerminalView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection
    @Environment(\.dismiss) private var dismiss

    /// 是否正在加载屏幕内容
    @State private var isLoading = true
    /// 加载错误信息
    @State private var errorMessage: String?
    /// 终端字体大小（持久化到 UserDefaults）
    @AppStorage("terminalFontSize") private var fontSize: Double = 14
    /// 自动刷新定时器
    @State private var refreshTask: Task<Void, Never>?
    /// 当前是否处于横屏模式
    @State private var isLandscape = false
    /// 终端内容是否已加载完成（用于渐入动画）
    @State private var contentVisible = false
    @StateObject private var requestGate = LatestOnlyRequestGate()

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                // 终端输出区域
                terminalContent

                // 输入工具栏（横竖屏均显示在底部）
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

            // 横屏模式下显示浮动返回按钮
            if isLandscape {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding(.top, 8)
                .padding(.leading, 8)
                .accessibilityLabel(String(localized: "common.back", defaultValue: "返回"))
            }
        }
        .background(Color.black)
        .navigationBarHidden(isLandscape)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // 字体缩小
                Button { fontSize = max(6.0, fontSize - 1.0) } label: {
                    Image(systemName: "textformat.size.smaller")
                        .font(.caption)
                }
                .accessibilityLabel(String(localized: "terminal.font_smaller", defaultValue: "字体缩小"))
                // 字体放大
                Button { fontSize = min(20.0, fontSize + 1.0) } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.caption)
                }
                .accessibilityLabel(String(localized: "terminal.font_larger", defaultValue: "字体放大"))
                // 刷新屏幕
                Button { requestScreenContent() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .accessibilityLabel(String(localized: "terminal.refresh", defaultValue: "刷新终端"))
            }
        }
        .onAppear {
            inputManager.enableInput()
            requestScreenContent()
            startAutoRefresh()
            updateOrientation()
        }
        .onDisappear {
            inputManager.disableInput()
            stopAutoRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateOrientation()
        }
    }

    /// 根据设备方向更新横屏状态
    private func updateOrientation() {
        let orientation = UIDevice.current.orientation
        withAnimation(.easeInOut(duration: 0.25)) {
            isLandscape = orientation.isLandscape
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
            // 终端内容（渐入动画）
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(ANSIParser.parse(line))
                                .font(.system(size: CGFloat(fontSize), design: .monospaced))
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
                .opacity(contentVisible ? 1 : 0)
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                    withAnimation(.easeIn(duration: 0.3)) {
                        contentVisible = true
                    }
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
        let token = requestGate.begin("read_screen")
        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
            guard requestGate.isLatest(token, for: "read_screen") else { return }
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

    // MARK: - 自动刷新

    /// 每 2 秒刷新一次终端内容
    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                requestScreenContent()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
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
        // Mac 端期望 key 格式为 "ctrl-l"，不是分开的 key+mods
        let combinedKey = mods.isEmpty ? key : "\(mods)-\(key)"
        relayConnection.send([
            "method": "surface.send_key",
            "params": [
                "surface_id": surfaceID,
                "key": combinedKey,
            ],
        ])
    }

    private var surfaceTitle: String {
        messageStore.surfaces.first { $0.id == surfaceID }?.title ?? "终端"
    }
}
