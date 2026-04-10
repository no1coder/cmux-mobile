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
    /// 流式预览：Claude 生成过程中从终端屏幕读取的实时输出
    @State private var streamingPreview = ""
    /// 流式预览轮询任务
    @State private var streamingTask: Task<Void, Never>?
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
    /// 每页消息数量
    private static let pageSize = 200
    /// 当前显示消息上限（向上滚动时递增）
    @State private var displayLimit = 200
    /// 展开的 Turn ID 集合
    @State private var expandedTurnIds: Set<String> = []
    // MARK: - 发送状态

    private enum SendStage: Equatable {
        case sending
        case delivered
        case thinking
        case failed(String)
    }

    private struct PendingSend: Equatable {
        let id: String
        var stage: SendStage
    }
    @State private var pendingSend: PendingSend?
    @State private var lastSendText = ""

    /// 是否还有更早的消息可加载
    private var hasMoreMessages: Bool {
        let all = messageStore.claudeChats[surfaceID] ?? []
        return all.count > displayLimit
    }

    private var chatMessages: [ClaudeChatItem] {
        let all = messageStore.claudeChats[surfaceID] ?? []
        if all.count > displayLimit {
            return Array(all.suffix(displayLimit))
        }
        return all
    }

    /// 将平铺消息分组为对话轮次
    private var chatTurns: [ConversationTurn] {
        ConversationTurn.group(chatMessages)
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
                    },
                    dynamicCommands: messageStore.slashCommands
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
            stopStreamingPreview()
        }
        .onChange(of: isThinking) { _, thinking in
            if thinking {
                startStreamingPreview()
            } else {
                stopStreamingPreview()
            }
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
                    // 滚动到顶部时自动加载更早的消息
                    if hasMoreMessages {
                        Button {
                            loadMoreMessages(proxy: proxy)
                        } label: {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(String(localized: "chat.load_more", defaultValue: "加载更早的消息"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(CMColors.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .onAppear {
                            // 滚到顶部自动触发加载
                            loadMoreMessages(proxy: proxy)
                        }
                    }
                    if chatMessages.isEmpty && !isThinking {
                        Text("向 Claude 发送消息开始对话")
                            .font(.system(size: 13))
                            .foregroundStyle(CMColors.textTertiary)
                            .padding(.top, 20)
                    }
                    ForEach(chatTurns) { turn in
                        TurnView(
                            turn: turn,
                            isExpanded: expandedTurnIds.contains(turn.id),
                            onToggle: { toggleTurn(turn.id) },
                            onToolTap: { tool in selectedTool = tool }
                        )
                        .id(turn.id)
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
                        streamingPreviewView.id("thinking")
                    }
                    sendStatusFooter.id("send-status")
                    Color.clear.frame(height: 4).id("end")
                }.padding(.horizontal, 14)
            }
            .onTapGesture {
                // 点击聊天区域收起键盘
                isInputFocused = false
            }
            .onAppear {
                // 进入页面时：已有消息则立即滚动到底部
                if !chatMessages.isEmpty {
                    // 延迟一帧等 LazyVStack 完成布局
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatMessages.count) { oldCount, newCount in
                if oldCount == 0 && newCount > 0 {
                    // 首次加载消息，无动画直接跳到底部
                    autoExpandLastTurn()
                    proxy.scrollTo("end", anchor: .bottom)
                } else if newCount > oldCount {
                    // 新增消息，平滑滚动到底部
                    autoExpandLastTurn()
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamingPreview) { _, _ in
                // 流式预览内容更新时保持在底部
                proxy.scrollTo("end", anchor: .bottom)
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

    /// 流式预览视图：显示 Claude 正在生成的内容（从终端屏幕读取）
    private var streamingPreviewView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !streamingPreview.isEmpty {
                // 显示实时内容
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        Circle().fill(Color.purple.opacity(0.15)).frame(width: 26, height: 26)
                        Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.purple)
                    }
                    Text(streamingPreview)
                        .font(.system(size: 14))
                        .foregroundStyle(CMColors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 底部状态指示
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5).tint(.purple.opacity(0.6))
                    Text(statusLabel)
                        .font(.system(size: 11)).foregroundStyle(CMColors.textTertiary).italic()
                }.padding(.leading, 34)
            } else {
                // 还没读到内容，显示加载状态
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
        }
    }

    /// 当前状态显示文本
    private var statusLabel: String {
        switch activityLabel {
        case "tool_running": return String(localized: "claude.status.tool_running", defaultValue: "执行工具中…")
        case "thinking": return String(localized: "claude.status.thinking", defaultValue: "思考中…")
        default: return String(localized: "claude.status.processing", defaultValue: "处理中…")
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
        Haptics.rigid()
        let messageId = UUID().uuidString
        inputText = ""; showSlashMenu = false; showFilePicker = false

        appendMessage(ClaudeChatItem(id: messageId, role: .user, content: text, timestamp: Date()))

        withAnimation { pendingSend = PendingSend(id: messageId, stage: .sending) }
        lastSendText = text

        relayConnection.sendWithResponse([
            "method": "surface.send_text",
            "params": ["surface_id": surfaceID, "text": text + "\n"],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if resultDict["error"] as? String != nil {
                withAnimation { pendingSend = PendingSend(id: messageId, stage: .failed("发送失败")) }
                return
            }
            withAnimation { pendingSend = PendingSend(id: messageId, stage: .delivered) }
            isThinking = true
        }
    }

    private func retrySend() {
        guard let pending = pendingSend, case .failed = pending.stage else { return }
        withAnimation { pendingSend = PendingSend(id: pending.id, stage: .sending) }
        relayConnection.sendWithResponse([
            "method": "surface.send_text",
            "params": ["surface_id": surfaceID, "text": lastSendText + "\n"],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if resultDict["error"] as? String != nil {
                withAnimation { pendingSend = PendingSend(id: pending.id, stage: .failed("发送失败")) }
                return
            }
            withAnimation { pendingSend = PendingSend(id: pending.id, stage: .delivered) }
            isThinking = true
        }
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
        Haptics.rigid()

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

        let composedMsgId = UUID().uuidString
        withAnimation { pendingSend = PendingSend(id: composedMsgId, stage: .sending) }
        lastSendText = displayText
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            if pendingSend?.id == composedMsgId, pendingSend?.stage == .sending {
                withAnimation { pendingSend = PendingSend(id: composedMsgId, stage: .delivered) }
            }
        }

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

    // MARK: - Turn 折叠管理

    private func toggleTurn(_ turnId: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedTurnIds.contains(turnId) {
                expandedTurnIds.remove(turnId)
            } else {
                expandedTurnIds.insert(turnId)
            }
        }
    }

    private func autoExpandLastTurn() {
        let turns = chatTurns
        guard let lastTurn = turns.last else { return }
        expandedTurnIds = [lastTurn.id]
    }

    // MARK: - 分页加载

    /// 加载更早的消息（向上滚动时触发）
    private func loadMoreMessages(proxy: ScrollViewProxy) {
        // 记住当前第一条消息的 ID，加载后保持滚动位置
        let firstVisibleId = chatMessages.first?.id
        displayLimit += Self.pageSize
        // 加载后保持在原位置（不跳到底部）
        if let id = firstVisibleId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
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
            if !isThinking && pendingSend != nil {
                withAnimation { pendingSend = nil }
            }
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
                            // 已有同 ID 消息 → 内容可能更新（流式追加），就地替换
                            if existingIDs.contains(msgID) {
                                updateOrAppendStreamingMessage(
                                    &newItems, existingIDs: existingIDs,
                                    id: msgID, role: .assistant,
                                    content: text, modelName: displayModel
                                )
                            } else {
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

        // 更新已有消息（工具状态更新）
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
            // 有新消息到达时清空流式预览（已被结构化消息替代）
            if !newItems.isEmpty { streamingPreview = "" }

            // HIGH 修复：更新 Plan 模式缓存（避免每次渲染遍历全部消息）
            updatePlanModeState(all)
        }
    }

    /// 流式消息：更新已有的同 ID 消息内容，或追加新消息
    private func updateOrAppendStreamingMessage(
        _ newItems: inout [ClaudeChatItem],
        existingIDs: Set<String>,
        id: String, role: ClaudeChatItem.Role,
        content: String, modelName: String?
    ) {
        // 检查已有消息中是否有同 ID 的流式消息
        if let existing = messageStore.claudeChats[surfaceID],
           let idx = existing.firstIndex(where: { $0.id == id }) {
            // 内容不变则跳过
            guard existing[idx].content != content else { return }
            // 替换为新内容（不可变：创建新实例）
            var msgs = existing
            msgs[idx] = ClaudeChatItem(
                id: id, role: role,
                content: content, timestamp: Date(),
                modelName: modelName
            )
            messageStore.claudeChats[surfaceID] = msgs
        } else if !existingIDs.contains(id) {
            newItems.append(ClaudeChatItem(
                id: id, role: role,
                content: content, timestamp: Date(),
                modelName: modelName
            ))
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
            _ = relayConnection  // 保持 weak 引用以避免循环引用
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
                case "claude.session.reset":
                    // Mac 端 JSONL 文件被截断/替换，重置状态并重新拉取
                    let payloadSid = payload["surface_id"] as? String ?? ""
                    guard payloadSid == sid else { return }
                    lastSeq = 0
                    displayLimit = Self.pageSize
                    tokenUsage = [:]
                    isThinking = false
                    activityLabel = ""
                    fetchMessages()
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

                // 更新发送状态
                if let pending = pendingSend,
                   pending.stage == .delivered || pending.stage == .sending {
                    let hasResponse = messages.contains { ($0["type"] as? String) == "assistant" }
                    if hasResponse || status == "thinking" || status == "tool_running" {
                        withAnimation { pendingSend = PendingSend(id: pending.id, stage: .thinking) }
                    }
                }
                if !isThinking && pendingSend != nil {
                    withAnimation { pendingSend = nil }
                }
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

    // MARK: - 流式预览（生成时轮询终端屏幕）

    /// Claude 生成期间，快速轮询 read_screen 获取实时输出
    private func startStreamingPreview() {
        stopStreamingPreview()
        streamingPreview = ""
        let sid = surfaceID
        streamingTask = Task {
            while !Task.isCancelled {
                // 1 秒间隔轮询终端屏幕
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }

                await withCheckedContinuation { continuation in
                    relayConnection.sendWithResponse([
                        "method": "read_screen",
                        "params": ["surface_id": sid],
                    ]) { result in
                        let resultDict = result["result"] as? [String: Any] ?? result
                        if let lines = resultDict["lines"] as? [String] {
                            let extracted = Self.extractClaudeOutput(from: lines)
                            if !extracted.isEmpty {
                                DispatchQueue.main.async {
                                    streamingPreview = extracted
                                }
                            }
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func stopStreamingPreview() {
        streamingTask?.cancel()
        streamingTask = nil
        // 不立即清空 streamingPreview，让 JSONL 消息到达后自然替换
    }

    /// 从终端屏幕行中提取 Claude 正在输出的文本内容
    /// 跳过 TUI 框架元素（状态栏、工具调用指示器等），提取纯文本
    private static func extractClaudeOutput(from lines: [String]) -> String {
        // Claude Code TUI 的屏幕布局：
        // - 顶部几行：状态栏、上下文信息
        // - 中间：对话内容（用户消息和 assistant 输出）
        // - 底部：输入框、快捷键提示
        //
        // 策略：从底部向上扫描，跳过空行和 TUI 装饰，提取最近的文本块
        var contentLines: [String] = []
        var foundContent = false

        // 从倒数第二行开始（最后一行通常是输入框/快捷键提示）
        let scanLines = Array(lines.dropLast(2).reversed())

        for line in scanLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 跳过空行
            if trimmed.isEmpty {
                if foundContent { break } // 连续文本块结束
                continue
            }

            // 跳过 TUI 装饰行（进度条、状态指示、分隔符等）
            if trimmed.hasPrefix("─") || trimmed.hasPrefix("━")
                || trimmed.hasPrefix("╭") || trimmed.hasPrefix("╰")
                || trimmed.hasPrefix("│") || trimmed.hasPrefix("┃")
                || trimmed.hasPrefix(">") // 输入提示符
                || trimmed.hasPrefix("⏵") // Claude Code 输入
                || trimmed.hasPrefix("●") || trimmed.hasPrefix("○") // 状态指示
            {
                if foundContent { break }
                continue
            }

            foundContent = true
            contentLines.append(trimmed)
        }

        // 反转回正序
        contentLines.reverse()

        // 限制预览长度（避免过长的屏幕内容）
        let joined = contentLines.joined(separator: "\n")
        if joined.count > 2000 {
            return String(joined.suffix(2000))
        }
        return joined
    }

    // MARK: - 发送状态指示

    @ViewBuilder
    private var sendStatusFooter: some View {
        if let pending = pendingSend {
            HStack(spacing: 6) {
                switch pending.stage {
                case .sending:
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text(String(localized: "chat.status.sending", defaultValue: "发送中..."))
                case .delivered:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(String(localized: "chat.status.delivered", defaultValue: "已送达"))
                case .thinking:
                    ThinkingDotsView()
                    Text(String(localized: "chat.status.thinking", defaultValue: "Claude 正在思考..."))
                case .failed(let error):
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                    Button(String(localized: "chat.status.retry", defaultValue: "重试")) {
                        retrySend()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(CMColors.textTertiary)
            .padding(.leading, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private struct ThinkingDotsView: View {
        @State private var phase = 0

        var body: some View {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.purple.opacity(i <= phase ? 1.0 : 0.3))
                        .frame(width: 4, height: 4)
                        .scaleEffect(i <= phase ? 1.2 : 0.8)
                }
            }
            .frame(width: 20, height: 12)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(0.35))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        phase = (phase + 1) % 4
                    }
                }
            }
        }
    }
}
