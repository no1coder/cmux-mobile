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
        // Mac 端期望 key 格式为 "ctrl-c"，不是分开的 key+mods
        let combinedKey = mods.isEmpty ? key : "\(mods)-\(key)"
        relayConnection.send([
            "method": "surface.send_key",
            "params": ["surface_id": surfaceID, "key": combinedKey],
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
            // 首次进入时，扫描屏幕上已有的对话作为历史
            if chatMessages.isEmpty {
                loadHistoryFromScreen(lines)
            }
        }
    }

    private func startPolling() {
        stopPolling()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                pollForResponse()
            }
        }
    }

    private func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }

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
            messageStore.lastTerminalHash[surfaceID] = lines.joined().hashValue
        }
    }

    /// 从屏幕内容加载已有对话历史
    private func loadHistoryFromScreen(_ lines: [String]) {
        let conversations = Self.scanConversations(lines)
        if !conversations.isEmpty {
            messageStore.claudeChats[surfaceID] = conversations
        }
    }

    /// 轮询检测新回复
    private func pollForResponse() {
        readTerminal { lines in
            sessionInfo = ClaudeOutputParser.parseSessionInfo(lines)

            let hash = lines.joined().hashValue
            let prevHash = messageStore.lastTerminalHash[surfaceID] ?? 0
            guard hash != prevHash else { return }
            messageStore.lastTerminalHash[surfaceID] = hash

            // 从屏幕扫描所有对话
            let scanned = Self.scanConversations(lines)

            // 如果扫描到的回复比当前存储的多，追加新的
            let existingAssistantCount = chatMessages.filter { $0.role == .assistant }.count
            let scannedAssistantCount = scanned.filter { $0.role == .assistant }.count

            print("[claude-poll] scanned=\(scanned.count) (user=\(scanned.filter { $0.role == .user }.count), assist=\(scannedAssistantCount)) existing=\(chatMessages.count) (assist=\(existingAssistantCount)) thinking=\(isThinking)")

            if scannedAssistantCount > existingAssistantCount {
                // 有新回复
                isThinking = false
                // 取最后一个新回复
                if let lastAssistant = scanned.last(where: { $0.role == .assistant }) {
                    let alreadyHas = chatMessages.contains { $0.role == .assistant && $0.content == lastAssistant.content }
                    if !alreadyHas {
                        appendMessage(lastAssistant)
                    }
                }
            }

            // 如果内容变化了但 thinking 状态，检查是否 Claude 已完成（出现新的 prompt）
            if isThinking {
                let cleanText = lines.map { Self.stripAnsi($0) }.joined()
                // Claude 完成的标志：出现了新的输入 prompt（❯ 后面没内容）
                let hasIdlePrompt = cleanText.contains("❯") && !cleanText.contains("Perusing") && !cleanText.contains("Harmonizing") && !cleanText.contains("Thinking")
                if hasIdlePrompt && scannedAssistantCount >= existingAssistantCount {
                    // Claude 已完成但可能回复太长滚出了屏幕
                    // 再次全量扫描获取完整对话
                    let fullScan = Self.scanConversations(lines)
                    mergeScannedMessages(fullScan)
                    isThinking = false
                }
            }
        }
    }

    /// 合并扫描到的消息和本地消息
    private func mergeScannedMessages(_ scanned: [ClaudeChatItem]) {
        var merged = chatMessages
        for item in scanned {
            let exists = merged.contains { $0.content == item.content && $0.role == item.role }
            if !exists {
                merged.append(item)
            }
        }
        if merged.count != chatMessages.count {
            messageStore.claudeChats[surfaceID] = merged
        }
    }

    // MARK: - 屏幕内容扫描

    /// 去除 ANSI 转义码
    static func stripAnsi(_ line: String) -> String {
        var result = ""
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\u{1B}" {
                i = line.index(after: i)
                guard i < line.endIndex else { break }
                if line[i] == "[" {
                    i = line.index(after: i)
                    while i < line.endIndex {
                        if line[i].asciiValue.map({ $0 >= 0x40 && $0 <= 0x7E }) == true { i = line.index(after: i); break }
                        i = line.index(after: i)
                    }
                } else if line[i] == "]" {
                    i = line.index(after: i)
                    while i < line.endIndex {
                        if line[i] == "\u{07}" { i = line.index(after: i); break }
                        if line[i] == "\u{1B}" { let ni = line.index(after: i); if ni < line.endIndex && line[ni] == "\\" { i = line.index(after: ni); break } }
                        i = line.index(after: i)
                    }
                } else { i = line.index(after: i) }
                continue
            }
            if let s = c.unicodeScalars.first {
                let v = s.value
                if v < 0x20 && v != 0x09 { i = line.index(after: i); continue }
                if (v >= 0xE000 && v <= 0xF8FF) || v >= 0xF0000 { i = line.index(after: i); continue }
                if (v >= 0x2500 && v <= 0x259F) || (v >= 0x2800 && v <= 0x28FF) { i = line.index(after: i); continue }
            }
            result.append(c)
            i = line.index(after: i)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// 判断行是否为 Claude TUI 噪音
    static func isNoiseLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.count <= 2 { return true }
        if t.allSatisfy({ "─━_=-~".contains($0) }) { return true }

        let noisePatterns = [
            "Claude Code v", "with medium effort", "with high effort", "with low effort",
            "Claude Max", "Claude API", "Loamwaddle",
            "Context", "git:(", "git:", "main*)", "main!?",
            "<(", "._>", "`--'", "^^^",
            "1M context", "200K context",
            "Harmonizing", "Perusing", "Thinking", "Hashing",
            "Compiling", "Reasoning", "Analyzing", "Generating",
            "Initializing", "Processing", "Connecting", "Searching",
            "Accessing workspace", "safety check", "trust this folder",
            "Security guide", "Tip:", "Usage", "Weekly", "resets in",
            "Enter to confirm", "Esc to cancel",
        ]
        return noisePatterns.contains { t.contains($0) }
    }

    /// 从终端屏幕扫描对话（user prompt + assistant response 对）
    static func scanConversations(_ lines: [String]) -> [ClaudeChatItem] {
        var items: [ClaudeChatItem] = []
        var i = 0
        let cleaned = lines.map { stripAnsi($0) }

        while i < cleaned.count {
            let line = cleaned[i].trimmingCharacters(in: .whitespaces)

            // 检测用户输入行：以 ❯ 开头后跟文本
            if let userText = extractUserPrompt(line) {
                if !userText.isEmpty {
                    items.append(ClaudeChatItem(
                        id: "scan-user-\(items.count)",
                        role: .user,
                        content: userText,
                        timestamp: Date()
                    ))
                }
                i += 1

                // 收集接下来的 Claude 回复（直到下一个 prompt 或屏幕结束）
                var responseLines: [String] = []
                while i < cleaned.count {
                    let nextLine = cleaned[i].trimmingCharacters(in: .whitespaces)
                    // 遇到下一个 prompt，结束收集
                    if extractUserPrompt(nextLine) != nil { break }
                    // 跳过噪音行
                    if !isNoiseLine(nextLine) {
                        responseLines.append(nextLine)
                    }
                    i += 1
                }

                let response = cleanAssistantText(responseLines.joined(separator: "\n"))
                if !response.isEmpty && response.count > 3 {
                    items.append(ClaudeChatItem(
                        id: "scan-assist-\(items.count)",
                        role: .assistant,
                        content: response,
                        timestamp: Date()
                    ))
                }
            } else {
                i += 1
            }
        }

        return items
    }

    /// 从行中提取用户 prompt 文本（如果是 prompt 行的话）
    static func extractUserPrompt(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        // Claude Code prompt: ❯ text 或 > text（确保是 prompt，不是 Claude 回复中的引用）
        if t.hasPrefix("❯ ") && t.count > 2 { return String(t.dropFirst(2)) }
        // 注意：不匹配 "> " 因为 Claude 回复中可能有 "> 引用" 格式
        return nil
    }

    /// 清理 Claude 回复中的 bullet 前缀（● ✦ 等）
    static func cleanAssistantText(_ text: String) -> String {
        var result = text
        // 移除行首的 bullet 字符
        let bulletPrefixes = ["● ", "✦ ", "• ", "○ ", "◉ "]
        for prefix in bulletPrefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
