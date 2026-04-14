import SwiftUI
import UIKit

/// Claude Code 聊天模式 — 直接从 JSONL 会话文件读取结构化消息
/// 跟 happy 项目一样，不解析终端输出
struct ClaudeChatView: View {
    let surfaceID: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var relayConnection: RelayConnection
    @EnvironmentObject var approvalManager: ApprovalManager
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("showTokenUsage") var showTokenUsage = true
    @AppStorage("autoScrollToBottom") var autoScrollToBottom = true

    @StateObject var composeViewModel = ComposeInputViewModel()
    @StateObject var requestGate = LatestOnlyRequestGate()
    @State var inputText = ""
    @State var isThinking = false
    @State var activityLabel = ""
    @State var sessionInfo: (model: String, project: String, context: String) = ("", "", "")
    @State var refreshTask: Task<Void, Never>?
    /// 流式预览：Claude 生成过程中从终端屏幕读取的实时输出
    @State var streamingPreview = ""
    /// 流式预览轮询任务
    @State var streamingTask: Task<Void, Never>?
    /// 视图生命周期内派生的辅助任务（TUI 抓屏 / 模型切换 toast 自动隐藏 / 滚动修正）
    /// 存在 @StateObject 里，视图销毁时统一取消，避免 Task 泄漏 + 持有已释放的 @State
    @StateObject var viewTaskBag = ViewTaskBag()
    @FocusState var isInputFocused: Bool
    /// 已获取的最大消息序号（用于增量拉取）
    @State var lastSeq = 0
    /// 选中的工具项（用于 sheet 展示详情）
    @State var selectedTool: ClaudeChatItem?
    /// 是否显示 / 命令菜单
    @State var showSlashMenu = false
    /// 是否显示 @ 文件选择器
    @State var showFilePicker = false
    @State var fileList: [MentionFileEntry] = []
    @State var isLoadingFileMentions = false
    @State var mentionLoadError: String?
    /// @ 提及过滤查询（@后输入的字符）
    @State var mentionQuery = ""
    /// @ 提及当前路径前缀（支持路径遍历）
    @State var mentionBasePath = ""
    /// 是否有图片在粘贴板
    @State var hasPastedImage = false
    /// Token 用量统计
    @State var tokenUsage: [String: Int] = [:]
    /// Plan 模式缓存（避免每次重新遍历消息列表）
    @State var isInPlanMode = false
    /// 显示模型选择器
    @State var showModelPicker = false
    /// 模型切换成功反馈（非 nil 时显示 toast）
    @State var modelSwitchFeedback: String?
    @State var historyLoadState: HistoryLoadState = .idle
    @State var fullHistoryState: FullHistoryState = .idle
    @State var claudeUpdateObserverID: UUID?
    @State var activeHistoryFetchMode: HistoryFetchMode?
    @State var queuedHistoryFetchMode: HistoryFetchMode?
    @State var hasMoreRemoteHistory = false
    @State var nextBeforeSeq: Int?
    @State var pagingState = ClaudeHistoryPagingState()
    /// 每页消息数量
    static let pageSize = 200
    /// 发送消息后等待多久将 pending 状态从 .sending 迁移到 .delivered
    /// TODO: replace with server ACK callback from ComposedMessageSender
    static let kPendingDeliveryConfirmTimeout: TimeInterval = 1.0
    /// 当前显示消息上限（向上滚动时递增）
    @State var displayLimit = 200
    @State var isLoadingMoreMessages = false
    @State var canAutoLoadMore = false
    /// 加载更早消息期间临时抑制"自动滚到底部"（避免与 loadMoreMessages 的锚点竞争）
    @State var suppressAutoScroll = false
    /// 用户最近一次手动拖动聊天的时间：3 秒内的自动滚到底部会被抑制，
    /// 避免用户在上翻看历史时被新消息/流式预览强行拉回底部
    @State var lastUserScrollAt: Date = .distantPast
    // MARK: - 发送状态

    enum SendStage: Equatable {
        case sending
        case queued
        case delivered
        case thinking
        case failed(String)
    }

    struct PendingSend: Equatable {
        let id: String
        var stage: SendStage
    }

    struct PendingLocalEcho: Equatable {
        let localID: String
        let content: String
    }

    enum HistoryLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum FullHistoryState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum HistoryFetchMode: Equatable {
        case incremental
        case recentPage
        case pageBefore(Int)
        case fullRefreshLegacy

        var coreKind: ClaudeHistoryFetchKind {
            switch self {
            case .incremental:
                return .incremental
            case .recentPage:
                return .recentPage
            case .pageBefore(let beforeSeq):
                return .pageBefore(beforeSeq)
            case .fullRefreshLegacy:
                return .fullRefreshLegacy
            }
        }

        var requestGateKey: String {
            switch self {
            case .incremental:
                return "claude-history-incremental"
            case .recentPage, .pageBefore:
                return "claude-history-page"
            case .fullRefreshLegacy:
                return "claude-history-full"
            }
        }

        var priority: Int {
            switch self {
            case .incremental:
                return 0
            case .recentPage, .pageBefore:
                return 1
            case .fullRefreshLegacy:
                return 2
            }
        }

        var timeoutSeconds: Double {
            switch self {
            case .incremental:
                return 45
            case .recentPage:
                return 60
            case .pageBefore:
                return 90
            case .fullRefreshLegacy:
                return 150
            }
        }
    }
    @State var pendingSend: PendingSend?
    @State var lastSendText = ""
    @State var pendingLocalEchoes: [PendingLocalEcho] = []

    /// 是否还有更早的消息可加载
    private var hasMoreMessages: Bool {
        let all = messageStore.claudeChats[surfaceID] ?? []
        return all.count > displayLimit || hasMoreRemoteHistory
    }

    private var localHasMoreMessages: Bool {
        let all = messageStore.claudeChats[surfaceID] ?? []
        return all.count > displayLimit
    }

    var oldestLoadedSeq: Int? {
        (messageStore.claudeChats[surfaceID] ?? []).compactMap(\.seq).min()
    }

    var chatMessages: [ClaudeChatItem] {
        let raw = messageStore.claudeChats[surfaceID] ?? []
        // 历史消息以 Mac 端返回顺序为准；不要再按本地 timestamp 重排，
        // 否则全量历史 / 增量推送 / 流式替换交错时会把旧消息“洗牌”。
        if raw.count > displayLimit {
            return Array(raw.suffix(displayLimit))
        }
        return raw
    }

    private var shouldShowHistoryBackfillBanner: Bool {
        guard !(messageStore.claudeChats[surfaceID] ?? []).isEmpty else { return false }
        switch fullHistoryState {
        case .loading, .failed:
            return true
        case .idle, .loaded:
            return false
        }
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
                    isLoading: $isLoadingFileMentions,
                    errorMessage: $mentionLoadError,
                    mentionQuery: $mentionQuery,
                    mentionBasePath: $mentionBasePath,
                    rootPath: mentionRootPath
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
                    inputText += "/"; showSlashMenu = true; showFilePicker = false; isInputFocused = true
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
                        .foregroundStyle(CMColors.textPrimary)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground))
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
            let cachedMessages = messageStore.claudeChats[surfaceID] ?? []
            let cachedSeq = messageStore.claudeChatSequence(for: surfaceID)
            let normalizedCachedMessages = ClaudeChatItem.normalizeRunningTools(in: cachedMessages)

            if normalizedCachedMessages != cachedMessages {
                messageStore.setClaudeChat(surfaceID, messages: normalizedCachedMessages, totalSeq: cachedSeq > 0 ? cachedSeq : nil)
            }

            if cachedMessages.isEmpty {
                lastSeq = 0
                historyLoadState = .loading
                fullHistoryState = .loading
            } else {
                if cachedSeq > 0 {
                    lastSeq = cachedSeq
                }
                historyLoadState = .loaded
                fullHistoryState = .idle
                updatePlanModeState(cachedMessages)
                // bootstrapFromCache 由下方 if-else 分支按 hasCompleteCachedHistory/cachedHasSeqMetadata 精确调用
            }
            hasPastedImage = UIPasteboard.general.hasImages
            let hasCompleteCachedHistory = messageStore.hasCompleteClaudeChatHistory(for: surfaceID)
            if cachedMessages.isEmpty {
                requestHistoryFetch(mode: .recentPage)
            } else {
                requestHistoryFetch(mode: .incremental)
                let cachedHasSeqMetadata = cachedMessages.contains { $0.seq != nil }
                if hasCompleteCachedHistory {
                    pagingState.bootstrapFromCache(
                        hasCompleteHistory: true,
                        cachedHasSeqMetadata: cachedHasSeqMetadata,
                        oldestLoadedSeq: oldestLoadedSeq
                    )
                    fullHistoryState = .loaded
                    hasMoreRemoteHistory = pagingState.hasMoreRemoteHistory
                    nextBeforeSeq = pagingState.nextBeforeSeq
                } else if cachedHasSeqMetadata {
                    pagingState.bootstrapFromCache(
                        hasCompleteHistory: false,
                        cachedHasSeqMetadata: true,
                        oldestLoadedSeq: oldestLoadedSeq
                    )
                    hasMoreRemoteHistory = pagingState.hasMoreRemoteHistory
                    nextBeforeSeq = pagingState.nextBeforeSeq
                } else {
                    requestHistoryFetch(mode: .fullRefreshLegacy)
                }
            }
            // 订阅 Mac 端推送（文件监听），保留低频轮询作为降级
            startWatching()
            startPolling()
        }
        .onDisappear {
            stopPolling()
            stopWatching()
            stopStreamingPreview()
            viewTaskBag.cancelAll()
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
                    if hasMoreMessages {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                guard canAutoLoadMore else { return }
                                loadMoreMessages(proxy: proxy)
                            }
                    }
                    // 手动点击加载更早的消息
                    // 不再用 .onAppear 自动触发：按钮首屏就在顶部，初次进入会与"滚到底部"抢锚点，
                    // 导致用户看到视图被拉到中间的历史消息。改为用户主动点按。
                    if hasMoreMessages {
                        Button {
                            loadMoreMessages(proxy: proxy)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 12))
                                Text(String(localized: "chat.load_more", defaultValue: "加载更早的消息"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(CMColors.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                    }
                    if shouldShowHistoryBackfillBanner {
                        historyBackfillBanner
                    }
                    if chatMessages.isEmpty && !isThinking {
                        emptyChatState
                    }
                    ForEach(chatMessages) { msg in
                        ChatMessageRow(msg: msg, onToolTap: { tool in selectedTool = tool })
                            .id(msg.id)
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
            // 监听用户手动拖动：短期内抑制自动滚到底部，允许用户安心上翻阅读历史
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { _ in
                        lastUserScrollAt = Date()
                        canAutoLoadMore = true
                    }
            )
            .onAppear {
                // 进入页面时：已有消息则立即滚动到底部（分多帧确保 LazyVStack 完成估算→实测修正）
                guard autoScrollToBottom else { return }
                scrollToLatest(proxy: proxy, animated: false)
            }
            // ③ 用"最后一条消息的 id"替代 count；loadMoreMessages 往头部追加不会触发
            .onChange(of: chatMessages.last?.id) { _, newId in
                guard shouldAutoScroll, newId != nil else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    scrollToLatest(proxy: proxy, animated: false)
                }
            }
            .onChange(of: streamingPreview) { _, _ in
                guard shouldAutoScroll else { return }
                // 流式预览内容更新时保持在底部
                scrollToLatest(proxy: proxy, animated: false)
            }
        }
    }

    private func handleInputChange(_ text: String) {
        // 斜杠菜单：检测最后一个 "/" 后的内容（支持文字中间插入命令）
        if let slashRange = text.range(of: "/", options: .backwards) {
            let afterSlash = String(text[slashRange.upperBound...])
            // "/" 后无空格且无换行 → 显示菜单
            showSlashMenu = !afterSlash.contains(" ") && !afterSlash.contains("\n")
        } else {
            showSlashMenu = false
        }

        // @ 提及检测与实时过滤
        if let atRange = text.range(of: "@", options: .backwards) {
            let afterAt = String(text[atRange.upperBound...])
            // 如果 @ 后没有空格，视为正在输入提及
            if !afterAt.contains(" ") {
                if !showFilePicker {
                    // 首次触发 @，加载文件列表
                    mentionBasePath = ""
                    mentionQuery = ""
                    mentionLoadError = nil
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

    private var mentionRootPath: String {
        if !sessionInfo.project.isEmpty {
            return sessionInfo.project
        }
        if let firstAllowedDirectory = messageStore.allowedDirectories.first, !firstAllowedDirectory.isEmpty {
            return firstAllowedDirectory
        }
        return "~"
    }

    private func mentionFullPath(for subpath: String) -> String {
        let trimmedSubpath = subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedSubpath.isEmpty else { return mentionRootPath }
        return mentionRootPath + "/" + trimmedSubpath
    }

    /// 委托给 FileMentionPicker 加载文件列表
    private func loadFileList(subpath: String = "") {
        let fullPath = mentionFullPath(for: subpath)
        let token = requestGate.begin("mention-file-list")
        isLoadingFileMentions = true
        mentionLoadError = nil
        relayConnection.sendWithResponse(["method": "file.list", "params": ["path": fullPath]]) { result in
            guard requestGate.isLatest(token, for: "mention-file-list") else { return }
            isLoadingFileMentions = false
            let resultDict = result["result"] as? [String: Any] ?? result
            if let entries = resultDict["entries"] as? [[String: Any]] {
                fileList = entries.compactMap {
                    guard let name = $0["name"] as? String else { return nil }
                    return MentionFileEntry(name: name, isDirectory: ($0["type"] as? String) == "directory")
                }.sorted { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                mentionLoadError = nil
                return
            }

            let fallbackMessage: String
            if subpath.isEmpty {
                fallbackMessage = String(localized: "chat.mention.load_failed", defaultValue: "无法加载文件列表，请稍后重试。")
            } else {
                fallbackMessage = String(localized: "chat.mention.load_failed_subpath", defaultValue: "无法加载这个目录，请稍后重试。")
            }
            fileList = []
            mentionLoadError = FileExplorerView.extractErrorMessage(from: result) ?? fallbackMessage
        }
    }

    private func dismissMentionPicker() {
        showFilePicker = false
        fileList = []
        isLoadingFileMentions = false
        mentionLoadError = nil
        mentionQuery = ""
        mentionBasePath = ""
    }


    // MARK: - 消息持久化

    func appendMessage(_ msg: ClaudeChatItem) {
        var msgs = messageStore.claudeChats[surfaceID] ?? []
        msgs.append(msg)
        messageStore.setClaudeChat(surfaceID, messages: msgs)
        sessionManager.touchActivity(surfaceID: surfaceID, at: msg.timestamp)
    }


    // MARK: - 分页加载

    /// 加载更早的消息（向上滚动时触发）
    private func loadMoreMessages(proxy: ScrollViewProxy) {
        guard hasMoreMessages, !isLoadingMoreMessages else { return }
        if localHasMoreMessages {
            isLoadingMoreMessages = true
            let firstVisibleId = chatMessages.first?.id
            suppressAutoScroll = true
            displayLimit += Self.pageSize
            if let id = firstVisibleId {
                viewTaskBag.runAfter(0.05) {
                    proxy.scrollTo(id, anchor: .top)
                    viewTaskBag.runAfter(0.3) {
                        suppressAutoScroll = false
                        isLoadingMoreMessages = false
                    }
                }
            } else {
                suppressAutoScroll = false
                isLoadingMoreMessages = false
            }
            return
        }

        let fallbackCursor = oldestLoadedSeq
        guard let cursor = pagingState.nextPageCursor(fallbackOldestLoadedSeq: fallbackCursor), cursor > 1 else {
            if !messageStore.hasCompleteClaudeChatHistory(for: surfaceID) {
                requestHistoryFetch(mode: .fullRefreshLegacy)
            }
            return
        }

        isLoadingMoreMessages = true
        suppressAutoScroll = true
        requestHistoryFetch(mode: .pageBefore(cursor))
    }

    /// 是否允许自动滚到最新：排除分页期抑制 + 用户近 3 秒内刚手动滑动
    var shouldAutoScroll: Bool {
        if !autoScrollToBottom { return false }
        if suppressAutoScroll { return false }
        if Date().timeIntervalSince(lastUserScrollAt) < 3 { return false }
        return true
    }

    /// ① 可靠的"滚动到最新消息"：优先定位真实最后一条消息的 id，anchor .bottom；
    /// 分两帧调用兼容 LazyVStack 的估算→实测高度过程
    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool) {
        let targetId: String = {
            // 流式预览优先（isThinking 时 streamingPreviewView 在最下）
            if isThinking { return "thinking" }
            if let last = chatMessages.last { return last.id }
            return "end"
        }()
        let doScroll = {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(targetId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(targetId, anchor: .bottom)
            }
        }
        // 第 1 帧：触发 LazyVStack 把目标附近 item 渲染出来
        viewTaskBag.runAfter(0) { doScroll() }
        // 第 2 帧：等真实高度测量完再补一次，修正估算误差
        viewTaskBag.runAfter(0.08) { doScroll() }
        // 第 3 帧：兜底一次（超长列表场景）
        viewTaskBag.runAfter(0.25) { doScroll() }
    }

    // MARK: - 从 JSONL 拉取消息（实现见 ClaudeChatHistoryLoader.swift）


}

