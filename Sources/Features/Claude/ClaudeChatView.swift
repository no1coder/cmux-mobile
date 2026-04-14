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
    @AppStorage("showTokenUsage") private var showTokenUsage = true
    @AppStorage("autoScrollToBottom") private var autoScrollToBottom = true

    @StateObject private var composeViewModel = ComposeInputViewModel()
    @StateObject private var requestGate = LatestOnlyRequestGate()
    @State private var inputText = ""
    @State private var isThinking = false
    @State private var activityLabel = ""
    @State private var sessionInfo: (model: String, project: String, context: String) = ("", "", "")
    @State private var refreshTask: Task<Void, Never>?
    /// 流式预览：Claude 生成过程中从终端屏幕读取的实时输出
    @State private var streamingPreview = ""
    /// 流式预览轮询任务
    @State private var streamingTask: Task<Void, Never>?
    /// 视图生命周期内派生的辅助任务（TUI 抓屏 / 模型切换 toast 自动隐藏 / 滚动修正）
    /// 存在 @StateObject 里，视图销毁时统一取消，避免 Task 泄漏 + 持有已释放的 @State
    @StateObject private var viewTaskBag = ViewTaskBag()
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
    @State private var isLoadingFileMentions = false
    @State private var mentionLoadError: String?
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
    @State private var historyLoadState: HistoryLoadState = .idle
    @State private var fullHistoryState: FullHistoryState = .idle
    @State private var claudeUpdateObserverID: UUID?
    @State private var activeHistoryFetchMode: HistoryFetchMode?
    @State private var queuedHistoryFetchMode: HistoryFetchMode?
    @State private var hasMoreRemoteHistory = false
    @State private var nextBeforeSeq: Int?
    @State private var pagingState = ClaudeHistoryPagingState()
    /// 每页消息数量
    private static let pageSize = 200
    /// 当前显示消息上限（向上滚动时递增）
    @State private var displayLimit = 200
    @State private var isLoadingMoreMessages = false
    @State private var canAutoLoadMore = false
    /// 加载更早消息期间临时抑制"自动滚到底部"（避免与 loadMoreMessages 的锚点竞争）
    @State private var suppressAutoScroll = false
    /// 用户最近一次手动拖动聊天的时间：3 秒内的自动滚到底部会被抑制，
    /// 避免用户在上翻看历史时被新消息/流式预览强行拉回底部
    @State private var lastUserScrollAt: Date = .distantPast
    // MARK: - 发送状态

    private enum SendStage: Equatable {
        case sending
        case queued
        case delivered
        case thinking
        case failed(String)
    }

    private struct PendingSend: Equatable {
        let id: String
        var stage: SendStage
    }

    private struct PendingLocalEcho: Equatable {
        let localID: String
        let content: String
    }

    private enum HistoryLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private enum FullHistoryState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private enum HistoryFetchMode: Equatable {
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
    @State private var pendingSend: PendingSend?
    @State private var lastSendText = ""
    @State private var pendingLocalEchoes: [PendingLocalEcho] = []

    /// 是否还有更早的消息可加载
    private var hasMoreMessages: Bool {
        let all = messageStore.claudeChats[surfaceID] ?? []
        return all.count > displayLimit || hasMoreRemoteHistory
    }

    private var localHasMoreMessages: Bool {
        let all = messageStore.claudeChats[surfaceID] ?? []
        return all.count > displayLimit
    }

    private var oldestLoadedSeq: Int? {
        (messageStore.claudeChats[surfaceID] ?? []).compactMap(\.seq).min()
    }

    private var chatMessages: [ClaudeChatItem] {
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
                pagingState.bootstrapFromCache(
                    hasCompleteHistory: messageStore.hasCompleteClaudeChatHistory(for: surfaceID),
                    cachedHasSeqMetadata: cachedMessages.contains { $0.seq != nil },
                    oldestLoadedSeq: oldestLoadedSeq
                )
                hasMoreRemoteHistory = pagingState.hasMoreRemoteHistory
                nextBeforeSeq = pagingState.nextBeforeSeq
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
            if showTokenUsage && !tokenUsage.isEmpty {
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

    private var emptyChatState: some View {
        VStack(spacing: 10) {
            switch historyLoadState {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "chat.loading_history", defaultValue: "正在加载历史消息…"))
                    .font(.system(size: 13))
                    .foregroundStyle(CMColors.textTertiary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(CMColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Button(String(localized: "common.retry", defaultValue: "重试")) {
                    requestHistoryFetch()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .idle, .loaded:
                Text(String(localized: "chat.empty_prompt", defaultValue: "向 Claude 发送消息开始对话"))
                    .font(.system(size: 13))
                    .foregroundStyle(CMColors.textTertiary)
            }
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var historyBackfillBanner: some View {
        switch fullHistoryState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "chat.loading_more_history", defaultValue: "正在补全更早历史…"))
                    .font(.system(size: 12))
                    .foregroundStyle(CMColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(CMColors.textSecondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "chat.retry_full_history", defaultValue: "重试加载完整历史")) {
                    hydrateFullHistoryIfNeeded(force: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        case .idle, .loaded:
            EmptyView()
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

    // MARK: - 发送

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Haptics.rigid()
        let messageId = "local-user-\(UUID().uuidString)"
        inputText = ""; showSlashMenu = false; showFilePicker = false

        appendMessage(ClaudeChatItem(id: messageId, role: .user, content: text, timestamp: Date()))
        pendingLocalEchoes.append(PendingLocalEcho(localID: messageId, content: text))
        lastSendText = text

        if relayConnection.status != .connected {
            relayConnection.send([
                "method": "surface.send_text",
                "params": ["surface_id": surfaceID, "text": text + "\n"],
            ])
            withAnimation { pendingSend = PendingSend(id: messageId, stage: .queued) }
            return
        }

        withAnimation { pendingSend = PendingSend(id: messageId, stage: .sending) }

        relayConnection.sendWithResponse([
            "method": "surface.send_text",
            "params": ["surface_id": surfaceID, "text": text + "\n"],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let error = FileExplorerView.extractErrorMessage(from: result) ?? resultDict["error"] as? String {
                withAnimation { pendingSend = PendingSend(id: messageId, stage: .failed(error)) }
                return
            }
            withAnimation { pendingSend = PendingSend(id: messageId, stage: .delivered) }
            isThinking = true
        }
    }

    private func retrySend() {
        guard let pending = pendingSend, case .failed = pending.stage else { return }

        if relayConnection.status != .connected {
            relayConnection.send([
                "method": "surface.send_text",
                "params": ["surface_id": surfaceID, "text": lastSendText + "\n"],
            ])
            withAnimation { pendingSend = PendingSend(id: pending.id, stage: .queued) }
            return
        }

        withAnimation { pendingSend = PendingSend(id: pending.id, stage: .sending) }
        relayConnection.sendWithResponse([
            "method": "surface.send_text",
            "params": ["surface_id": surfaceID, "text": lastSendText + "\n"],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let error = FileExplorerView.extractErrorMessage(from: result) ?? resultDict["error"] as? String {
                withAnimation { pendingSend = PendingSend(id: pending.id, stage: .failed(error)) }
                return
            }
            withAnimation { pendingSend = PendingSend(id: pending.id, stage: .delivered) }
            isThinking = true
        }
    }

    private func sendDirect(_ text: String) {
        relayConnection.send(["method": "surface.send_text", "params": ["surface_id": surfaceID, "text": text]])

        guard relayConnection.status == .connected else { return }

        // 检测 TUI-only 命令：输出只在终端显示，不会写入 JSONL
        // 发送后抓取屏幕内容，清洗后作为聊天气泡就地展示
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isTUIOnlyCommand(trimmed) {
            let label = trimmed.components(separatedBy: .whitespaces).first ?? trimmed
            captureTUIOutput(for: label)
        }
    }

    /// 仅在终端 TUI 中渲染输出的斜杠命令集合
    /// 这些命令执行后不会在 JSONL 中产生消息，聊天视图自然不会显示内容
    private static let tuiOnlyCommands: Set<String> = [
        "/status", "/help", "/cost", "/config", "/model", "/clear",
        "/memory", "/doctor", "/bug", "/mcp", "/hooks", "/agents",
        "/permissions", "/add-dir", "/ide", "/release-notes", "/vim",
        "/terminal-setup", "/init", "/review", "/logout", "/login",
        "/privacy-settings", "/upgrade", "/export", "/todos",
    ]

    private static func isTUIOnlyCommand(_ text: String) -> Bool {
        guard text.hasPrefix("/") else { return false }
        let head = text.components(separatedBy: .whitespaces).first ?? text
        return tuiOnlyCommands.contains(head)
    }

    /// 发送 TUI-only 命令后从终端屏幕抓取输出，就地渲染为聊天气泡
    /// 策略：轮询 read_screen，等画面稳定后抓取，清洗 ANSI/TUI 边框字符后展示
    private func captureTUIOutput(for command: String) {
        let placeholderId = "tui-\(UUID().uuidString)"
        // 先插入占位气泡，表示正在读取
        appendMessage(ClaudeChatItem(
            id: placeholderId,
            role: .tuiOutput(command: command),
            content: String(localized: "claude.tui.reading", defaultValue: "读取终端输出中…"),
            timestamp: Date()
        ))

        let task = Task { @MainActor in
            // 等一会让 TUI 渲染完成；再多轮读取直到画面稳定
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            var lastHash = 0
            var stableCount = 0
            var finalLines: [String] = []
            for attempt in 0..<8 {
                let lines = await readScreenLinesAsync()
                guard !Task.isCancelled else { return }
                let hash = lines.joined(separator: "\n").hashValue
                if hash == lastHash {
                    stableCount += 1
                } else {
                    stableCount = 0
                    lastHash = hash
                }
                finalLines = lines
                // 连续 2 次相同即视为稳定
                if stableCount >= 1 && attempt >= 1 { break }
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
            }

            let cleaned = Self.cleanTUIOutput(finalLines, command: command)
            replaceTUIOutput(
                id: placeholderId,
                command: command,
                content: cleaned.isEmpty
                    ? String(localized: "claude.tui.empty",
                             defaultValue: "未能抓到 \(command) 的输出，点击聊天右上角菜单 →「查看终端」可直接查看")
                    : cleaned
            )
        }
        viewTaskBag.add(task)
    }

    private func readScreenLinesAsync() async -> [String] {
        guard relayConnection.status == .connected else { return [] }
        return await withCheckedContinuation { cont in
            relayConnection.sendWithResponse([
                "method": "read_screen",
                "params": ["surface_id": surfaceID],
            ]) { result in
                let dict = result["result"] as? [String: Any] ?? result
                let lines = dict["lines"] as? [String] ?? []
                cont.resume(returning: lines)
            }
        }
    }

    /// 清洗终端屏幕文本：去除 ANSI 转义、TUI 边框字符、多余空白；
    /// 尽量剔除 Claude Code 聊天 UI 本身的装饰（输入框、快捷键提示），
    /// 只保留 /status 等命令真正输出的内容
    private static func cleanTUIOutput(_ lines: [String], command: String) -> String {
        // 去 ANSI 转义
        let ansi = try? NSRegularExpression(pattern: "\u{1b}\\[[0-9;?]*[a-zA-Z]")
        // 边框/盒线/半格字符
        let boxChars = Set<Character>(
            "─│┌┐└┘├┤┬┴┼━┃┏┓┗┛┣┫┳┻╋═║╔╗╚╝╠╣╦╩╬▌▐▀▄╭╮╰╯▲▼◀▶"
        )
        // 装饰性/状态栏字符：角标、✳、⏵、❯、›、 ⎿ 等
        let decoPrefixes: [String] = ["✳", "⏵", "❯", "›", "⎿", "▸", "▲", "▼"]
        // 明显属于输入框或快捷键提示的行
        let noisePatterns: [String] = [
            "Esc to cancel", "Tab to amend", "ctrl+e to explain",
            "to approve", "to reject", "to exit", "Shift+Tab",
            "? for shortcuts", "input?", "Type your message",
        ]

        var result: [String] = []
        for raw in lines {
            var s = raw
            if let regex = ansi {
                let range = NSRange(s.startIndex..., in: s)
                s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            }
            // 去边框字符
            s = String(s.filter { !boxChars.contains($0) })
            s = s.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else {
                // 保留单个空行分隔
                if result.last?.isEmpty == false { result.append("") }
                continue
            }
            if decoPrefixes.contains(where: { s.hasPrefix($0) }) {
                s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
                if s.isEmpty { continue }
            }
            // 过滤噪声提示
            if noisePatterns.contains(where: { s.localizedCaseInsensitiveContains($0) }) {
                continue
            }
            result.append(s)
        }
        // 折叠末尾空行
        while result.last?.isEmpty == true { result.removeLast() }
        // 折叠头部空行
        while result.first?.isEmpty == true { result.removeFirst() }
        // 去重：连续相同行合并
        var deduped: [String] = []
        for line in result {
            if deduped.last != line { deduped.append(line) }
        }
        return deduped.joined(separator: "\n")
    }

    /// 替换先前插入的占位 TUI 气泡
    private func replaceTUIOutput(id: String, command: String, content: String) {
        var msgs = messageStore.claudeChats[surfaceID] ?? []
        guard let index = msgs.firstIndex(where: { $0.id == id }) else { return }
        msgs[index] = ClaudeChatItem(
            id: id,
            role: .tuiOutput(command: command),
            content: content,
            timestamp: msgs[index].timestamp
        )
        messageStore.setClaudeChat(surfaceID, messages: msgs)
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
        let localMessageID = "local-user-\(UUID().uuidString)"
        appendMessage(ClaudeChatItem(id: localMessageID, role: .user, content: displayText, timestamp: Date()))
        pendingLocalEchoes.append(PendingLocalEcho(localID: localMessageID, content: displayText))

        let composedMsgId = UUID().uuidString
        if relayConnection.status == .connected {
            withAnimation { pendingSend = PendingSend(id: composedMsgId, stage: .sending) }
        } else {
            withAnimation { pendingSend = PendingSend(id: composedMsgId, stage: .queued) }
        }
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
        if relayConnection.status == .connected {
            isThinking = true
        }
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
    private var shouldAutoScroll: Bool {
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

    // MARK: - 从 JSONL 拉取消息（跟 happy 的 sessionScanner 一样）

    private func requestHistoryFetch(mode: HistoryFetchMode = .incremental) {
        if let activeHistoryFetchMode {
            if activeHistoryFetchMode.priority >= mode.priority {
                return
            }
            queuedHistoryFetchMode = mode
            return
        }

        fetchMessages(mode: mode)
    }

    private func finishHistoryFetch(_ mode: HistoryFetchMode) {
        guard activeHistoryFetchMode == mode else { return }
        activeHistoryFetchMode = nil

        guard let queuedHistoryFetchMode else { return }
        self.queuedHistoryFetchMode = nil
        fetchMessages(mode: queuedHistoryFetchMode)
    }

    private func fetchMessages(mode: HistoryFetchMode = .incremental) {
        activeHistoryFetchMode = mode
        let startedAt = Date()
        let token = requestGate.begin(mode.requestGateKey)
        let hadCachedMessages = !(messageStore.claudeChats[surfaceID] ?? []).isEmpty
        let previousCachedCount = messageStore.claudeChats[surfaceID]?.count ?? 0
        if mode != .incremental {
            fullHistoryState = .loading
            if !hadCachedMessages {
                historyLoadState = .loading
            }
        } else if !hadCachedMessages {
            historyLoadState = .loading
        }

        var params: [String: Any] = ["surface_id": surfaceID]
        switch mode {
        case .incremental:
            params["after_seq"] = lastSeq
        case .recentPage:
            params["limit"] = Self.pageSize
        case .pageBefore(let beforeSeq):
            params["before_seq"] = beforeSeq
            params["limit"] = Self.pageSize
        case .fullRefreshLegacy:
            params["after_seq"] = 0
        }

        relayConnection.sendWithResponse([
            "method": "claude.messages",
            "params": params,
            "client_timeout_seconds": mode.timeoutSeconds,
        ]) { result in
            defer { finishHistoryFetch(mode) }
            guard requestGate.isLatest(token, for: mode.requestGateKey) else { return }
            let resultDict = result["result"] as? [String: Any] ?? result

            if let error = resultDict["error"] as? String {
                let message = (resultDict["message"] as? String)
                    ?? String(localized: "chat.history_load_failed", defaultValue: "加载历史消息失败，请稍后重试。")
                if mode != .incremental {
                    if !hadCachedMessages && chatMessages.isEmpty {
                        historyLoadState = .failed(message)
                    }
                    fullHistoryState = .failed(message)
                } else if !hadCachedMessages && chatMessages.isEmpty {
                    historyLoadState = .failed(message)
                } else {
                    historyLoadState = .loaded
                }
                #if DEBUG
                print("[claude] claude.messages 失败: \(error) \(message)")
                #endif
                return
            }

            if let totalSeq = resultDict["total_seq"] as? Int {
                if mode == .fullRefreshLegacy && totalSeq < lastSeq {
                    // 说明全量回填返回时，本地已经收到了更新的增量；
                    // 不要用较旧快照覆盖当前聊天，再发起一次全量回填。
                    fullHistoryState = .idle
                    viewTaskBag.runAfter(0.2) {
                        requestHistoryFetch(mode: .fullRefreshLegacy)
                    }
                    return
                }
                lastSeq = totalSeq
                messageStore.setClaudeChatSequence(surfaceID, totalSeq: totalSeq)
            }

            // 更新整体状态
            let status = resultDict["status"] as? String ?? "idle"
            activityLabel = status
            isThinking = (status == "thinking" || status == "tool_running")

            // 提取 token 用量
            if let usage = resultDict["usage"] as? [String: Int] {
                tokenUsage = usage
            }

            pagingState.applyResponse(
                fetchKind: mode.coreKind,
                hasMore: resultDict["has_more"] as? Bool,
                serverNextBeforeSeq: resultDict["next_before_seq"] as? Int,
                fallbackOldestLoadedSeq: oldestLoadedSeq
            )
            hasMoreRemoteHistory = pagingState.hasMoreRemoteHistory
            nextBeforeSeq = pagingState.nextBeforeSeq

            guard let messages = resultDict["messages"] as? [[String: Any]] else {
                let existingMessages = messageStore.claudeChats[surfaceID] ?? []
                let normalizedMessages = ClaudeChatItem.normalizeRunningTools(
                    in: existingMessages,
                    allowTrailingRunningTools: status == "tool_running"
                )
                if normalizedMessages != existingMessages {
                    messageStore.setClaudeChat(surfaceID, messages: normalizedMessages, totalSeq: lastSeq > 0 ? lastSeq : nil)
                }
                if mode != .incremental {
                    if !hadCachedMessages && chatMessages.isEmpty {
                        historyLoadState = .failed(String(
                            localized: "chat.history_missing_payload",
                            defaultValue: "未收到会话历史数据，请稍后重试。"
                        ))
                    }
                    fullHistoryState = .failed(String(
                        localized: "chat.history_missing_payload",
                        defaultValue: "未收到会话历史数据，请稍后重试。"
                    ))
                } else if !hadCachedMessages && chatMessages.isEmpty {
                    historyLoadState = .failed(String(
                        localized: "chat.history_missing_payload",
                        defaultValue: "未收到会话历史数据，请稍后重试。"
                    ))
                } else {
                    historyLoadState = .loaded
                }
                return
            }

            #if DEBUG
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[claude] history \(String(describing: mode)) loaded in \(elapsedMs)ms messages=\(messages.count) totalSeq=\(lastSeq) hasMore=\(hasMoreRemoteHistory) nextBefore=\(nextBeforeSeq.map(String.init) ?? "nil") cachedBefore=\(previousCachedCount)")
            #endif

            let prependOlderMessages: Bool = {
                if case .pageBefore = mode { return true }
                return false
            }()

            processJsonlMessages(
                messages,
                resetExisting: mode == .fullRefreshLegacy,
                prependOlderMessages: prependOlderMessages
            )
            if mode != .incremental {
                let refreshedCount = messageStore.claudeChats[surfaceID]?.count ?? 0
                if prependOlderMessages {
                    preserveExpandedHistoryWindowAfterPrepend(
                        previousCount: previousCachedCount,
                        refreshedCount: refreshedCount
                    )
                } else {
                    preserveExpandedHistoryWindowAfterFullRefresh(
                        previousCount: previousCachedCount,
                        refreshedCount: refreshedCount
                    )
                }
                messageStore.setClaudeChatHistoryCompleteness(surfaceID, hasCompleteHistory: !hasMoreRemoteHistory)
                fullHistoryState = .loaded
            }
            historyLoadState = .loaded
            if !isThinking && pendingSend != nil {
                withAnimation { pendingSend = nil }
            }
            if prependOlderMessages {
                viewTaskBag.runAfter(0.3) {
                    suppressAutoScroll = false
                    isLoadingMoreMessages = false
                }
            }
        }
    }

    private func preserveExpandedHistoryWindowAfterFullRefresh(previousCount: Int, refreshedCount: Int) {
        guard displayLimit > Self.pageSize else { return }
        guard refreshedCount > previousCount else { return }

        let insertedOlderCount = refreshedCount - previousCount
        displayLimit = min(refreshedCount, displayLimit + insertedOlderCount)
    }

    private func preserveExpandedHistoryWindowAfterPrepend(previousCount: Int, refreshedCount: Int) {
        guard refreshedCount > previousCount else { return }
        let insertedOlderCount = refreshedCount - previousCount
        displayLimit = min(refreshedCount, displayLimit + insertedOlderCount)
    }

    /// 将 JSONL 结构化消息转换为 UI 消息
    private func processJsonlMessages(
        _ messages: [[String: Any]],
        resetExisting: Bool = false,
        prependOlderMessages: Bool = false
    ) {
        var newItems: [ClaudeChatItem] = []
        var newItemIndexes: [String: Int] = [:]
        // 收集 tool_result，用于关联到 tool_use
        var toolResults: [String: (content: String, isError: Bool)] = [:]

        // HIGH 修复：预构建去重集合，O(1) 查找替代 O(n) contains
        var existingMessages = resetExisting ? [] : (messageStore.claudeChats[surfaceID] ?? [])
        let previousMessageCount = existingMessages.count
        if resetExisting && messages.isEmpty {
            if !(messageStore.claudeChats[surfaceID] ?? []).isEmpty {
                messageStore.setClaudeChat(surfaceID, messages: [], totalSeq: lastSeq > 0 ? lastSeq : nil)
            }
            updatePlanModeState([])
            return
        }

        var existingIDs = Set(existingMessages.map(\.id))
        let existingToolIds = Set(existingMessages.compactMap(\.toolUseId))
        var seenMessageIDs = existingIDs
        var seenToolUseIDs = existingToolIds
        var reconciledLocalEcho = false
        var updatedExistingMessages = false

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
            let seq = msg["seq"] as? Int
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
                        if !resetExisting,
                           reconcilePendingLocalEcho(
                            remoteID: uuid,
                            text: text,
                            existingMessages: &existingMessages,
                            existingIDs: &existingIDs,
                            seenMessageIDs: &seenMessageIDs
                           ) {
                            reconciledLocalEcho = true
                            continue
                        }

                        if !seenMessageIDs.contains(uuid) {
                            upsertNewItem(
                                ClaudeChatItem(id: uuid, seq: seq, role: .user, content: text, timestamp: Date()),
                                key: uuid,
                                into: &newItems,
                                indexes: &newItemIndexes
                            )
                            seenMessageIDs.insert(uuid)
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
                                updatedExistingMessages = updateOrAppendStreamingMessage(
                                    &newItems,
                                    newItemIndexes: &newItemIndexes,
                                    existingMessages: &existingMessages,
                                    existingIDs: existingIDs,
                                    id: msgID, role: .assistant,
                                    content: text, modelName: displayModel
                                ) || updatedExistingMessages
                            } else if !seenMessageIDs.contains(msgID) {
                                upsertNewItem(
                                    ClaudeChatItem(
                                        id: msgID, seq: seq, role: .assistant,
                                        content: text, timestamp: Date(),
                                        modelName: displayModel
                                    ),
                                    key: msgID,
                                    into: &newItems,
                                    indexes: &newItemIndexes
                                )
                                seenMessageIDs.insert(msgID)
                            }
                        }
                    case "thinking":
                        // 思考过程（extended thinking）
                        if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                            let thinkingID = "\(uuid)-thinking"
                            if !seenMessageIDs.contains(thinkingID) {
                                upsertNewItem(
                                    ClaudeChatItem(
                                        id: thinkingID, seq: seq, role: .thinking,
                                        content: thinking, timestamp: Date()
                                    ),
                                    key: thinkingID,
                                    into: &newItems,
                                    indexes: &newItemIndexes
                                )
                                seenMessageIDs.insert(thinkingID)
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
                        if !seenToolUseIDs.contains(toolUseId) {
                            upsertNewItem(
                                ClaudeChatItem(
                                    id: "\(uuid)-tool-\(toolUseId.prefix(8))",
                                    seq: seq,
                                    role: .tool(name: toolName),
                                    content: summary,
                                    timestamp: Date(),
                                    toolResult: result?.content,
                                    toolState: toolState,
                                    toolUseId: toolUseId,
                                    completedAt: result != nil ? Date() : nil
                                ),
                                key: "tool-\(toolUseId)",
                                into: &newItems,
                                indexes: &newItemIndexes
                            )
                            seenToolUseIDs.insert(toolUseId)
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
        var all: [ClaudeChatItem] = []
        var updated = reconciledLocalEcho || updatedExistingMessages
        for item in existingMessages {
            if let toolId = item.toolUseId, item.toolState == .running,
               let result = toolResults[toolId] {
                // 创建新实例替代就地修改
                let updatedItem = ClaudeChatItem(
                    id: item.id,
                    seq: item.seq,
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
            if prependOlderMessages {
                all = newItems + all
            } else {
                all.append(contentsOf: newItems)
            }
            updated = true
        }

        let normalizedAll = ClaudeChatItem.normalizeRunningTools(
            in: all,
            allowTrailingRunningTools: activityLabel == "tool_running"
        )
        if normalizedAll != all {
            all = normalizedAll
            updated = true
        }

        if updated {
            if !prependOlderMessages {
                preserveVisibleWindowForIncrementalAppend(
                    previousCount: previousMessageCount,
                    newCount: all.count,
                    resetExisting: resetExisting
                )
            }
            messageStore.setClaudeChat(surfaceID, messages: all)
            if let latestActivityAt = newItems.map(\.timestamp).max() {
                sessionManager.touchActivity(surfaceID: surfaceID, at: latestActivityAt)
            }
            // 有新消息到达时清空流式预览（已被结构化消息替代）
            if !newItems.isEmpty { streamingPreview = "" }

            // HIGH 修复：更新 Plan 模式缓存（避免每次渲染遍历全部消息）
            updatePlanModeState(all)
        }
    }

    private func preserveVisibleWindowForIncrementalAppend(
        previousCount: Int,
        newCount: Int,
        resetExisting: Bool
    ) {
        guard !resetExisting else { return }
        guard newCount > previousCount else { return }
        guard displayLimit > Self.pageSize || !shouldAutoScroll else { return }

        let appendedCount = newCount - previousCount
        displayLimit = min(newCount, displayLimit + appendedCount)
    }

    private func upsertNewItem(
        _ item: ClaudeChatItem,
        key: String,
        into newItems: inout [ClaudeChatItem],
        indexes: inout [String: Int]
    ) {
        if let index = indexes[key] {
            newItems[index] = item
        } else {
            indexes[key] = newItems.count
            newItems.append(item)
        }
    }

    private func reconcilePendingLocalEcho(
        remoteID: String,
        text: String,
        existingMessages: inout [ClaudeChatItem],
        existingIDs: inout Set<String>,
        seenMessageIDs: inout Set<String>
    ) -> Bool {
        guard let pendingIndex = pendingLocalEchoes.firstIndex(where: { $0.content == text }) else {
            return false
        }

        let localEcho = pendingLocalEchoes[pendingIndex]
        guard let existingIndex = existingMessages.firstIndex(where: { $0.id == localEcho.localID }) else {
            pendingLocalEchoes.remove(at: pendingIndex)
            return false
        }

        let existingMessage = existingMessages[existingIndex]
        existingMessages[existingIndex] = ClaudeChatItem(
            id: remoteID,
            role: .user,
            content: text,
            timestamp: existingMessage.timestamp
        )
        existingIDs.remove(localEcho.localID)
        seenMessageIDs.remove(localEcho.localID)
        existingIDs.insert(remoteID)
        seenMessageIDs.insert(remoteID)
        pendingLocalEchoes.remove(at: pendingIndex)
        return true
    }

    /// 流式消息：更新已有的同 ID 消息内容，或追加新消息
    private func updateOrAppendStreamingMessage(
        _ newItems: inout [ClaudeChatItem],
        newItemIndexes: inout [String: Int],
        existingMessages: inout [ClaudeChatItem],
        existingIDs: Set<String>,
        id: String, role: ClaudeChatItem.Role,
        content: String, modelName: String?
    ) -> Bool {
        // 检查已有消息中是否有同 ID 的流式消息
        if let idx = existingMessages.firstIndex(where: { $0.id == id }) {
            // 内容不变则跳过
            guard existingMessages[idx].content != content else { return false }
            // 替换为新内容（不可变：创建新实例）
            existingMessages[idx] = ClaudeChatItem(
                id: id, role: role,
                content: content, timestamp: existingMessages[idx].timestamp,
                modelName: modelName
            )
            return true
        } else if !existingIDs.contains(id) {
            upsertNewItem(
                ClaudeChatItem(
                    id: id, role: role,
                    content: content, timestamp: Date(),
                    modelName: modelName
                ),
                key: id,
                into: &newItems,
                indexes: &newItemIndexes
            )
            return true
        }
        return false
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
        if claudeUpdateObserverID != nil { return }
        relayConnection.beginClaudeWatch(surfaceID: surfaceID)

        // 监听推送事件
        let sid = surfaceID
        claudeUpdateObserverID = relayConnection.addClaudeUpdateObserver { payload in
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
                    viewTaskBag.runAfter(2.5) {
                        withAnimation { modelSwitchFeedback = nil }
                    }
                    return
                case "claude.session.reset":
                    // Mac 端 JSONL 文件被截断/替换，重置状态并重新拉取
                    let payloadSid = payload["surface_id"] as? String ?? ""
                    guard payloadSid == sid else { return }
                    lastSeq = 0
                    displayLimit = Self.pageSize
                    pagingState.hasMoreRemoteHistory = true
                    pagingState.nextBeforeSeq = nil
                    hasMoreRemoteHistory = pagingState.hasMoreRemoteHistory
                    nextBeforeSeq = pagingState.nextBeforeSeq
                    tokenUsage = [:]
                    isThinking = false
                    activityLabel = ""
                    historyLoadState = .loading
                    fullHistoryState = .loading
                    messageStore.setClaudeChatHistoryCompleteness(surfaceID, hasCompleteHistory: false)
                    requestHistoryFetch(mode: .recentPage)
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
                historyLoadState = .loaded

                // 提取 token 用量
                if let usage = payload["usage"] as? [String: Int] {
                    tokenUsage = usage
                }

                processJsonlMessages(messages)

                // 更新发送状态
                if let pending = pendingSend,
                   pending.stage == .delivered || pending.stage == .sending || pending.stage == .queued {
                    let hasResponse = messages.contains { ($0["type"] as? String) == "assistant" }
                    if hasResponse || status == "thinking" || status == "tool_running" {
                        withAnimation { pendingSend = PendingSend(id: pending.id, stage: .thinking) }
                    }
                }
                if !isThinking, let pending = pendingSend, pending.stage == .thinking {
                    withAnimation { pendingSend = nil }
                }
            }
        }
    }

    private func stopWatching() {
        relayConnection.endClaudeWatch(surfaceID: surfaceID)
        if let claudeUpdateObserverID {
            relayConnection.removeClaudeUpdateObserver(claudeUpdateObserverID)
            self.claudeUpdateObserverID = nil
        }
    }

    // MARK: - 降级轮询（15秒兜底）

    private func startPolling() {
        stopPolling()
        refreshTask = Task {
            while !Task.isCancelled {
                // HIGH 修复：推送通道存在时，轮询间隔从 5 秒提升到 15 秒
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                guard relayConnection.status == .connected else { continue }
                requestHistoryFetch(mode: .incremental)
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

                let token = await MainActor.run { requestGate.begin("streaming-preview") }
                await withCheckedContinuation { continuation in
                    relayConnection.sendWithResponse([
                        "method": "read_screen",
                        "params": ["surface_id": sid],
                    ]) { result in
                        guard requestGate.isLatest(token, for: "streaming-preview") else {
                            continuation.resume()
                            return
                        }
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
                    Text(String(localized: "chat.status.sending", defaultValue: "发送中…"))
                case .queued:
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(String(localized: "chat.status.queued", defaultValue: "离线排队中…"))
                case .delivered:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(String(localized: "chat.status.delivered", defaultValue: "已送达"))
                case .thinking:
                    ThinkingDotsView()
                    Text(String(localized: "chat.status.thinking", defaultValue: "Claude 正在思考…"))
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

/// 辅助任务袋：聊天视图生命周期内派生的 Task 统一登记，视图销毁时 deinit 自动取消
/// 用于替代 DispatchQueue.main.asyncAfter（闭包强引用 self 且无法取消）
@MainActor
final class ViewTaskBag: ObservableObject {
    private var tasks: Set<UUID> = []
    private var store: [UUID: Task<Void, Never>] = [:]

    /// 注册一个异步任务；返回句柄 id 以便外部取消
    @discardableResult
    func add(_ task: Task<Void, Never>) -> UUID {
        let id = UUID()
        tasks.insert(id)
        store[id] = task
        return id
    }

    /// 延迟执行（带自动取消），替代 DispatchQueue.main.asyncAfter
    func runAfter(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        let t = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
        add(t)
    }

    func cancel(_ id: UUID) {
        store[id]?.cancel()
        store.removeValue(forKey: id)
        tasks.remove(id)
    }

    func cancelAll() {
        for (_, t) in store { t.cancel() }
        store.removeAll()
        tasks.removeAll()
    }

    deinit {
        for (_, t) in store { t.cancel() }
    }
}

private extension Array where Element == ClaudeChatItem {
    /// 按 timestamp 升序稳定排序：时间戳相同的消息保持原有相对顺序
    /// 用于合并 WS 推送 / 轮询 / 文件监听多路数据源时，避免末尾不是最新
    /// 快路径：若数组已按 timestamp 非递减，直接返回 self 避免 O(n log n) 成本
    func sortedByTimestampStable() -> [ClaudeChatItem] {
        if count < 2 { return self }
        var alreadySorted = true
        for i in 1..<count {
            if self[i - 1].timestamp > self[i].timestamp {
                alreadySorted = false
                break
            }
        }
        if alreadySorted { return self }
        // 慢路径：有乱序，稳定排序
        return enumerated()
            .sorted { lhs, rhs in
                if lhs.element.timestamp == rhs.element.timestamp {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.timestamp < rhs.element.timestamp
            }
            .map(\.element)
    }
}
