import SwiftUI

/// Claude Code 聊天模式 — 纯对话式，消息持久化
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    @State private var inputText = ""
    @State private var isThinking = false
    @State private var sessionInfo: (model: String, project: String, context: String) = ("", "", "")
    @State private var refreshTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    /// 从 MessageStore 读取持久化的消息
    private var chatMessages: [ClaudeChatItem] {
        messageStore.claudeChats[surfaceID] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            chatArea
            inputBar
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .onAppear {
            fetchSessionInfo()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
    }

    // MARK: - 聊天区域

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    sessionHeader
                        .padding(.bottom, 8)

                    if chatMessages.isEmpty {
                        Text("向 Claude 发送消息开始对话")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.2))
                            .padding(.top, 20)
                    }

                    ForEach(chatMessages) { msg in
                        messageRow(msg).id(msg.id)
                    }

                    if isThinking {
                        thinkingView.id("thinking")
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
        }
    }

    // MARK: - 会话头部

    private var sessionHeader: some View {
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
        }
    }

    // MARK: - 消息渲染

    @ViewBuilder
    private func messageRow(_ msg: ClaudeChatItem) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 50)
                Text(msg.content)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.22, green: 0.42, blue: 0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                claudeAvatar
                Text(msg.content)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
            }

        case .tool(let name):
            HStack(alignment: .top, spacing: 8) {
                Color.clear.frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text(name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text(msg.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(4)
                }
                .padding(8)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer(minLength: 20)
            }

        case .system:
            HStack {
                Spacer()
                Text(msg.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.2))
                Spacer()
            }
        }
    }

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

    private var thinkingView: some View {
        HStack(alignment: .top, spacing: 8) {
            claudeAvatar
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.purple.opacity(0.4)).frame(width: 5, height: 5)
                }
                Text("思考中")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.3)).italic()
            }
            .padding(.top, 5)
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    // MARK: - 输入区域

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))

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
                .padding(.horizontal, 8).padding(.vertical, 4)
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

        // 保存当前终端内容快照，用于后续对比
        saveCurrentSnapshot()

        // 添加用户消息到持久化存储
        appendMessage(ClaudeChatItem(
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

    // MARK: - 消息持久化

    private func appendMessage(_ msg: ClaudeChatItem) {
        var msgs = messageStore.claudeChats[surfaceID] ?? []
        msgs.append(msg)
        messageStore.claudeChats[surfaceID] = msgs
    }

    // MARK: - 终端轮询

    private func fetchSessionInfo() {
        readTerminal { lines in
            sessionInfo = ClaudeOutputParser.parseSessionInfo(lines)
        }
    }

    private func startPolling() {
        stopPolling()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                pollTerminalChanges()
            }
        }
    }

    private func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// 读取终端内容
    private func readTerminal(completion: @escaping ([String]) -> Void) {
        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let lines = resultDict["lines"] as? [String] {
                completion(lines)
            }
        }
    }

    /// 保存当前终端快照
    private func saveCurrentSnapshot() {
        readTerminal { lines in
            let clean = Self.cleanTerminalText(lines)
            messageStore.lastCleanText[surfaceID] = clean
            messageStore.lastTerminalHash[surfaceID] = lines.joined().hashValue
        }
    }

    /// 轮询检测终端变化，提取 Claude 回复
    private func pollTerminalChanges() {
        readTerminal { lines in
            // 更新会话信息
            sessionInfo = ClaudeOutputParser.parseSessionInfo(lines)

            // 检测内容变化
            let hash = lines.joined().hashValue
            let prevHash = messageStore.lastTerminalHash[surfaceID] ?? 0
            guard hash != prevHash else { return }
            messageStore.lastTerminalHash[surfaceID] = hash

            // 提取干净文本
            let cleanText = Self.cleanTerminalText(lines)
            let prevText = messageStore.lastCleanText[surfaceID] ?? ""

            // 只在 thinking 状态下提取新回复
            if isThinking && !cleanText.isEmpty {
                let newContent = Self.extractNewResponse(previous: prevText, current: cleanText)
                if !newContent.isEmpty {
                    isThinking = false
                    appendMessage(ClaudeChatItem(
                        id: UUID().uuidString,
                        role: .assistant,
                        content: newContent,
                        timestamp: Date()
                    ))
                }
            }

            messageStore.lastCleanText[surfaceID] = cleanText
        }
    }

    // MARK: - 文本处理（静态方法）

    /// 从终端行中提取干净的纯文本内容
    static func cleanTerminalText(_ lines: [String]) -> String {
        var result: [String] = []

        for line in lines {
            var clean = ""
            var i = line.startIndex

            while i < line.endIndex {
                let char = line[i]

                // 跳过 ESC 序列
                if char == "\u{1B}" {
                    i = line.index(after: i)
                    guard i < line.endIndex else { break }
                    if line[i] == "[" {
                        i = line.index(after: i)
                        while i < line.endIndex {
                            if line[i].asciiValue.map({ $0 >= 0x40 && $0 <= 0x7E }) == true {
                                i = line.index(after: i); break
                            }
                            i = line.index(after: i)
                        }
                    } else if line[i] == "]" {
                        i = line.index(after: i)
                        while i < line.endIndex {
                            if line[i] == "\u{07}" { i = line.index(after: i); break }
                            if line[i] == "\u{1B}" {
                                let ni = line.index(after: i)
                                if ni < line.endIndex && line[ni] == "\\" { i = line.index(after: ni); break }
                            }
                            i = line.index(after: i)
                        }
                    } else {
                        i = line.index(after: i)
                    }
                    continue
                }

                // 跳过控制字符和特殊 Unicode
                if let scalar = char.unicodeScalars.first {
                    let v = scalar.value
                    if v < 0x20 && v != 0x09 { i = line.index(after: i); continue }
                    if (v >= 0xE000 && v <= 0xF8FF) || v >= 0xF0000 { i = line.index(after: i); continue }
                    if (v >= 0x2500 && v <= 0x259F) || (v >= 0x2800 && v <= 0x28FF) { i = line.index(after: i); continue }
                }

                clean.append(char)
                i = line.index(after: i)
            }

            let trimmed = clean.trimmingCharacters(in: .whitespaces)

            // 跳过装饰行和无意义短行
            if trimmed.isEmpty { continue }
            if trimmed.count <= 2 { continue }
            if trimmed.allSatisfy({ "─━_=-~".contains($0) }) { continue }

            // 跳过 Claude TUI 固有内容
            if trimmed.contains("Claude Code v") { continue }
            if trimmed.contains("with medium effort") || trimmed.contains("with high effort") { continue }
            if trimmed.contains("Claude Max") || trimmed.contains("Claude API") { continue }
            if trimmed.contains("Loamwaddle") { continue }
            if trimmed.contains("Context") && trimmed.contains("%") { continue }
            if trimmed.hasPrefix("[Opus") || trimmed.hasPrefix("[Sonnet") { continue }
            if trimmed.contains("git:(") || trimmed.contains("git:") { continue }
            if trimmed.contains("<(") || trimmed.contains("._>") || trimmed.contains("`--'") { continue }
            if trimmed.contains("1M context") || trimmed.contains("200K context") { continue }
            if trimmed.contains("Harmonizing") { continue }
            if trimmed.contains("Accessing workspace") { continue }

            result.append(trimmed)
        }

        return result.joined(separator: "\n")
    }

    /// 从前后文本对比中提取 Claude 的新回复
    static func extractNewResponse(previous: String, current: String) -> String {
        // 如果 current 包含 previous，取新增部分
        if current.count > previous.count && current.hasPrefix(previous) {
            let diff = String(current.dropFirst(previous.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if diff.count > 3 { return diff }
        }

        // 如果完全不同，找出新增行
        let prevLines = Set(previous.components(separatedBy: "\n"))
        let currLines = current.components(separatedBy: "\n")
        let newLines = currLines.filter { !prevLines.contains($0) && !$0.isEmpty }

        let joined = newLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.count > 3 ? joined : ""
    }
}
