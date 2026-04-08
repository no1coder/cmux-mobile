import SwiftUI

/// Claude Code 聊天模式
/// 本地维护对话历史，终端输出过滤后作为 Claude 回复展示
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    /// 本地对话消息列表
    @State private var chatMessages: [ChatItem] = []
    /// 输入文本
    @State private var inputText = ""
    /// Claude 是否正在处理
    @State private var isThinking = false
    /// 上一次终端内容的行数（用于检测新输出）
    @State private var lastLineCount = 0
    /// 上一次终端内容的哈希（用于检测变化）
    @State private var lastContentHash = 0
    /// 会话信息
    @State private var sessionInfo: (model: String, project: String, context: String) = ("", "", "")
    /// 自动刷新任务
    @State private var refreshTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    /// 聊天消息项
    struct ChatItem: Identifiable, Equatable {
        let id: String
        let role: Role
        let content: String
        let timestamp: Date

        enum Role: Equatable {
            case user
            case assistant
            case tool(name: String, state: ToolCallState)
            case system
            case thinking
        }

        static func == (lhs: ChatItem, rhs: ChatItem) -> Bool {
            lhs.id == rhs.id && lhs.content == rhs.content
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 聊天消息区域
            chatArea

            // 输入区域
            inputBar
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .onAppear {
            loadInitialContent()
            startWatching()
        }
        .onDisappear {
            stopWatching()
        }
    }

    // MARK: - 聊天消息区域

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    // 会话头部
                    sessionHeaderView
                        .padding(.bottom, 8)

                    // 消息列表
                    ForEach(chatMessages) { item in
                        chatRow(item)
                            .id(item.id)
                    }

                    // 思考中动画
                    if isThinking {
                        thinkingBubble
                            .id("thinking")
                    }

                    Color.clear.frame(height: 4).id("end")
                }
                .padding(.horizontal, 14)
            }
            .onChange(of: chatMessages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
            .onChange(of: isThinking) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - 会话头部

    private var sessionHeaderView: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(.purple)
                .padding(.top, 16)

            if !sessionInfo.model.isEmpty {
                HStack(spacing: 8) {
                    Text(sessionInfo.model)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.purple.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())

                    if !sessionInfo.context.isEmpty {
                        Text(sessionInfo.context)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            if !sessionInfo.project.isEmpty {
                Text(sessionInfo.project)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            if chatMessages.isEmpty {
                Text("向 Claude 发送消息开始对话")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - 聊天行

    @ViewBuilder
    private func chatRow(_ item: ChatItem) -> some View {
        switch item.role {
        case .user:
            // 用户消息 — 右对齐蓝色气泡
            HStack {
                Spacer(minLength: 50)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.content)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.22, green: 0.42, blue: 0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

        case .assistant:
            // Claude 回复 — 左对齐
            HStack(alignment: .top, spacing: 8) {
                claudeAvatar
                Text(item.content)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
            }

        case .tool(let name, let state):
            // 工具调用卡片
            HStack(alignment: .top, spacing: 8) {
                Color.clear.frame(width: 26)
                toolCard(name: name, state: state, content: item.content)
                Spacer(minLength: 20)
            }

        case .system:
            // 系统消息
            HStack {
                Spacer()
                Text(item.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
                Spacer()
            }

        case .thinking:
            thinkingBubble
        }
    }

    /// Claude 头像
    private var claudeAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.purple.opacity(0.15))
                .frame(width: 26, height: 26)
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(.purple)
        }
    }

    /// 工具调用卡片
    private func toolCard(name: String, state: ToolCallState, content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: toolIcon(name))
                    .font(.system(size: 10))
                    .foregroundStyle(toolColor(state))
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                statusIcon(state)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if !content.isEmpty {
                Text(content)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(3)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func statusIcon(_ state: ToolCallState) -> some View {
        switch state {
        case .running:
            ProgressView().scaleEffect(0.4).tint(.yellow)
        case .completed:
            Image(systemName: "checkmark").font(.system(size: 9)).foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.red)
        case .permissionRequired:
            Image(systemName: "hand.raised").font(.system(size: 9)).foregroundStyle(.orange)
        }
    }

    /// 思考中气泡
    private var thinkingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            claudeAvatar
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.purple.opacity(0.4))
                        .frame(width: 5, height: 5)
                }
                Text("思考中")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    .italic()
            }
            .padding(.top, 5)
            Spacer()
        }
    }

    // MARK: - 输入区域

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))

            // 快捷操作
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("@", color: .blue) { inputText += "@"; isInputFocused = true }
                    chip("/", color: .orange) { inputText += "/"; isInputFocused = true }

                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 16)

                    chip("^C", color: .red) { sendKey("c", "ctrl") }
                    chip("Esc", color: .gray) { sendKey("escape", "") }
                    chip("/compact", color: .purple) { sendDirect("/compact\n") }
                    chip("/status", color: .green) { sendDirect("/status\n") }
                    chip("回车", color: .white.opacity(0.6)) { sendKey("return", "") }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // 输入框 + 发送
            HStack(spacing: 8) {
                TextField("", text: $inputText, prompt: Text("消息...").foregroundStyle(.gray.opacity(0.6)), axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(inputText.isEmpty ? .gray.opacity(0.3) : .purple)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }

    private func chip(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.1))
                .foregroundStyle(color.opacity(0.7))
                .clipShape(Capsule())
        }
    }

    // MARK: - 发送

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        // 添加用户消息
        chatMessages.append(ChatItem(
            id: UUID().uuidString,
            role: .user,
            content: text,
            timestamp: Date()
        ))

        // 发送到终端
        sendDirect(text + "\n")
        isThinking = true
    }

    private func sendDirect(_ text: String) {
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

    // MARK: - 终端内容监控

    private func loadInitialContent() {
        fetchTerminalContent()
    }

    private func startWatching() {
        stopWatching()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { break }
                fetchTerminalContent()
            }
        }
    }

    private func stopWatching() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// 从终端读取内容并更新聊天
    private func fetchTerminalContent() {
        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            guard let lines = resultDict["lines"] as? [String] else { return }

            // 更新会话信息
            sessionInfo = ClaudeOutputParser.parseSessionInfo(lines)

            // 检测内容变化
            let contentHash = lines.joined().hashValue
            guard contentHash != lastContentHash else { return }
            lastContentHash = contentHash

            // 解析终端输出为消息
            let parsed = ClaudeOutputParser.extractMessages(lines)

            // 如果有新的 assistant 消息，停止思考状态
            if parsed.contains(where: { $0.kind == .agentText || $0.kind == .toolCall }) {
                isThinking = false
            }

            // 将解析结果转换为 ChatItem，和本地消息合并
            updateChatFromParsed(parsed)
        }
    }

    /// 将解析的终端消息合并到本地聊天
    private func updateChatFromParsed(_ parsed: [ClaudeMessage]) {
        // 保留所有本地用户消息
        let localUserMessages = chatMessages.filter {
            if case .user = $0.role { return true }
            return false
        }

        // 从解析结果构建远端消息
        var remoteMsgs: [ChatItem] = []
        for msg in parsed {
            switch msg.kind {
            case .userText:
                remoteMsgs.append(ChatItem(id: msg.id, role: .user, content: msg.content, timestamp: msg.timestamp))
            case .agentText:
                remoteMsgs.append(ChatItem(id: msg.id, role: .assistant, content: msg.content, timestamp: msg.timestamp))
            case .toolCall:
                let state = msg.toolState ?? .completed
                remoteMsgs.append(ChatItem(id: msg.id, role: .tool(name: msg.toolName ?? "Tool", state: state), content: msg.content, timestamp: msg.timestamp))
            case .systemEvent:
                remoteMsgs.append(ChatItem(id: msg.id, role: .system, content: msg.content, timestamp: msg.timestamp))
            case .thinking:
                break
            }
        }

        // 合并：远端消息 + 本地独有的用户消息
        var merged = remoteMsgs
        for local in localUserMessages {
            if !merged.contains(where: { $0.content == local.content && isUser($0) }) {
                merged.append(local)
            }
        }

        // 只有内容真正变化时才更新
        if merged.map(\.content) != chatMessages.map(\.content) {
            chatMessages = merged
        }
    }

    private func isUser(_ item: ChatItem) -> Bool {
        if case .user = item.role { return true }
        return false
    }

    // MARK: - 工具辅助

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Grep": return "magnifyingglass"
        case "Glob": return "doc.on.doc"
        case "Agent": return "person.2"
        default: return "wrench"
        }
    }

    private func toolColor(_ state: ToolCallState) -> Color {
        switch state {
        case .running: return .yellow
        case .completed: return .green
        case .error: return .red
        case .permissionRequired: return .orange
        }
    }
}
