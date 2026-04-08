import SwiftUI

/// Claude Code 聊天模式 — 纯对话式，消息持久化
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    @State private var inputText = ""
    @State private var isThinking = false
    /// Claude 当前活动状态
    @State private var activityLabel = ""
    @State private var sessionInfo: (model: String, project: String, context: String) = ("", "", "")
    @State private var refreshTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool
    /// 上次扫描到的 assistant 消息数量
    @State private var lastAssistantCount = 0
    /// 是否显示 / 命令菜单
    @State private var showSlashMenu = false
    /// 是否显示 @ 文件选择器
    @State private var showFilePicker = false
    /// 文件列表
    @State private var fileList: [FileEntry] = []

    private var chatMessages: [ClaudeChatItem] {
        messageStore.claudeChats[surfaceID] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            chatArea
            if showSlashMenu { slashCommandMenu }
            if showFilePicker { filePickerView }
            inputBar
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .onAppear {
            fetchSessionInfo()
            lastAssistantCount = chatMessages.filter { $0.role == .assistant }.count
            startPolling()
        }
        .onDisappear { stopPolling() }
        .onChange(of: inputText) { _, newValue in handleInputChange(newValue) }
    }

    // MARK: - 聊天区域

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    sessionHeader.padding(.bottom, 8)

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
                        Image(systemName: toolIcon(name))
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

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder.badge.questionmark"
        case "Agent": return "person.2"
        default: return "terminal"
        }
    }

    private var claudeAvatar: some View {
        ZStack {
            Circle().fill(Color.purple.opacity(0.15)).frame(width: 26, height: 26)
            Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.purple)
        }
    }

    private var thinkingView: some View {
        HStack(alignment: .top, spacing: 8) {
            claudeAvatar
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6).tint(.purple.opacity(0.6))
                Text(activityLabel.isEmpty ? "思考中…" : activityLabel)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.3)).italic()
            }
            .padding(.top, 3)
            Spacer()
        }
    }

    // MARK: - / 命令菜单

    private let slashCommands: [(cmd: String, desc: String)] = [
        ("/compact", "压缩上下文"), ("/status", "查看状态"), ("/help", "帮助"),
        ("/clear", "清空对话"), ("/review", "代码审查"), ("/init", "初始化项目"),
        ("/config", "配置"), ("/cost", "费用统计"), ("/doctor", "诊断"),
        ("/permissions", "权限管理"), ("/memory", "记忆管理"), ("/mcp", "MCP 服务"),
    ]

    private var slashCommandMenu: some View {
        let query = String(inputText.dropFirst()).lowercased()
        let filtered = query.isEmpty ? slashCommands : slashCommands.filter { $0.cmd.contains(query) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filtered, id: \.cmd) { item in
                    Button {
                        inputText = item.cmd
                        showSlashMenu = false
                        isInputFocused = true
                    } label: {
                        HStack {
                            Text(item.cmd).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(.orange)
                            Spacer()
                            Text(item.desc).font(.system(size: 12)).foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    Divider().background(Color.white.opacity(0.05))
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    // MARK: - @ 文件选择器

    struct FileEntry { let name: String; let isDirectory: Bool }

    private var filePickerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(.blue)
                Text("选择文件").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button { showFilePicker = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            if fileList.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.6).tint(.blue)
                    Text("加载文件列表…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.3))
                }.padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(fileList, id: \.name) { file in
                            Button {
                                let atRef = "@\(file.name) "
                                inputText = inputText.hasSuffix("@") ? String(inputText.dropLast()) + atRef : inputText + atRef
                                showFilePicker = false
                                isInputFocused = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.text")
                                        .font(.system(size: 12))
                                        .foregroundStyle(file.isDirectory ? .yellow : .blue)
                                        .frame(width: 16)
                                    Text(file.name).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                                    Spacer()
                                }.padding(.horizontal, 16).padding(.vertical, 8)
                            }
                        }
                    }
                }.frame(maxHeight: 200)
            }
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("@", color: .blue) {
                        inputText += "@"; isInputFocused = true
                        loadFileList(); showFilePicker = true; showSlashMenu = false
                    }
                    chip("/", color: .orange) {
                        inputText = "/"; showSlashMenu = true; showFilePicker = false; isInputFocused = true
                    }
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 16)
                    chip("^C", color: .red) { sendKey("c", "ctrl") }
                    chip("Esc", color: .gray) { sendKey("escape", "") }
                    chip("/compact", color: .purple) { sendDirect("/compact\n") }
                    chip("/status", color: .green) { sendDirect("/status\n") }
                    chip("回车", color: .white.opacity(0.6)) { sendKey("return", "") }
                }.padding(.horizontal, 12).padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                TextField("", text: $inputText, prompt: Text("消息...").foregroundStyle(.gray.opacity(0.6)), axis: .vertical)
                    .font(.system(size: 15)).foregroundStyle(.white)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .lineLimit(1...4).focused($isInputFocused)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onSubmit { send() }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                        .foregroundStyle(inputText.isEmpty ? .gray.opacity(0.3) : .purple)
                }.disabled(inputText.isEmpty)
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }

    private func chip(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.1)).foregroundStyle(color.opacity(0.7))
                .clipShape(Capsule())
        }
    }

    private func handleInputChange(_ text: String) {
        showSlashMenu = text.hasPrefix("/") && !text.contains(" ")
        if text.hasSuffix("@") && !showFilePicker {
            loadFileList(); showFilePicker = true
        }
    }

    private func loadFileList() {
        let path = sessionInfo.project.isEmpty ? "~" : sessionInfo.project
        relayConnection.sendWithResponse([
            "method": "file.list", "params": ["path": path],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let entries = resultDict["entries"] as? [[String: Any]] {
                fileList = entries.compactMap { entry in
                    guard let name = entry["name"] as? String else { return nil }
                    let isDir = (entry["type"] as? String) == "directory"
                    return FileEntry(name: name, isDirectory: isDir)
                }.sorted { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
        }
    }

    // MARK: - 发送

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        showSlashMenu = false; showFilePicker = false

        appendMessage(ClaudeChatItem(id: UUID().uuidString, role: .user, content: text, timestamp: Date()))
        sendDirect(text + "\n")
        isThinking = true; activityLabel = ""
    }

    private func sendDirect(_ text: String) {
        relayConnection.send(["method": "surface.send_text", "params": ["surface_id": surfaceID, "text": text]])
    }

    private func sendKey(_ key: String, _ mods: String) {
        let combinedKey = mods.isEmpty ? key : "\(mods)-\(key)"
        relayConnection.send(["method": "surface.send_key", "params": ["surface_id": surfaceID, "key": combinedKey]])
    }

    // MARK: - 消息持久化

    private func appendMessage(_ msg: ClaudeChatItem) {
        var msgs = messageStore.claudeChats[surfaceID] ?? []
        msgs.append(msg)
        messageStore.claudeChats[surfaceID] = msgs
    }

    // MARK: - 轮询

    private func fetchSessionInfo() {
        readTerminal { lines in
            sessionInfo = ClaudeOutputParser.parseSessionInfo(lines)
            if chatMessages.isEmpty { loadHistoryFromScreen(lines) }
        }
    }

    private func startPolling() {
        stopPolling()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { break }
                pollForResponse()
            }
        }
    }

    private func stopPolling() { refreshTask?.cancel(); refreshTask = nil }

    private func readTerminal(completion: @escaping ([String]) -> Void) {
        relayConnection.sendWithResponse([
            "method": "read_screen", "params": ["surface_id": surfaceID],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let lines = resultDict["lines"] as? [String] { completion(lines) }
        }
    }

    private func loadHistoryFromScreen(_ lines: [String]) {
        let conversations = Self.scanConversations(lines)
        if !conversations.isEmpty {
            messageStore.claudeChats[surfaceID] = conversations
            lastAssistantCount = conversations.filter { $0.role == .assistant }.count
        }
    }

    /// 轮询检测新回复
    private func pollForResponse() {
        readTerminal { lines in
            sessionInfo = ClaudeOutputParser.parseSessionInfo(lines)
            let cleaned = lines.map { Self.stripAnsi($0) }

            // 检测活动状态
            let activity = Self.detectActivity(cleaned)
            activityLabel = activity

            // 检测 idle prompt（Claude 完成的标志）
            let isIdle = Self.detectIdlePrompt(cleaned)

            // 扫描对话
            let scanned = Self.scanConversations(lines)
            let scannedAssistantCount = scanned.filter { $0.role == .assistant }.count

            if scannedAssistantCount > lastAssistantCount {
                // 有新回复
                if let newReply = scanned.last(where: { $0.role == .assistant }) {
                    let alreadyHas = chatMessages.contains { $0.role == .assistant && $0.content == newReply.content }
                    if !alreadyHas { appendMessage(newReply) }
                }
                lastAssistantCount = scannedAssistantCount
                isThinking = false; activityLabel = ""
            } else if isThinking && isIdle {
                // thinking 状态但检测到 idle，回复可能滚出屏幕
                if scannedAssistantCount == lastAssistantCount {
                    // 尝试从屏幕提取内容
                    let extracted = Self.extractLastResponse(cleaned)
                    if !extracted.isEmpty {
                        appendMessage(ClaudeChatItem(
                            id: UUID().uuidString, role: .assistant,
                            content: extracted, timestamp: Date()
                        ))
                        lastAssistantCount += 1
                    }
                }
                isThinking = false; activityLabel = ""
            }
        }
    }

    // MARK: - 终端解析

    /// 检测 Claude 活动状态
    static func detectActivity(_ lines: [String]) -> String {
        let activities: [(String, String)] = [
            ("Thinking", "思考中…"), ("Reasoning", "推理中…"), ("Analyzing", "分析中…"),
            ("Searching", "搜索中…"), ("Reading", "读取文件…"), ("Writing", "写入文件…"),
            ("Editing", "编辑中…"), ("Compiling", "编译中…"), ("Generating", "生成中…"),
            ("Processing", "处理中…"), ("Harmonizing", "整合中…"), ("Perusing", "审阅中…"),
            ("Hashing", "计算中…"), ("Initializing", "初始化…"), ("Connecting", "连接中…"),
        ]
        // 只检查屏幕中间区域（跳过顶部启动信息和底部状态栏）
        let midLines = lines.dropFirst(3).dropLast(8)
        let text = midLines.joined(separator: " ")
        for (pattern, label) in activities {
            if text.contains(pattern) { return label }
        }
        return ""
    }

    /// 检测 idle prompt — 从底部向上搜索，跳过状态栏/鸭子区域
    /// Claude 完成回复后屏幕结构：
    ///   ❯ user_input       ← 用户输入
    ///   ● response...      ← Claude 回复
    ///   ❯                  ← idle prompt（空的，等待输入）
    ///   ────────────        ← 分隔线
    ///   [Opus 4.6 ...]     ← 状态栏
    ///   Context 4%         ← 上下文用量
    ///   ...Loamwaddle...   ← 鸭子
    static func detectIdlePrompt(_ lines: [String]) -> Bool {
        // 从底部向上搜索，跳过空行和状态栏噪音
        for line in lines.reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)

            // 跳过空行
            if t.isEmpty { continue }

            // 跳过状态栏/鸭子区域的噪音
            if isStatusOrDecoration(t) { continue }

            // 找到了有意义的行
            // idle prompt：单独的 ❯ 或 ❯ 后面只有空白/光标
            if t == "❯" || t == ">" { return true }

            // 如果找到了 ❯ 开头后面有文本，说明正在输入，也算 idle
            if t.hasPrefix("❯ ") || t.hasPrefix("> ") { return true }

            // 如果找到了 ● 开头（Claude 回复行），且后面没有活动指示，可能 Claude 刚回复完
            if t.hasPrefix("●") { return true }

            // 找到其他内容，不是 idle
            return false
        }
        return false
    }

    /// 判断是否为状态栏、分隔线、鸭子等装饰内容
    static func isStatusOrDecoration(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        // 纯装饰字符
        if t.allSatisfy({ "─━═_=-~│┃".contains($0) }) { return true }
        // 状态栏关键词
        let statusPatterns = [
            "Context", "Usage", "Weekly", "resets in", "git:(", "git:",
            "Opus", "Sonnet", "Haiku", "1M context", "200K context",
            "Loamwaddle", "<(", "._>", "`--'", "^^^", "___",
            "main*)", "main!?", "main)",
        ]
        return statusPatterns.contains { t.contains($0) }
    }

    /// 从屏幕提取最后一个回复（当 scanConversations 没找到时的兜底）
    static func extractLastResponse(_ lines: [String]) -> String {
        // 从底部向上找到最后一个 ❯ prompt（idle），然后向上收集直到遇到上一个 ❯（用户输入）
        var idleIdx = -1
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if isStatusOrDecoration(t) || t.isEmpty { continue }
            if t == "❯" || t.hasPrefix("❯ ") {
                idleIdx = i
                break
            }
            break
        }
        guard idleIdx > 0 else { return "" }

        // 从 idle prompt 向上收集回复行
        var responseLines: [String] = []
        for i in stride(from: idleIdx - 1, through: 0, by: -1) {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            // 遇到用户 prompt，停止
            if t.hasPrefix("❯ ") && t.count > 2 { break }
            if !t.isEmpty && !isNoiseLine(t) {
                responseLines.insert(t, at: 0)
            }
        }

        let response = cleanAssistantText(responseLines.joined(separator: "\n"))
        return response.count > 2 ? response : ""
    }

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

    static func isNoiseLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.count <= 2 { return true }
        if t.allSatisfy({ "─━_=-~".contains($0) }) { return true }
        let noisePatterns = [
            "Claude Code v", "with medium effort", "with high effort", "with low effort",
            "Claude Max", "Claude API", "Loamwaddle",
            "Context", "git:(", "git:", "main*)", "main!?",
            "<(", "._>", "`--'", "^^^", "___",
            "1M context", "200K context",
            "Harmonizing", "Perusing", "Thinking", "Hashing",
            "Compiling", "Reasoning", "Analyzing", "Generating",
            "Initializing", "Processing", "Connecting", "Searching",
            "Accessing workspace", "safety check", "trust this folder",
            "Security guide", "Tip:", "Usage", "Weekly", "resets in",
            "Enter to confirm", "Esc to cancel",
            "Reading", "Writing", "Editing",
        ]
        return noisePatterns.contains { t.contains($0) }
    }

    /// 从终端屏幕扫描对话（只扫描 Claude Code 启动之后的内容）
    static func scanConversations(_ lines: [String]) -> [ClaudeChatItem] {
        var items: [ClaudeChatItem] = []
        let cleaned = lines.map { stripAnsi($0) }

        // 找到 Claude Code 启动标志
        var startIndex = 0
        for (idx, line) in cleaned.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("Claude Code v") {
                startIndex = idx + 1
            }
        }

        var i = startIndex
        while i < cleaned.count {
            let line = cleaned[i].trimmingCharacters(in: .whitespaces)

            // 检测用户输入：❯ text
            if let userText = extractUserPrompt(line) {
                if !userText.isEmpty {
                    items.append(ClaudeChatItem(
                        id: "scan-user-\(items.count)", role: .user,
                        content: userText, timestamp: Date()
                    ))
                }
                i += 1

                // 收集 Claude 回复（直到下一个 ❯ 或屏幕结束）
                var responseLines: [String] = []
                while i < cleaned.count {
                    let nextLine = cleaned[i].trimmingCharacters(in: .whitespaces)
                    if extractUserPrompt(nextLine) != nil { break }
                    // 空的 ❯（idle prompt），停止
                    if nextLine == "❯" || nextLine == ">" { i += 1; break }
                    // 跳过状态栏
                    if isStatusOrDecoration(nextLine) { i += 1; continue }
                    // 跳过噪音
                    if !isNoiseLine(nextLine) {
                        // 去掉 ● 前缀（Claude 回复标记）
                        let content = nextLine.hasPrefix("●") ? String(nextLine.dropFirst()).trimmingCharacters(in: .whitespaces) : nextLine
                        if !content.isEmpty {
                            responseLines.append(content)
                        }
                    }
                    i += 1
                }

                let response = cleanAssistantText(responseLines.joined(separator: "\n"))
                if !response.isEmpty && response.count > 1 {
                    items.append(ClaudeChatItem(
                        id: "scan-assist-\(items.count)", role: .assistant,
                        content: response, timestamp: Date()
                    ))
                }
            } else {
                i += 1
            }
        }

        return items
    }

    static func extractUserPrompt(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("❯ ") && t.count > 2 { return String(t.dropFirst(2)) }
        return nil
    }

    static func cleanAssistantText(_ text: String) -> String {
        var result = text
        let bulletPrefixes = ["● ", "✦ ", "• ", "○ ", "◉ "]
        for prefix in bulletPrefixes {
            if result.hasPrefix(prefix) { result = String(result.dropFirst(prefix.count)) }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
