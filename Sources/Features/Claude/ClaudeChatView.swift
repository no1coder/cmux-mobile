import SwiftUI
import UIKit

/// Claude Code 聊天模式 — 直接从 JSONL 会话文件读取结构化消息
/// 跟 happy 项目一样，不解析终端输出
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var relayConnection: RelayConnection
    @EnvironmentObject var approvalManager: ApprovalManager

    @StateObject private var composeViewModel = ComposeInputViewModel()
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
    @State private var fileList: [MentionFileEntry] = []
    /// @ 提及过滤查询（@后输入的字符）
    @State private var mentionQuery = ""
    /// @ 提及当前路径前缀（支持路径遍历）
    @State private var mentionBasePath = ""
    /// 是否有图片在粘贴板
    @State private var hasPastedImage = false
    /// Token 用量统计
    @State private var tokenUsage: [String: Int] = [:]
    /// Plan 模式缓存（避免每次重新遍历消息列表）
    @State private var isInPlanMode = false
    /// 显示模型选择器
    @State private var showModelPicker = false
    /// 模型切换成功反馈（非 nil 时显示 toast）
    @State private var modelSwitchFeedback: String?
    private var chatMessages: [ClaudeChatItem] {
        messageStore.claudeChats[surfaceID] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            if isInPlanMode { planModeBanner }
            chatArea
            offlineQueueBanner
            if showSlashMenu {
                SlashCommandMenu(
                    inputText: $inputText,
                    showSlashMenu: $showSlashMenu,
                    onSelect: { isInputFocused = true },
                    onInteractiveCommand: { cmd in
                        switch cmd {
                        case .model:
                            // 先收起键盘，避免 confirmationDialog 被键盘遮挡
                            isInputFocused = false
                            // 延迟一帧等键盘开始收起后再弹出 dialog
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showModelPicker = true
                            }
                        }
                    }
                )
            }
            if showFilePicker {
                FileMentionPicker(
                    inputText: $inputText,
                    showFilePicker: $showFilePicker,
                    fileList: $fileList,
                    mentionQuery: $mentionQuery,
                    mentionBasePath: $mentionBasePath,
                    projectPath: sessionInfo.project
                )
            }
            ChatInputBar(
                inputText: $inputText,
                isInputFocused: $isInputFocused,
                hasPastedImage: hasPastedImage,
                onSend: send,
                onDismissPasteImage: { hasPastedImage = false },
                onAtTap: {
                    inputText += "@"; isInputFocused = true
                    loadFileList(); showFilePicker = true; showSlashMenu = false
                },
                onSlashTap: {
                    inputText = "/"; showSlashMenu = true; showFilePicker = false; isInputFocused = true
                },
                onCtrlC: { sendKey("c", "ctrl") },
                onEsc: { sendKey("escape", "") },
                onCompact: { sendDirect("/compact\n") },
                onStatus: { sendDirect("/status\n") },
                onPlan: { sendDirect("/plan\n") },
                isInPlanMode: isInPlanMode,
                composeViewModel: composeViewModel,
                onSendComposed: { message in
                    sendComposedMessage(message)
                }
            )
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
        .overlay(alignment: .top) {
            // 模型切换成功提示
            if let feedback = modelSwitchFeedback {
                HStack(spacing: 6) {
                    Image(systemName: feedback.hasPrefix("⚠️") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(feedback.hasPrefix("⚠️") ? .orange : .green)
                    Text(feedback)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            String(localized: "model.picker.title", defaultValue: "切换模型"),
            isPresented: $showModelPicker,
            titleVisibility: .visible
        ) {
            // 发送 /model 命令后，用数字键选择模型（Claude Code 的交互方式）
            Button("Default (推荐)") { selectModel(key: "default", name: "Default") }
            Button("Sonnet 4.6") { selectModel(key: "sonnet", name: "Sonnet") }
            Button("Haiku 4.5") { selectModel(key: "haiku", name: "Haiku") }
            Button("Opus 4.6 (1M context)") { selectModel(key: "opus", name: "Opus") }
            Button(String(localized: "model.picker.cancel", defaultValue: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "model.picker.desc", defaultValue: "切换后应用于当前及未来的 Claude Code 会话"))
        }
        .onAppear {
            // 保留已有消息避免闪烁，仅首次加载时重置序号
            if chatMessages.isEmpty {
                lastSeq = 0
            }
            hasPastedImage = UIPasteboard.general.hasImages
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
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            hasPastedImage = UIPasteboard.general.hasImages
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
                            .foregroundStyle(CMColors.textTertiary)
                            .padding(.top, 20)
                    }
                    ForEach(chatMessages) { msg in
                        ChatMessageRow(msg: msg) { tool in
                            selectedTool = tool
                        }.id(msg.id)
                    }
                    // 内嵌审批请求（当前 surface 的待处理请求）
                    ForEach(pendingApprovalsForSurface) { request in
                        InlineApprovalView(
                            request: request,
                            onApprove: { handleInlineApprove(request) },
                            onReject: { handleInlineReject(request) }
                        )
                        .id("approval-\(request.requestID)")
                    }

                    if isThinking {
                        thinkingView.id("thinking")
                    }
                    Color.clear.frame(height: 4).id("end")
                }.padding(.horizontal, 14)
            }
            .onTapGesture {
                // 点击聊天区域收起键盘
                isInputFocused = false
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
                        Text(sessionInfo.context).font(.system(size: 11)).foregroundStyle(CMColors.textTertiary)
                    }
                }
            }
            if !sessionInfo.project.isEmpty {
                Text(sessionInfo.project).font(.system(size: 11, design: .monospaced)).foregroundStyle(CMColors.textTertiary)
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

    /// Plan 模式横幅
    private var planModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 13))
            Text(String(localized: "claude.plan_mode", defaultValue: "Plan 模式 — Claude 正在规划而非执行"))
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button {
                sendDirect("/plan\n")
            } label: {
                Text(String(localized: "claude.exit_plan", defaultValue: "退出 Plan"))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.systemFill))
                    .clipShape(Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.7))
    }

    private var thinkingView: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.15)).frame(width: 26, height: 26)
                Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.purple)
            }
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6).tint(.purple.opacity(0.6))
                Text(statusLabel)
                    .font(.system(size: 12)).foregroundStyle(CMColors.textTertiary).italic()
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

    /// 委托给 FileMentionPicker 加载文件列表
    private func loadFileList(subpath: String = "") {
        let basePath = sessionInfo.project.isEmpty ? "~" : sessionInfo.project
        let fullPath = subpath.isEmpty ? basePath : basePath + "/" + subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        relayConnection.sendWithResponse(["method": "file.list", "params": ["path": fullPath]]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let entries = resultDict["entries"] as? [[String: Any]] {
                fileList = entries.compactMap {
                    guard let name = $0["name"] as? String else { return nil }
                    return MentionFileEntry(name: name, isDirectory: ($0["type"] as? String) == "directory")
                }.sorted { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
        }
    }

    private func dismissMentionPicker() {
        showFilePicker = false
        mentionQuery = ""
        mentionBasePath = ""
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

    /// 发送混合消息（文字 + 图片）到终端
    private func sendComposedMessage(_ message: ComposedMessage) {
        let correctedMessage = ComposedMessage(
            blocks: message.blocks,
            targetSurfaceID: surfaceID
        )
        guard !correctedMessage.isEmpty else { return }

        // 本地显示用户消息（仅显示文字部分 + 图片数量提示）
        let textParts = correctedMessage.effectiveBlocks.compactMap { $0.textContent }
        let imageCount = correctedMessage.imageCount
        var displayText = textParts.joined(separator: "\n")
        if imageCount > 0 {
            let imageLabel = String(localized: "chat.composed.imageCount",
                                    defaultValue: "[\(imageCount) 张图片]")
            displayText = displayText.isEmpty ? imageLabel : displayText + "\n" + imageLabel
        }
        appendMessage(ClaudeChatItem(id: UUID().uuidString, role: .user, content: displayText, timestamp: Date()))

        // 通过 composed_msg 协议发送
        let sender = ComposedMessageSender(relayConnection: relayConnection)
        sender.send(correctedMessage)
        isThinking = true
    }

    // MARK: - 内嵌审批

    /// 当前 surface 的待处理审批请求
    private var pendingApprovalsForSurface: [ApprovalRequest] {
        approvalManager.pendingRequests.filter { $0.surfaceID == surfaceID }
    }

    private func handleInlineApprove(_ request: ApprovalRequest) {
        let payload = approvalManager.buildApprovePayload(requestID: request.requestID)
        relayConnection.send(payload)
        approvalManager.markResolved(requestID: request.requestID, resolution: .approved)
    }

    private func handleInlineReject(_ request: ApprovalRequest) {
        let payload = approvalManager.buildRejectPayload(requestID: request.requestID)
        relayConnection.send(payload)
        approvalManager.markResolved(requestID: request.requestID, resolution: .rejected)
    }

    /// 通过 Mac 端 RPC 切换模型（Ctrl+C → --resume + --model 重启）
    private func selectModel(key: String, name: String) {
        // 立即显示"切换中"反馈
        withAnimation { modelSwitchFeedback = "正在切换到 \(name)..." }

        relayConnection.sendWithResponse([
            "method": "claude.switch_model",
            "params": ["surface_id": surfaceID, "model": key],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if resultDict["switching"] as? Bool == true {
                // 异步切换已开始，等待 claude.model_switched 事件
                // 反馈已在上面显示，事件到达时会更新
                return
            }
            // 旧版 Mac 端或错误响应
            if resultDict["ok"] as? Bool == true {
                withAnimation { modelSwitchFeedback = "已切换到 \(name)" }
            } else {
                let error = resultDict["error"] as? String ?? "切换失败"
                withAnimation { modelSwitchFeedback = "⚠️ \(error)" }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { modelSwitchFeedback = nil }
            }
        }
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

        // HIGH 修复：预构建去重集合，O(1) 查找替代 O(n) contains
        let existingIDs = Set(chatMessages.map { $0.id })
        let existingUserTexts = Set(chatMessages.filter { $0.role == .user }.map { $0.content })
        let existingToolIds = Set(chatMessages.compactMap { $0.toolUseId })

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

        // 用于跟踪本批次内的新用户消息文本（防止批次内重复）
        var newUserTexts = Set<String>()

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
                        // 过滤系统注入的 user 消息（skill 展开、任务通知等）
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("Base directory for this skill:")
                            || trimmed.hasPrefix("<task-notification>")
                            || trimmed.hasPrefix("<command-name>")
                            || trimmed.hasPrefix("<local-command-caveat>")
                            || trimmed.hasPrefix("<local-command-stdout>")
                            || trimmed.hasPrefix("<local-command-stderr>")
                            || trimmed.hasPrefix("<system-reminder>") {
                            continue
                        }
                        // O(1) 去重：匹配 ID 或内容
                        let exists = existingIDs.contains(uuid)
                            || existingUserTexts.contains(text)
                            || newUserTexts.contains(text)
                        if !exists {
                            newItems.append(ClaudeChatItem(id: uuid, role: .user, content: text, timestamp: Date()))
                            newUserTexts.insert(text)
                        }
                    }
                }
            } else if type == "assistant" {
                // 跳过中间状态消息（stop_reason 为 null 表示 Claude 还在生成）
                if stopReason == nil { continue }

                // 提取模型名（用于标注每条消息）
                let rawModel = (msg["message"] as? [String: Any])?["model"] as? String
                    ?? msg["model"] as? String
                let displayModel = formatModelName(rawModel)

                for block in blocks {
                    let blockType = block["type"] as? String ?? ""
                    switch blockType {
                    case "text":
                        if let text = block["text"] as? String, !text.isEmpty {
                            let msgID = "\(uuid)-text"
                            // O(1) UUID-based 去重
                            if !existingIDs.contains(msgID) {
                                newItems.append(ClaudeChatItem(
                                    id: msgID, role: .assistant,
                                    content: text, timestamp: Date(),
                                    modelName: displayModel
                                ))
                            }
                        }
                    case "thinking":
                        // 思考过程（extended thinking）
                        if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                            let thinkingID = "\(uuid)-thinking"
                            if !existingIDs.contains(thinkingID) {
                                newItems.append(ClaudeChatItem(
                                    id: thinkingID, role: .thinking,
                                    content: thinking, timestamp: Date()
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

                        // O(1) 去重
                        if !existingToolIds.contains(toolUseId) {
                            newItems.append(ClaudeChatItem(
                                id: "\(uuid)-tool-\(toolUseId.prefix(8))",
                                role: .tool(name: toolName),
                                content: summary,
                                timestamp: Date(),
                                toolResult: result?.content,
                                toolState: toolState,
                                toolUseId: toolUseId,
                                completedAt: result != nil ? Date() : nil
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
                    toolUseId: item.toolUseId,
                    completedAt: Date()
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

            // HIGH 修复：更新 Plan 模式缓存（避免每次渲染遍历全部消息）
            updatePlanModeState(all)
        }
    }

    /// 将原始模型 ID 格式化为可读名称
    private func formatModelName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.contains("opus") { return "Opus" }
        if raw.contains("sonnet") { return "Sonnet" }
        if raw.contains("haiku") { return "Haiku" }
        // 其他模型保留原始名（截取最后部分）
        if let last = raw.split(separator: "/").last {
            return String(last)
        }
        return raw
    }

    /// 根据最新消息列表更新 Plan 模式状态
    /// 根据最后一个 Plan 相关工具消息确定 Plan 模式状态
    /// 只有明确找到 EnterPlanMode/ExitPlanMode 时才更新，避免无关消息误重置
    private func updatePlanModeState(_ messages: [ClaudeChatItem]) {
        for msg in messages.reversed() {
            if case .tool(name: let name) = msg.role {
                if name == "ExitPlanMode" { isInPlanMode = false; return }
                if name == "EnterPlanMode" { isInPlanMode = true; return }
            }
        }
        // 没找到任何 Plan 工具消息时不修改状态（保持当前值）
    }

    /// 格式化工具输入为简要描述
    private func formatToolInput(name: String, input: [String: Any]) -> String {
        switch name {
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Write":
            return input["file_path"] as? String ?? ""
        case "Edit":
            return input["file_path"] as? String ?? ""
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
        relayConnection.onClaudeUpdate = { [weak relayConnection] payload in
            // 模型切换事件（不含 surface_id 过滤，因为是全局事件）
            if let event = payload["event"] as? String {
                switch event {
                case "claude.model_switching":
                    let model = payload["model"] as? String ?? ""
                    withAnimation { modelSwitchFeedback = "正在切换到 \(model)..." }
                    return
                case "claude.model_switched":
                    let model = payload["model"] as? String ?? ""
                    let ok = payload["ok"] as? Bool ?? false
                    if ok {
                        withAnimation { modelSwitchFeedback = "已切换到 \(model)" }
                    } else {
                        let error = payload["error"] as? String ?? "切换失败"
                        withAnimation { modelSwitchFeedback = "⚠️ \(error)" }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { modelSwitchFeedback = nil }
                    }
                    return
                default:
                    break
                }
            }

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

    // MARK: - 降级轮询（15秒兜底）

    private func startPolling() {
        stopPolling()
        refreshTask = Task {
            while !Task.isCancelled {
                // HIGH 修复：推送通道存在时，轮询间隔从 5 秒提升到 15 秒
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                fetchMessages()
            }
        }
    }

    private func stopPolling() { refreshTask?.cancel(); refreshTask = nil }
}
