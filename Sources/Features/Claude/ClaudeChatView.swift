import SwiftUI

/// Claude Code 聊天模式视图
/// 类似 happy 的聊天式 UI，支持 @文件、/技能等
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ClaudeMessage] = []
    @State private var sessionInfo: (model: String, project: String, context: String) = ("", "", "")
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var isWaitingResponse = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var showRawTerminal = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 消息区域
            messagesArea

            // 输入区域
            inputArea
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .navigationTitle(sessionInfo.project.isEmpty ? "Claude Code" : sessionInfo.project)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRawTerminal = true
                } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 14))
                        .foregroundStyle(.gray)
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

    // MARK: - 消息区域

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 会话头部信息
                    if !sessionInfo.model.isEmpty {
                        sessionHeader
                    }

                    // 空状态
                    if messages.isEmpty && !isLoading {
                        emptyState
                    }

                    // 消息列表
                    ForEach(messages) { message in
                        messageRow(message)
                            .id(message.id)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }

                    // 等待响应动画
                    if isWaitingResponse {
                        thinkingIndicator
                            .id("thinking")
                    }

                    Color.clear.frame(height: 8).id("bottom")
                }
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: isWaitingResponse) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - 会话头部

    private var sessionHeader: some View {
        VStack(spacing: 8) {
            // Claude 图标
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.purple)
                .padding(.top, 20)

            Text("Claude Code")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            // 模型和项目信息
            HStack(spacing: 12) {
                if !sessionInfo.model.isEmpty {
                    Label(sessionInfo.model, systemImage: "cpu")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if !sessionInfo.context.isEmpty {
                    Label(sessionInfo.context, systemImage: "chart.bar")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if !sessionInfo.project.isEmpty {
                Text(sessionInfo.project)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("输入消息开始对话")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 40)
        }
    }

    // MARK: - 消息行

    @ViewBuilder
    private func messageRow(_ message: ClaudeMessage) -> some View {
        switch message.kind {
        case .userText:
            userBubble(message.content)
        case .agentText:
            agentBubble(message.content)
        case .toolCall:
            toolCard(message)
        case .systemEvent:
            systemLabel(message.content)
        case .thinking:
            thinkingIndicator
        }
    }

    /// 用户消息气泡 — 右对齐
    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 50)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0.25, green: 0.45, blue: 0.85))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// Claude 回复 — 左对齐，带头像
    private func agentBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Claude 头像
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
            }

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 30)
        }
    }

    /// 工具调用卡片
    private func toolCard(_ message: ClaudeMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 占位对齐头像
            Color.clear.frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 0) {
                // 头部
                HStack(spacing: 8) {
                    Image(systemName: toolIcon(message.toolName))
                        .font(.system(size: 11))
                        .foregroundStyle(toolColor(message.toolState))

                    Text(message.toolName ?? "Tool")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    // 状态
                    Group {
                        if message.toolState == .running {
                            ProgressView().scaleEffect(0.5).tint(.yellow)
                        } else if message.toolState == .completed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if message.toolState == .error {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.system(size: 11))
                }
                .padding(10)

                // 内容
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(4)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            Spacer(minLength: 30)
        }
    }

    /// 系统事件标签
    private func systemLabel(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// 思考中动画
    private var thinkingIndicator: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
            }

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.purple.opacity(0.5))
                        .frame(width: 5, height: 5)
                        .offset(y: thinkingOffset(i))
                }
                Text("思考中")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func thinkingOffset(_ index: Int) -> CGFloat {
        return 0 // 简化动画，避免性能问题
    }

    // MARK: - 输入区域

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.1))

            // 快捷操作行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // @文件引用
                    chipButton("@文件", icon: "doc", color: .blue) {
                        inputText += "@"
                        isInputFocused = true
                    }
                    // /技能命令
                    chipButton("/技能", icon: "command", color: .orange) {
                        inputText += "/"
                        isInputFocused = true
                    }

                    Divider().frame(height: 20)

                    chipButton("Ctrl+C", icon: "stop.circle", color: .red) {
                        sendKey("c", "ctrl")
                    }
                    chipButton("Esc", icon: "escape", color: .gray) {
                        sendKey("escape", "")
                    }
                    chipButton("/compact", icon: "arrow.down.right.and.arrow.up.left", color: .purple) {
                        sendText("/compact\n")
                    }
                    chipButton("/status", icon: "info.circle", color: .green) {
                        sendText("/status\n")
                    }
                    chipButton("/help", icon: "questionmark.circle", color: .cyan) {
                        sendText("/help\n")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            // 输入框
            HStack(spacing: 10) {
                TextField("", text: $inputText, prompt: Text("给 Claude 发消息...").foregroundStyle(.gray), axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onSubmit { handleSend() }

                Button(action: handleSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(inputText.isEmpty ? Color.gray.opacity(0.4) : Color.purple)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
    }

    /// 快捷操作芯片按钮
    private func chipButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .foregroundStyle(color.opacity(0.8))
            .clipShape(Capsule())
        }
    }

    // MARK: - 发送

    private func handleSend() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""

        // 添加用户消息到本地列表
        messages.append(ClaudeMessage(
            id: "local-\(Date().timeIntervalSince1970)",
            kind: .userText,
            content: text,
            timestamp: Date()
        ))

        // 发送到终端
        sendText(text + "\n")
        isWaitingResponse = true
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
                let parsed = ClaudeOutputParser.extractMessages(linesArray)
                sessionInfo = ClaudeOutputParser.parseSessionInfo(linesArray)

                // 合并本地用户消息和解析到的消息
                mergeMessages(parsed)

                // 如果有新的 agent 消息，停止等待状态
                if parsed.contains(where: { $0.kind == .agentText || $0.kind == .toolCall }) {
                    isWaitingResponse = false
                }
            }
        }
    }

    /// 合并远端解析的消息和本地发送的消息
    private func mergeMessages(_ parsed: [ClaudeMessage]) {
        // 如果解析到的消息比本地多，更新
        if parsed.count > messages.filter({ !$0.id.hasPrefix("local-") }).count {
            // 保留本地发送但还没出现在解析结果中的消息
            let localOnly = messages.filter { $0.id.hasPrefix("local-") && $0.kind == .userText }
            var merged = parsed
            for local in localOnly {
                if !merged.contains(where: { $0.kind == .userText && $0.content == local.content }) {
                    merged.append(local)
                }
            }
            messages = merged
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

    // MARK: - 发送辅助

    private func sendText(_ text: String) {
        relayConnection.send([
            "method": "surface.send_text",
            "params": ["surface_id": surfaceID, "text": text],
        ])
    }

    private func sendKey(_ key: String, _ mods: String) {
        relayConnection.send([
            "method": "surface.send_key",
            "params": ["surface_id": surfaceID, "key": key, "mods": mods],
        ])
    }

    // MARK: - 工具图标

    private func toolIcon(_ name: String?) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Grep": return "magnifyingglass"
        case "Glob": return "doc.on.doc"
        case "Agent": return "person.2"
        case "WebSearch": return "globe"
        case "WebFetch": return "arrow.down.doc"
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
