import SwiftUI
import UIKit

/// Claude Code 聊天模式 — 直接从 JSONL 会话文件读取结构化消息
/// 跟 happy 项目一样，不解析终端输出
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var inputText = ""
    @State private var isThinking = false
    @State private var activityLabel = ""
    @State private var sessionInfo: (model: String, project: String, context: String) = ("", "", "")
    @State private var refreshTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool
    /// 已获取的最大消息序号（用于增量拉取）
    @State private var lastSeq = 0
    /// 选中的工具项（用于 sheet 展示详情）
    @State private var selectedTool: ClaudeChatItem?
    /// 是否显示 / 命令菜单
    @State private var showSlashMenu = false
    /// 是否显示 @ 文件选择器
    @State private var showFilePicker = false
    @State private var fileList: [FileEntry] = []
    /// @ 提及过滤查询（@后输入的字符）
    @State private var mentionQuery = ""
    /// @ 提及当前路径前缀（支持路径遍历）
    @State private var mentionBasePath = ""
    /// 最近使用的 / 命令（持久化）
    @AppStorage("recentSlashCommands") private var recentCommandsData = ""
    /// 是否有图片在粘贴板
    @State private var hasPastedImage = false
    /// Token 用量统计
    @State private var tokenUsage: [String: Int] = [:]

    private var chatMessages: [ClaudeChatItem] {
        messageStore.claudeChats[surfaceID] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            chatArea
            offlineQueueBanner
            if showSlashMenu { slashCommandMenu }
            if showFilePicker { filePickerView }
            inputBar
        }
        .background(CMColors.backgroundPrimary)
        .sheet(item: $selectedTool) { tool in
            if case .tool(name: let name) = tool.role {
                NavigationStack {
                    ToolDetailView(
                        toolName: name,
                        input: tool.content,
                        result: tool.toolResult,
                        state: tool.toolState
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                selectedTool = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            // 保留已有消息避免闪烁，仅首次加载时重置序号
            if chatMessages.isEmpty {
                lastSeq = 0
            }
            fetchMessages()
            // 订阅 Mac 端推送（文件监听），保留低频轮询作为降级
            startWatching()
            startPolling()
        }
        .onDisappear {
            stopPolling()
            stopWatching()
        }
        .onChange(of: inputText) { _, newValue in handleInputChange(newValue) }
        .onChange(of: speechRecognizer.isRecording) { _, recording in
            // 录音停止时，将转写文本追加到输入框
            if !recording {
                let text = speechRecognizer.transcript
                if !text.isEmpty {
                    inputText += text
                    isInputFocused = true
                }
            }
        }
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
            // Token 用量
            if !tokenUsage.isEmpty {
                TokenUsageView(
                    inputTokens: tokenUsage["input"] ?? 0,
                    outputTokens: tokenUsage["output"] ?? 0,
                    cacheTokens: tokenUsage["cache"] ?? 0,
                    compact: true
                )
                .padding(.horizontal, 20)
                .padding(.top, 4)
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
                    .background(CMColors.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                claudeAvatar
                markdownText(msg.content)
                Spacer(minLength: 20)
            }
        case .tool(name: let name):
            Button {
                selectedTool = msg
            } label: {
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

    /// Markdown 渲染（支持 # 标题、代码块、表格、列表等块级元素）
    private func markdownText(_ content: String) -> some View {
        MarkdownView(content: content)
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

    /// 命令分类定义
    private struct SlashCommand {
        let cmd: String
        let desc: String
        let category: String
        let shortcut: String?

        init(_ cmd: String, _ desc: String, _ category: String, shortcut: String? = nil) {
            self.cmd = cmd; self.desc = desc; self.category = category; self.shortcut = shortcut
        }
    }

    private let slashCommands: [SlashCommand] = [
        // 常用
        SlashCommand("/compact", "压缩上下文", "常用", shortcut: "⌘⇧C"),
        SlashCommand("/status", "查看状态", "常用"),
        SlashCommand("/clear", "清空对话", "常用"),
        SlashCommand("/help", "帮助", "常用"),
        SlashCommand("/cost", "费用统计", "常用"),
        // 项目
        SlashCommand("/init", "初始化项目", "项目"),
        SlashCommand("/review", "代码审查", "项目"),
        SlashCommand("/bug", "报告/调试 Bug", "项目"),
        SlashCommand("/terminal-setup", "终端环境配置", "项目"),
        // 配置
        SlashCommand("/config", "配置", "配置"),
        SlashCommand("/permissions", "权限管理", "配置"),
        SlashCommand("/memory", "记忆管理", "配置"),
        SlashCommand("/allowed-tools", "管理允许的工具", "配置"),
        // 工具
        SlashCommand("/mcp", "MCP 服务", "工具"),
        SlashCommand("/model", "切换模型", "工具"),
        SlashCommand("/vim", "Vim 模式", "工具"),
        SlashCommand("/doctor", "诊断", "工具"),
        SlashCommand("/listen", "监听模式", "工具"),
        SlashCommand("/install-github-app", "安装 GitHub App", "工具"),
    ]

    /// 最近使用的命令列表
    private var recentCommands: [String] {
        recentCommandsData.isEmpty ? [] : recentCommandsData.components(separatedBy: ",")
    }

    /// 记录最近使用的命令
    private func trackRecentCommand(_ cmd: String) {
        var recents = recentCommands.filter { $0 != cmd }
        recents.insert(cmd, at: 0)
        let trimmed = Array(recents.prefix(5))
        recentCommandsData = trimmed.joined(separator: ",")
    }

    private var slashCommandMenu: some View {
        let query = String(inputText.dropFirst()).lowercased()
        let filtered = query.isEmpty ? slashCommands : slashCommands.filter { $0.cmd.contains(query) }

        // 按分类分组
        let categories = ["常用", "项目", "配置", "工具"]
        let grouped = Dictionary(grouping: filtered) { $0.category }

        // 最近使用的命令（仅在无搜索时显示）
        let recentItems: [SlashCommand] = query.isEmpty
            ? recentCommands.compactMap { cmd in slashCommands.first { $0.cmd == cmd } }
            : []

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 最近使用
                if !recentItems.isEmpty {
                    sectionHeader("最近使用")
                    ForEach(recentItems, id: \.cmd) { item in
                        slashCommandRow(item)
                    }
                }

                // 分类列表
                ForEach(categories, id: \.self) { category in
                    if let items = grouped[category], !items.isEmpty {
                        sectionHeader(category)
                        ForEach(items, id: \.cmd) { item in
                            slashCommandRow(item)
                        }
                    }
                }
            }
        }.frame(maxHeight: 260).background(CMColors.menuBackground)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.25))
            .textCase(.uppercase)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }

    private func slashCommandRow(_ item: SlashCommand) -> some View {
        Button {
            inputText = item.cmd
            showSlashMenu = false
            isInputFocused = true
            trackRecentCommand(item.cmd)
        } label: {
            HStack {
                Text(item.cmd)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)
                Spacer()
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .padding(.trailing, 4)
                }
                Text(item.desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    // MARK: - @ 文件选择器

    struct FileEntry: Equatable { let name: String; let isDirectory: Bool }

    /// 根据 mentionQuery 模糊过滤的文件列表
    private var filteredFileList: [FileEntry] {
        guard !mentionQuery.isEmpty else { return fileList }
        let query = mentionQuery.lowercased()
        return fileList.filter { fuzzyMatch(query: query, target: $0.name.lowercased()) }
    }

    /// 简单模糊匹配：查询字符按顺序出现在目标中
    private func fuzzyMatch(query: String, target: String) -> Bool {
        var targetIdx = target.startIndex
        for ch in query {
            guard let found = target[targetIdx...].firstIndex(of: ch) else { return false }
            targetIdx = target.index(after: found)
        }
        return true
    }

    private var filePickerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(.blue)
                if mentionBasePath.isEmpty {
                    Text("选择文件").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                } else {
                    Text(mentionBasePath)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.blue.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                if !mentionQuery.isEmpty {
                    Text("\(filteredFileList.count) 个结果")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.2))
                }
                Button { dismissMentionPicker() } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }
            }.padding(.horizontal, 16).padding(.vertical, 8)

            if fileList.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.6).tint(.blue)
                    Text("加载…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.3))
                }.padding(.horizontal, 16).padding(.vertical, 12)
            } else if filteredFileList.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.2))
                    Text("无匹配文件").font(.system(size: 12)).foregroundStyle(.white.opacity(0.3))
                }.padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredFileList, id: \.name) { file in
                            Button {
                                if file.isDirectory {
                                    // 路径遍历：进入子目录
                                    navigateToSubdirectory(file.name)
                                } else {
                                    selectFile(file)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.text")
                                        .font(.system(size: 12)).foregroundStyle(file.isDirectory ? .yellow : .blue).frame(width: 16)
                                    Text(file.name).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                                    Spacer()
                                    if file.isDirectory {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white.opacity(0.2))
                                    }
                                }.padding(.horizontal, 16).padding(.vertical, 8)
                            }
                        }
                    }
                }.frame(maxHeight: 200)
            }
        }.background(CMColors.menuBackground)
    }

    /// 进入子目录
    private func navigateToSubdirectory(_ dirName: String) {
        let newBase = mentionBasePath.isEmpty ? dirName + "/" : mentionBasePath + dirName + "/"
        mentionBasePath = newBase
        mentionQuery = ""
        // 更新输入框中的 @ 引用
        updateMentionInInput(newBase)
        loadFileList(subpath: newBase)
    }

    /// 选中文件，插入到输入框
    private func selectFile(_ file: FileEntry) {
        let fullPath = mentionBasePath + file.name
        // 替换输入框中 @ 开始的部分
        let textBeforeAt = extractTextBeforeLastAt(inputText)
        inputText = textBeforeAt + "@" + fullPath + " "
        dismissMentionPicker()
        isInputFocused = true
    }

    /// 关闭提及选择器并重置状态
    private func dismissMentionPicker() {
        showFilePicker = false
        mentionQuery = ""
        mentionBasePath = ""
    }

    /// 更新输入框中 @ 后的文本
    private func updateMentionInInput(_ path: String) {
        let textBeforeAt = extractTextBeforeLastAt(inputText)
        inputText = textBeforeAt + "@" + path
    }

    /// 提取输入框中最后一个 @ 之前的文本
    private func extractTextBeforeLastAt(_ text: String) -> String {
        guard let atRange = text.range(of: "@", options: .backwards) else { return text }
        return String(text[text.startIndex..<atRange.lowerBound])
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(CMColors.separator)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("@", color: .blue) {
                        inputText += "@"; isInputFocused = true; loadFileList(); showFilePicker = true; showSlashMenu = false
                    }
                    chip("/", color: .orange) { inputText = "/"; showSlashMenu = true; showFilePicker = false; isInputFocused = true }
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 16)
                    chip("^C", color: .red) { sendKey("c", "ctrl") }
                    chip("Esc", color: .gray) { sendKey("escape", "") }
                    chip("/compact", color: .purple) { sendDirect("/compact\n"); trackRecentCommand("/compact") }
                    chip("/status", color: .green) { sendDirect("/status\n"); trackRecentCommand("/status") }
                }.padding(.horizontal, 12).padding(.vertical, 6)
            }
            // 粘贴板图片提示
            if hasPastedImage {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 11)).foregroundStyle(.blue)
                    Text("粘贴板包含图片").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Button {
                        hasPastedImage = false
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(Color.blue.opacity(0.06))
            }
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    TextField("", text: $inputText, prompt: Text("消息...").foregroundStyle(.gray.opacity(0.6)), axis: .vertical)
                        .font(.system(size: 15)).foregroundStyle(.white)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .lineLimit(1...8).focused($isInputFocused)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .onSubmit { send() }
                    // 字符计数（超过 500 字符时显示）
                    if inputText.count > 500 {
                        Text("\(inputText.count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(inputText.count > 10000 ? .red.opacity(0.6) : .white.opacity(0.2))
                            .padding(.trailing, 10).padding(.bottom, 6)
                    }
                }
                VoiceInputButton(isRecording: speechRecognizer.isRecording) {
                    handleVoiceTap()
                }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                        .foregroundStyle(inputText.isEmpty ? .gray.opacity(0.3) : .purple)
                }.disabled(inputText.isEmpty)
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
        .background(CMColors.inputBarBackground)
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            hasPastedImage = UIPasteboard.general.hasImages
        }
        .onAppear {
            hasPastedImage = UIPasteboard.general.hasImages
        }
    }

    private func chip(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 8)
                .background(color.opacity(0.1)).foregroundStyle(color.opacity(0.7)).clipShape(Capsule())
        }
    }

    // MARK: - 离线队列提示

    @ViewBuilder
    private var offlineQueueBanner: some View {
        let count = relayConnection.offlineQueue.pendingCount
        if count > 0 {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                Text("\(count) 条消息待发送")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.08))
        }
    }

    private func handleInputChange(_ text: String) {
        showSlashMenu = text.hasPrefix("/") && !text.contains(" ")

        // @ 提及检测与实时过滤
        if let atRange = text.range(of: "@", options: .backwards) {
            let afterAt = String(text[atRange.upperBound...])
            // 如果 @ 后没有空格，视为正在输入提及
            if !afterAt.contains(" ") {
                if !showFilePicker {
                    // 首次触发 @，加载文件列表
                    mentionBasePath = ""
                    mentionQuery = ""
                    loadFileList()
                    showFilePicker = true
                    showSlashMenu = false
                }
                // 检查是否有路径遍历（包含 /）
                if afterAt.contains("/") {
                    let components = afterAt.components(separatedBy: "/")
                    let dirPath = components.dropLast().joined(separator: "/") + "/"
                    let query = components.last ?? ""
                    // 路径变化时重新加载子目录
                    if dirPath != mentionBasePath {
                        mentionBasePath = dirPath
                        mentionQuery = query
                        loadFileList(subpath: dirPath)
                    } else {
                        mentionQuery = query
                    }
                } else {
                    mentionQuery = afterAt
                }
            } else {
                // @ 后有空格，关闭选择器
                if showFilePicker { dismissMentionPicker() }
            }
        } else {
            // 没有 @，关闭选择器
            if showFilePicker { dismissMentionPicker() }
        }

        // 检测退格键删除 @ 时关闭选择器
        if showFilePicker && !text.contains("@") {
            dismissMentionPicker()
        }
    }

    private func loadFileList(subpath: String = "") {
        let basePath = sessionInfo.project.isEmpty ? "~" : sessionInfo.project
        let fullPath = subpath.isEmpty ? basePath : basePath + "/" + subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        relayConnection.sendWithResponse(["method": "file.list", "params": ["path": fullPath]]) { result in
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

    // MARK: - 语音输入

    private func handleVoiceTap() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        } else {
            Task {
                let granted = await speechRecognizer.requestPermissions()
                guard granted else { return }
                do {
                    try speechRecognizer.startRecording()
                } catch {
                    // 语音识别启动失败，静默处理
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

            // 提取 token 用量
            if let usage = resultDict["usage"] as? [String: Int] {
                tokenUsage = usage
            }

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
                // 用户消息：只显示纯文本，跳过 tool_result
                let textBlocks = blocks.filter { ($0["type"] as? String) == "text" }
                let hasToolResult = blocks.contains { ($0["type"] as? String) == "tool_result" }
                // 纯 tool_result 消息不显示为用户消息
                if hasToolResult && textBlocks.isEmpty { continue }

                if !textBlocks.isEmpty {
                    let text = textBlocks.compactMap { $0["text"] as? String }.joined()
                    if !text.isEmpty {
                        // 去重：匹配 ID 或内容（本地发送的 ID 与 JSONL 的 ID 不同）
                        let exists = chatMessages.contains { $0.id == uuid || ($0.role == .user && $0.content == text) }
                            || newItems.contains { $0.role == .user && $0.content == text }
                        if !exists {
                            newItems.append(ClaudeChatItem(id: uuid, role: .user, content: text, timestamp: Date()))
                        }
                    }
                }
            } else if type == "assistant" {
                // 跳过中间状态消息（stop_reason 为 null 表示 Claude 还在生成）
                if stopReason == nil { continue }
                for block in blocks {
                    let blockType = block["type"] as? String ?? ""
                    switch blockType {
                    case "text":
                        if let text = block["text"] as? String, !text.isEmpty {
                            let msgID = "\(uuid)-text"
                            // UUID-based 去重
                            let exists = chatMessages.contains { $0.id == msgID }
                            if !exists {
                                newItems.append(ClaudeChatItem(
                                    id: msgID, role: .assistant,
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

        // 更新已有工具消息的状态和结果（不可变：创建新实例替换旧的）
        let existing = messageStore.claudeChats[surfaceID] ?? []
        var all: [ClaudeChatItem] = []
        var updated = false
        for item in existing {
            if let toolId = item.toolUseId, item.toolState == .running,
               let result = toolResults[toolId] {
                // 创建新实例替代就地修改
                let updatedItem = ClaudeChatItem(
                    id: item.id,
                    role: item.role,
                    content: item.content,
                    timestamp: item.timestamp,
                    toolResult: result.content,
                    toolState: result.isError ? .error : .completed,
                    toolUseId: item.toolUseId
                )
                all.append(updatedItem)
                updated = true
            } else {
                all.append(item)
            }
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

    // MARK: - Mac 端推送监听（主要通道）

    /// 订阅 Mac 端 JSONL 文件监听推送
    private func startWatching() {
        // 发送 claude.watch 让 Mac 端开始监听文件变化
        relayConnection.send([
            "method": "claude.watch",
            "params": ["surface_id": surfaceID],
        ])

        // 监听推送事件
        let sid = surfaceID
        relayConnection.onClaudeUpdate = { payload in
            let payloadSid = payload["surface_id"] as? String ?? ""
            guard payloadSid == sid else { return }

            if let messages = payload["messages"] as? [[String: Any]] {
                let status = payload["status"] as? String ?? "idle"
                activityLabel = status
                isThinking = (status == "thinking" || status == "tool_running")

                // 提取 token 用量
                if let usage = payload["usage"] as? [String: Int] {
                    tokenUsage = usage
                }

                processJsonlMessages(messages)
            }
        }
    }

    private func stopWatching() {
        relayConnection.send([
            "method": "claude.unwatch",
            "params": ["surface_id": surfaceID],
        ])
        relayConnection.onClaudeUpdate = nil
    }

    // MARK: - 降级轮询（5秒兜底）

    private func startPolling() {
        stopPolling()
        refreshTask = Task {
            while !Task.isCancelled {
                // 推送通道存在时，轮询仅作为 5 秒兜底
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                fetchMessages()
            }
        }
    }

    private func stopPolling() { refreshTask?.cancel(); refreshTask = nil }
}
