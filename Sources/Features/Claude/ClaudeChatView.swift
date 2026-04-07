import SwiftUI

/// Claude Code 聊天模式视图
/// 将终端输出解析为聊天消息格式展示
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    @State private var messages: [ClaudeMessage] = []
    @State private var sessionStatus = ClaudeSessionStatus()
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var refreshTask: Task<Void, Never>?
    /// 是否显示原始终端视图
    @State private var showRawTerminal = false

    var body: some View {
        VStack(spacing: 0) {
            // 会话状态栏
            if sessionStatus.isActive {
                sessionStatusBar
            }

            // 消息列表
            messageList

            // 输入区域
            chatInputBar
        }
        .background(Color(white: 0.08))
        .navigationTitle("Claude Code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // 切换原始终端视图
                Button {
                    showRawTerminal = true
                } label: {
                    Image(systemName: "terminal")
                        .font(.caption)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showRawTerminal) {
            NavigationStack {
                TerminalView(surfaceID: surfaceID)
                    .environmentObject(messageStore)
                    .environmentObject(inputManager)
                    .environmentObject(relayConnection)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { showRawTerminal = false }
                        }
                    }
            }
        }
        .onAppear {
            requestAndParse()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - 会话状态栏

    private var sessionStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)

            if !sessionStatus.model.isEmpty {
                Text(sessionStatus.model)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if !sessionStatus.contextUsage.isEmpty {
                Text("· \(sessionStatus.contextUsage)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(white: 0.12))
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if isLoading && messages.isEmpty {
                        ProgressView("加载中…")
                            .tint(.green)
                            .padding(.top, 40)
                    }

                    ForEach(messages) { message in
                        messageView(for: message)
                            .id(message.id)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - 消息渲染

    @ViewBuilder
    private func messageView(for message: ClaudeMessage) -> some View {
        switch message.kind {
        case .userText:
            userMessageView(message)
        case .agentText:
            agentMessageView(message)
        case .toolCall:
            toolCallView(message)
        case .systemEvent:
            systemEventView(message)
        case .thinking:
            thinkingView(message)
        }
    }

    /// 用户消息 — 右对齐气泡
    private func userMessageView(_ message: ClaudeMessage) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.content)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// Claude 回复 — 左对齐，Markdown 风格
    private func agentMessageView(_ message: ClaudeMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Claude 头像
            Image(systemName: "sparkle")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)
                .background(Color.purple.opacity(0.15))
                .clipShape(Circle())

            Text(message.content)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 40)
        }
    }

    /// 工具调用 — 可折叠卡片
    private func toolCallView(_ message: ClaudeMessage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 工具头部
            HStack(spacing: 8) {
                Image(systemName: toolIcon(message.toolName))
                    .font(.system(size: 12))
                    .foregroundStyle(toolColor(message.toolState))

                Text(message.toolName ?? "Tool")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                // 状态指示
                if message.toolState == .running {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.yellow)
                } else if message.toolState == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                } else if message.toolState == .error {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))

            // 工具内容
            Text(message.content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(6)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// 系统事件 — 居中灰色文字
    private func systemEventView(_ message: ClaudeMessage) -> some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// 思考状态 — 脉冲动画
    private func thinkingView(_ message: ClaudeMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)
                .background(Color.purple.opacity(0.15))
                .clipShape(Circle())

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.purple.opacity(0.6))
                        .frame(width: 6, height: 6)
                }
            }

            Text("思考中…")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .italic()

            Spacer()
        }
    }

    // MARK: - 输入区域

    private var chatInputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)

            // 快捷操作
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    quickAction("Ctrl+C", icon: "stop.circle") {
                        sendKey(key: "c", mods: "ctrl")
                    }
                    quickAction("Esc", icon: "escape") {
                        sendKey(key: "escape", mods: "")
                    }
                    quickAction("/compact", icon: "arrow.down.right.and.arrow.up.left") {
                        sendText("/compact\n")
                    }
                    quickAction("/status", icon: "info.circle") {
                        sendText("/status\n")
                    }
                    quickAction("回车", icon: "return") {
                        sendKey(key: "return", mods: "")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // 文本输入
            HStack(spacing: 8) {
                TextField("", text: $inputText, prompt: Text("给 Claude 发消息…").foregroundStyle(.gray))
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onSubmit {
                        guard !inputText.isEmpty else { return }
                        sendText(inputText + "\n")
                        inputText = ""
                    }

                Button {
                    guard !inputText.isEmpty else { return }
                    sendText(inputText + "\n")
                    inputText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(inputText.isEmpty ? Color.gray : Color.purple)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(white: 0.1))
    }

    /// 快捷操作按钮
    private func quickAction(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .foregroundStyle(.white.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - 数据请求

    private func requestAndParse() {
        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
            isLoading = false
            let resultDict = result["result"] as? [String: Any] ?? result
            if let linesArray = resultDict["lines"] as? [String] {
                messages = ClaudeOutputParser.parse(linesArray)
                sessionStatus = ClaudeOutputParser.parseSessionStatus(linesArray)
            }
        }
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                requestAndParse()
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
            "params": ["surface_id": surfaceID, "text": text],
        ])
    }

    private func sendKey(key: String, mods: String) {
        relayConnection.send([
            "method": "surface.send_key",
            "params": ["surface_id": surfaceID, "key": key, "mods": mods],
        ])
    }

    // MARK: - 工具图标和颜色

    private func toolIcon(_ name: String?) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Grep": return "magnifyingglass"
        case "Glob": return "doc.on.doc"
        default: return "wrench"
        }
    }

    private func toolColor(_ state: ToolCallState?) -> Color {
        switch state {
        case .running: return .yellow
        case .completed: return .green
        case .error: return .red
        case .permissionRequired: return .orange
        case nil: return .gray
        }
    }
}
