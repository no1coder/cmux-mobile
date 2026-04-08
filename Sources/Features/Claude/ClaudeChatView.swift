import SwiftUI

/// Claude Code 聊天模式 — 纯对话式，消息持久化
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    @State private var inputText = ""
    @State private var isThinking = false
    /// Claude 当前活动状态（Thinking/Reading/Writing 等）
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
    /// 文件列表（用于 @file 选择器）
    @State private var fileList: [FileEntry] = []

    /// 从 MessageStore 读取持久化的消息
    private var chatMessages: [ClaudeChatItem] {
        messageStore.claudeChats[surfaceID] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            chatArea

            // / 命令自动补全
            if showSlashMenu {
                slashCommandMenu
            }

            // @ 文件选择器
            if showFilePicker {
                filePickerView
            }

            inputBar
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .onAppear {
            fetchSessionInfo()
            lastAssistantCount = chatMessages.filter { $0.role == .assistant }.count
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .onChange(of: inputText) { _, newValue in
            // 检测 @ 和 / 触发自动补全
            handleInputChange(newValue)
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

    /// 根据工具名返回图标
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
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.purple.opacity(0.6))
                Text(activityLabel.isEmpty ? "思考中…" : activityLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    .italic()
            }
            .padding(.top, 3)
            Spacer()
        }
    }

    // MARK: - / 命令自动补全

    /// Claude Code 常用命令
    private let slashCommands: [(cmd: String, desc: String)] = [
        ("/compact", "压缩上下文"),
        ("/status", "查看状态"),
        ("/help", "帮助"),
        ("/clear", "清空对话"),
        ("/review", "代码审查"),
        ("/init", "初始化项目"),
        ("/bug", "报告 bug"),
        ("/config", "配置"),
        ("/cost", "费用统计"),
        ("/login", "登录"),
        ("/logout", "登出"),
        ("/doctor", "诊断"),
        ("/permissions", "权限管理"),
        ("/memory", "记忆管理"),
        ("/mcp", "MCP 服务"),
    ]

    private var slashCommandMenu: some View {
        let query = String(inputText.dropFirst()).lowercased()
        let filtered = query.isEmpty
            ? slashCommands
            : slashCommands.filter { $0.cmd.lowercased().contains(query) }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filtered, id: \.cmd) { item in
                    Button {
                        inputText = item.cmd
                        showSlashMenu = false
                        isInputFocused = true
                    } label: {
                        HStack {
                            Text(item.cmd)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(.orange)
                            Spacer()
                            Text(item.desc)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    Divider().background(Color.white.opacity(0.05))
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    // MARK: - @ 文件选择器

    private var filePickerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("选择文件")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button {
                    showFilePicker = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if fileList.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.6).tint(.blue)
                    Text("加载文件列表…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(fileList, id: \.name) { file in
                            Button {
                                // 将 @文件路径 插入输入框
                                let atRef = "@\(file.name) "
                                if inputText.hasSuffix("@") {
                                    inputText = String(inputText.dropLast()) + atRef
                                } else {
                                    inputText += atRef
                                }
                                showFilePicker = false
                                isInputFocused = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.text")
                                        .font(.system(size: 12))
                                        .foregroundStyle(file.isDirectory ? .yellow : .blue)
                                        .frame(width: 16)
                                    Text(file.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    /// 简单的文件条目
    struct FileEntry {
        let name: String
        let isDirectory: Bool
    }

    // MARK: - 输入区域

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("@", color: .blue) {
                        inputText += "@"
                        isInputFocused = true
                        loadFileList()
                        showFilePicker = true
                        showSlashMenu = false
                    }
                    chip("/", color: .orange) {
                        inputText = "/"
                        showSlashMenu = true
                        showFilePicker = false
                        isInputFocused = true
                    }
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

    /// 输入内容变化时检测 @ 和 / 触发
    private func handleInputChange(_ text: String) {
        if text == "/" {
            showSlashMenu = true
            showFilePicker = false
        } else if text.hasPrefix("/") && text.count > 1 {
            showSlashMenu = true
            showFilePicker = false
        } else {
            showSlashMenu = false
        }

        if text.hasSuffix("@") && !showFilePicker {
            loadFileList()
            showFilePicker = true
        }
    }

    // MARK: - 文件列表加载

    private func loadFileList() {
        // 使用 session 中的项目路径
        let path = sessionInfo.project.isEmpty ? "~" : sessionInfo.project
        relayConnection.sendWithResponse([
            "method": "file.list",
            "params": ["path": path],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let entries = resultDict["entries"] as? [[String: Any]] {
                fileList = entries.compactMap { entry in
                    guard let name = entry["name"] as? String else { return nil }
                    let isDir = (entry["type"] as? String) == "directory"
                    return FileEntry(name: name, isDirectory: isDir)
                }
                // 排序：目录在前，按名称排序
                fileList.sort { a, b in
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
        showSlashMenu = false
        showFilePicker = false

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
        activityLabel = ""
    }

    private func sendDirect(_ text: String) {
        relayConnection.send([
            "method": "surface.send_text",
            "params": ["surface_id": surfaceID, "text": text],
        ])
    }

    private func sendKey(_ key: String, _ mods: String) {
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

    /// 从屏幕内容加载已有对话历史
    private func loadHistoryFromScreen(_ lines: [String]) {
        let conversations = Self.scanConversations(lines)
        if !conversations.isEmpty {
            messageStore.claudeChats[surfaceID] = conversations
            lastAssistantCount = conversations.filter { $0.role == .assistant }.count
        }
    }

    /// 轮询检测新回复 — 基于状态机
    private func pollForResponse() {
        readTerminal { lines in
            sessionInfo = ClaudeOutputParser.parseSessionInfo(lines)

            let cleaned = lines.map { Self.stripAnsi($0) }
            let joinedText = cleaned.joined(separator: " ")

            // 检测 Claude 活动状态
            let activity = detectActivity(joinedText)
            activityLabel = activity

            // 检测是否有 idle prompt（Claude 完成回复的标志）
            let hasIdlePrompt = detectIdlePrompt(cleaned)

            if isThinking {
                if hasIdlePrompt {
                    // Claude 已完成回复，提取新的回复内容
                    let scanned = Self.scanConversations(lines)
                    let scannedAssistantCount = scanned.filter { $0.role == .assistant }.count

                    if scannedAssistantCount > lastAssistantCount {
                        // 有新回复，追加最后一条
                        if let newReply = scanned.last(where: { $0.role == .assistant }) {
                            let alreadyHas = chatMessages.contains {
                                $0.role == .assistant && $0.content == newReply.content
                            }
                            if !alreadyHas {
                                appendMessage(newReply)
                            }
                        }
                        lastAssistantCount = scannedAssistantCount
                    } else if scannedAssistantCount == lastAssistantCount {
                        // 回复可能太长滚出屏幕了，添加一个提示
                        let hasNewContent = cleaned.contains { line in
                            let t = line.trimmingCharacters(in: .whitespaces)
                            return !t.isEmpty && !Self.isNoiseLine(t) && Self.extractUserPrompt(t) == nil
                        }
                        if hasNewContent {
                            appendMessage(ClaudeChatItem(
                                id: UUID().uuidString,
                                role: .assistant,
                                content: "（回复已完成，内容较长请在终端中查看）",
                                timestamp: Date()
                            ))
                            lastAssistantCount += 1
                        }
                    }

                    isThinking = false
                    activityLabel = ""
                }
            } else {
                // 非 thinking 状态，检查是否有从屏幕扫描到的新消息
                let scanned = Self.scanConversations(lines)
                let scannedAssistantCount = scanned.filter { $0.role == .assistant }.count

                if scannedAssistantCount > lastAssistantCount {
                    if let newReply = scanned.last(where: { $0.role == .assistant }) {
                        let alreadyHas = chatMessages.contains {
                            $0.role == .assistant && $0.content == newReply.content
                        }
                        if !alreadyHas {
                            appendMessage(newReply)
                        }
                    }
                    lastAssistantCount = scannedAssistantCount
                }
            }
        }
    }

    /// 检测 Claude 当前活动状态
    private func detectActivity(_ text: String) -> String {
        let activities: [(pattern: String, label: String)] = [
            ("Thinking", "思考中…"),
            ("Reasoning", "推理中…"),
            ("Analyzing", "分析中…"),
            ("Searching", "搜索中…"),
            ("Reading", "读取文件…"),
            ("Writing", "写入文件…"),
            ("Editing", "编辑中…"),
            ("Compiling", "编译中…"),
            ("Generating", "生成中…"),
            ("Processing", "处理中…"),
            ("Harmonizing", "整合中…"),
            ("Perusing", "审阅中…"),
            ("Hashing", "计算中…"),
            ("Initializing", "初始化…"),
            ("Connecting", "连接中…"),
        ]
        for (pattern, label) in activities {
            if text.contains(pattern) { return label }
        }
        return ""
    }

    /// 检测 idle prompt — Claude 回复完成的标志
    /// 屏幕最后几行出现 ❯ 且后面没有活动指示
    private func detectIdlePrompt(_ lines: [String]) -> Bool {
        let lastLines = lines.suffix(5)
        for line in lastLines {
            let t = line.trimmingCharacters(in: .whitespaces)
            // 空的 prompt 或带光标的 prompt
            if t == "❯" || t.hasPrefix("❯ ") {
                // 确认不在活动中
                let joinedLast = lastLines.joined(separator: " ")
                let activePatterns = ["Thinking", "Reasoning", "Analyzing", "Searching",
                                      "Reading", "Writing", "Editing", "Compiling",
                                      "Generating", "Processing", "Harmonizing", "Perusing",
                                      "Hashing", "Initializing", "Connecting"]
                let isActive = activePatterns.contains { joinedLast.contains($0) }
                return !isActive
            }
        }
        return false
    }

    // MARK: - 屏幕内容扫描

    /// 去除 ANSI 转义码和特殊字符
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
            "Reading", "Writing", "Editing",
        ]
        return noisePatterns.contains { t.contains($0) }
    }

    /// 从终端屏幕扫描对话
    static func scanConversations(_ lines: [String]) -> [ClaudeChatItem] {
        var items: [ClaudeChatItem] = []
        var i = 0
        let cleaned = lines.map { stripAnsi($0) }

        while i < cleaned.count {
            let line = cleaned[i].trimmingCharacters(in: .whitespaces)

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

                // 收集 Claude 回复
                var responseLines: [String] = []
                while i < cleaned.count {
                    let nextLine = cleaned[i].trimmingCharacters(in: .whitespaces)
                    if extractUserPrompt(nextLine) != nil { break }
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

    static func extractUserPrompt(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("❯ ") && t.count > 2 { return String(t.dropFirst(2)) }
        return nil
    }

    static func cleanAssistantText(_ text: String) -> String {
        var result = text
        let bulletPrefixes = ["● ", "✦ ", "• ", "○ ", "◉ "]
        for prefix in bulletPrefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
