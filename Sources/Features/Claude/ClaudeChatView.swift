import SwiftUI

/// Claude Code 聊天模式 — 直接从 JSONL 会话文件读取结构化消息
/// 跟 happy 项目一样，不解析终端输出
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    @State private var inputText = ""
    @State private var isThinking = false
    @State private var activityLabel = ""
    @State private var sessionInfo: (model: String, project: String, context: String) = ("", "", "")
    @State private var refreshTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool
    /// 已获取的最大消息序号（用于增量拉取）
    @State private var lastSeq = 0
    /// 是否显示 / 命令菜单
    @State private var showSlashMenu = false
    /// 是否显示 @ 文件选择器
    @State private var showFilePicker = false
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
            // 清空缓存，以 JSONL 为唯一数据源
            messageStore.claudeChats[surfaceID] = nil
            lastSeq = 0
            fetchMessages()
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
                    if chatMessages.isEmpty && !isThinking {
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
                }.padding(.horizontal, 14)
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
            Image(systemName: "sparkles").font(.system(size: 24)).foregroundStyle(.purple).padding(.top, 16)
            if !sessionInfo.model.isEmpty {
                HStack(spacing: 8) {
                    Text(sessionInfo.model)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.purple.opacity(0.8))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12)).clipShape(Capsule())
                    if !sessionInfo.context.isEmpty {
                        Text(sessionInfo.context).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            if !sessionInfo.project.isEmpty {
                Text(sessionInfo.project).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
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
                Text(msg.content).font(.system(size: 15)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(red: 0.22, green: 0.42, blue: 0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                claudeAvatar
                markdownText(msg.content)
                Spacer(minLength: 20)
            }
        case .tool(name: let name):
            NavigationLink(destination: ToolDetailView(
                toolName: name,
                input: msg.content,
                result: msg.toolResult,
                state: msg.toolState
            )) {
                HStack(alignment: .top, spacing: 8) {
                    Color.clear.frame(width: 26)
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: toolIcon(name)).font(.system(size: 10)).foregroundStyle(toolColor(name))
                                Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                            }
                            if !msg.content.isEmpty {
                                Text(msg.content).font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.35)).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 8)
                        // 状态图标
                        toolStateIcon(msg.toolState)
                    }
                    .padding(10).background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer(minLength: 20)
                }
            }
            .buttonStyle(.plain)
        case .system:
            HStack {
                Spacer()
                Text(msg.content).font(.system(size: 11)).foregroundStyle(.white.opacity(0.2))
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func toolStateIcon(_ state: ClaudeChatItem.ToolState) -> some View {
        switch state {
        case .running:
            ProgressView().scaleEffect(0.5).tint(.orange).frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green.opacity(0.6))
        case .error:
            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.red.opacity(0.6))
        case .none:
            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.white.opacity(0.2))
        }
    }

    private func toolColor(_ name: String) -> Color {
        switch name {
        case "Read": return .blue
        case "Write", "Edit": return .orange
        case "Bash": return .green
        case "Grep", "Glob": return .cyan
        case "Agent", "Task": return .purple
        default: return .gray
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

    /// Markdown 渲染
    @ViewBuilder
    private func markdownText(_ content: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(content)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var thinkingView: some View {
        HStack(alignment: .top, spacing: 8) {
            claudeAvatar
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6).tint(.purple.opacity(0.6))
                Text(statusLabel)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4)).italic()
            }.padding(.top, 3)
            Spacer()
        }
    }

    /// 当前状态显示文本
    private var statusLabel: String {
        switch activityLabel {
        case "tool_running": return "执行工具中…"
        case "thinking": return "思考中…"
        default: return "处理中…"
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
                        inputText = item.cmd; showSlashMenu = false; isInputFocused = true
                    } label: {
                        HStack {
                            Text(item.cmd).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(.orange)
                            Spacer()
                            Text(item.desc).font(.system(size: 12)).foregroundStyle(.white.opacity(0.3))
                        }.padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    Divider().background(Color.white.opacity(0.05))
                }
            }
        }.frame(maxHeight: 200).background(Color(red: 0.1, green: 0.1, blue: 0.12))
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
            }.padding(.horizontal, 16).padding(.vertical, 8)

            if fileList.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.6).tint(.blue)
                    Text("加载…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.3))
                }.padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(fileList, id: \.name) { file in
                            Button {
                                let atRef = "@\(file.name) "
                                inputText = inputText.hasSuffix("@") ? String(inputText.dropLast()) + atRef : inputText + atRef
                                showFilePicker = false; isInputFocused = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.text")
                                        .font(.system(size: 12)).foregroundStyle(file.isDirectory ? .yellow : .blue).frame(width: 16)
                                    Text(file.name).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                                    Spacer()
                                }.padding(.horizontal, 16).padding(.vertical, 8)
                            }
                        }
                    }
                }.frame(maxHeight: 200)
            }
        }.background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("@", color: .blue) {
                        inputText += "@"; isInputFocused = true; loadFileList(); showFilePicker = true; showSlashMenu = false
                    }
                    chip("/", color: .orange) { inputText = "/"; showSlashMenu = true; showFilePicker = false; isInputFocused = true }
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 16)
                    chip("^C", color: .red) { sendKey("c", "ctrl") }
                    chip("Esc", color: .gray) { sendKey("escape", "") }
                    chip("/compact", color: .purple) { sendDirect("/compact\n") }
                    chip("/status", color: .green) { sendDirect("/status\n") }
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
        }.background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }

    private func chip(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.1)).foregroundStyle(color.opacity(0.7)).clipShape(Capsule())
        }
    }

    private func handleInputChange(_ text: String) {
        showSlashMenu = text.hasPrefix("/") && !text.contains(" ")
        if text.hasSuffix("@") && !showFilePicker { loadFileList(); showFilePicker = true }
    }

    private func loadFileList() {
        let path = sessionInfo.project.isEmpty ? "~" : sessionInfo.project
        relayConnection.sendWithResponse(["method": "file.list", "params": ["path": path]]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let entries = resultDict["entries"] as? [[String: Any]] {
                fileList = entries.compactMap {
                    guard let name = $0["name"] as? String else { return nil }
                    return FileEntry(name: name, isDirectory: ($0["type"] as? String) == "directory")
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
        inputText = ""; showSlashMenu = false; showFilePicker = false

        // 本地立即显示用户消息
        appendMessage(ClaudeChatItem(id: UUID().uuidString, role: .user, content: text, timestamp: Date()))

        // 发送到终端
        sendDirect(text + "\n")
        isThinking = true
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

    // MARK: - 从 JSONL 拉取消息（跟 happy 的 sessionScanner 一样）

    private func fetchMessages() {
        relayConnection.sendWithResponse([
            "method": "claude.messages",
            "params": ["surface_id": surfaceID, "after_seq": lastSeq],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            guard let messages = resultDict["messages"] as? [[String: Any]] else { return }

            if let totalSeq = resultDict["total_seq"] as? Int {
                lastSeq = totalSeq
            }

            // 更新整体状态
            let status = resultDict["status"] as? String ?? "idle"
            activityLabel = status
            isThinking = (status == "thinking" || status == "tool_running")

            processJsonlMessages(messages)
        }
    }

    /// 将 JSONL 结构化消息转换为 UI 消息
    private func processJsonlMessages(_ messages: [[String: Any]]) {
        var newItems: [ClaudeChatItem] = []
        // 收集 tool_result，用于关联到 tool_use
        var toolResults: [String: (content: String, isError: Bool)] = [:]

        // 第一遍：收集所有 tool_result
        for msg in messages {
            let blocks = msg["content"] as? [[String: Any]] ?? []
            for block in blocks {
                if (block["type"] as? String) == "tool_result",
                   let toolUseId = block["tool_use_id"] as? String {
                    let content = block["content"] as? String ?? ""
                    let isError = block["is_error"] as? Bool ?? false
                    toolResults[toolUseId] = (content, isError)
                }
            }
        }

        // 第二遍：构建消息列表
        for msg in messages {
            let type = msg["type"] as? String ?? ""
            let uuid = msg["uuid"] as? String ?? UUID().uuidString
            let blocks = msg["content"] as? [[String: Any]] ?? []
            let stopReason = msg["stop_reason"] as? String

            if type == "user" {
                // 用户消息：只显示纯文本
                let textBlocks = blocks.filter { ($0["type"] as? String) == "text" }
                if !textBlocks.isEmpty {
                    let text = textBlocks.compactMap { $0["text"] as? String }.joined()
                    if !text.isEmpty {
                        let exists = chatMessages.contains { $0.role == .user && $0.content == text }
                        if !exists {
                            newItems.append(ClaudeChatItem(id: uuid, role: .user, content: text, timestamp: Date()))
                        }
                    }
                }
            } else if type == "assistant" {
                for block in blocks {
                    let blockType = block["type"] as? String ?? ""
                    switch blockType {
                    case "text":
                        if let text = block["text"] as? String, !text.isEmpty {
                            let exists = chatMessages.contains { $0.role == .assistant && $0.content == text }
                            if !exists {
                                newItems.append(ClaudeChatItem(
                                    id: "\(uuid)-text", role: .assistant,
                                    content: text, timestamp: Date()
                                ))
                            }
                        }
                    case "tool_use":
                        let toolName = block["name"] as? String ?? "Tool"
                        let toolUseId = block["id"] as? String ?? ""
                        let toolInput = block["input"] as? [String: Any] ?? [:]
                        let summary = formatToolInput(name: toolName, input: toolInput)

                        // 查找对应的 tool_result
                        let result = toolResults[toolUseId]
                        let toolState: ClaudeChatItem.ToolState
                        if let result {
                            toolState = result.isError ? .error : .completed
                        } else if stopReason == "tool_use" || stopReason == nil {
                            toolState = .running
                        } else {
                            toolState = .none
                        }

                        let exists = chatMessages.contains { $0.toolUseId == toolUseId }
                        if !exists {
                            newItems.append(ClaudeChatItem(
                                id: "\(uuid)-tool-\(toolUseId.prefix(8))",
                                role: .tool(name: toolName),
                                content: summary,
                                timestamp: Date(),
                                toolResult: result?.content,
                                toolState: toolState,
                                toolUseId: toolUseId
                            ))
                        }
                    default:
                        break
                    }
                }

                // 提取模型信息
                if let model = msg["model"] as? String, sessionInfo.model.isEmpty {
                    var info = sessionInfo
                    if model.contains("opus") { info.model = "Opus" }
                    else if model.contains("sonnet") { info.model = "Sonnet" }
                    else if model.contains("haiku") { info.model = "Haiku" }
                    sessionInfo = info
                }
            }
        }

        // 更新已有工具消息的状态和结果
        var all = messageStore.claudeChats[surfaceID] ?? []
        var updated = false
        for (idx, item) in all.enumerated() {
            guard let toolId = item.toolUseId, item.toolState == .running,
                  let result = toolResults[toolId] else { continue }
            all[idx].toolResult = result.content
            all[idx].toolState = result.isError ? .error : .completed
            updated = true
        }

        if !newItems.isEmpty {
            all.append(contentsOf: newItems)
            updated = true
        }

        if updated {
            messageStore.claudeChats[surfaceID] = all
        }
    }

    /// 格式化工具输入为简要描述
    private func formatToolInput(name: String, input: [String: Any]) -> String {
        switch name {
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Write":
            let path = input["file_path"] as? String ?? ""
            return path
        case "Edit":
            let path = input["file_path"] as? String ?? ""
            return path
        case "Bash":
            return input["command"] as? String ?? ""
        case "Grep":
            let pattern = input["pattern"] as? String ?? ""
            let path = input["path"] as? String ?? ""
            return "\(pattern) in \(path)"
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Agent":
            return input["description"] as? String ?? input["prompt"] as? String ?? ""
        default:
            // 通用：显示第一个字符串参数
            for (_, v) in input {
                if let s = v as? String, !s.isEmpty { return String(s.prefix(100)) }
            }
            return ""
        }
    }

    // MARK: - 轮询

    private func startPolling() {
        stopPolling()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                fetchMessages()
            }
        }
    }

    private func stopPolling() { refreshTask?.cancel(); refreshTask = nil }
}
