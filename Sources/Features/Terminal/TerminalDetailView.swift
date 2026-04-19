import SwiftUI

/// 终端详情页 — 自动检测 Claude，无缝切换模式
struct TerminalDetailView: View {
    let surfaceID: String
    let surfaceTitle: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection
    @EnvironmentObject var approvalManager: ApprovalManager
    @EnvironmentObject var sessionManager: SessionManager

    /// 是否在 Claude 模式
    @State private var isClaudeMode = false
    /// 是否显示原始终端（Sheet）
    @State private var showTerminalSheet = false
    /// 是否显示退出确认
    @State private var showExitConfirm = false
    /// 是否显示会话信息
    @State private var showSessionInfo = false
    /// read_screen 降频状态（引用类型，确保 Task 能读到最新值）
    @StateObject private var readScreenState = ReadScreenState()
    /// 会话信息
    @State private var sessionModel = ""
    @State private var sessionContext = ""
    /// 模式检测定时器
    @State private var modeDetectTask: Task<Void, Never>?
    /// 用户手动退出后，暂停自动检测 10 秒（等 Claude 进程退出）
    @State private var suppressAutoDetectUntil: Date = .distantPast
    @StateObject private var requestGate = LatestOnlyRequestGate()
    @Environment(\.dismiss) private var dismiss
    /// 宽限期结束时刻：首次进入视图后 5 秒内即使 surface 不在列表也不退出，
    /// 避免因为 surface.list 还没回来就误把合法页面弹掉。
    @State private var surfaceValidityGraceUntil: Date = .distantFuture

    /// 从标题中提取项目名
    private var projectName: String {
        let title = surfaceTitle
        // ~/code/aiapi → aiapi
        if let last = title.split(separator: "/").last {
            return String(last)
        }
        return title.isEmpty ? "终端" : title
    }

    private var pathSubtitle: String? {
        guard !surfaceTitle.isEmpty, surfaceTitle != projectName else { return nil }
        return surfaceTitle
    }

    var body: some View {
        Group {
            if isClaudeMode {
                // approvalManager 通过 SwiftUI 环境链从 TerminalListView 自动传播
                // 不在本视图声明 @EnvironmentObject 以避免不必要的重渲染
                ClaudeChatView(surfaceID: surfaceID)
                    .environmentObject(messageStore)
                    .environmentObject(relayConnection)
                    .environmentObject(approvalManager)
            } else {
                TerminalView(surfaceID: surfaceID)
                    .environmentObject(messageStore)
                    .environmentObject(inputManager)
                    .environmentObject(relayConnection)
            }
        }
        .navigationTitle(projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .top) {
            // 模式检测连续失败时给明确反馈，不让用户盯着空白或错误模式的界面
            if readScreenState.failCount >= 3 && !isClaudeMode {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(String(
                        localized: "terminal.mode_detect_failed",
                        defaultValue: "Claude 模式检测失败，可手动重试或保留终端视图"
                    ))
                    .font(.system(size: 12, weight: .medium))
                    Button {
                        readScreenState.failCount = 0
                        detectMode()
                    } label: {
                        Text(String(localized: "common.retry", defaultValue: "重试"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 4)
                .padding(.horizontal, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if relayConnection.status == .connected, let latency = relayConnection.latencyMs {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(latency < 100 ? .green : latency < 300 ? .yellow : .red)
                            .frame(width: 4, height: 4)
                        Text("\(latency)ms")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(projectName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let pathSubtitle {
                        Text(pathSubtitle)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if isClaudeMode {
                        Button {
                            showTerminalSheet = true
                        } label: {
                            Label("查看终端", systemImage: "terminal")
                        }

                        Button(role: .destructive) {
                            showExitConfirm = true
                        } label: {
                            Label("退出 Claude", systemImage: "xmark.circle")
                        }
                    }

                    if !sessionModel.isEmpty {
                        Section("会话信息") {
                            Label(sessionModel, systemImage: "cpu")
                            if !sessionContext.isEmpty {
                                Label("上下文 \(sessionContext)", systemImage: "chart.bar")
                            }
                            Label(surfaceTitle, systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray)
                }
                .accessibilityLabel(String(
                    localized: "common.more_actions",
                    defaultValue: "更多操作"
                ))
            }
        }
        .sheet(isPresented: $showTerminalSheet) {
            NavigationStack {
                TerminalView(surfaceID: surfaceID)
                    .environmentObject(messageStore)
                    .environmentObject(inputManager)
                    .environmentObject(relayConnection)
                    .navigationTitle("终端")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { showTerminalSheet = false }
                        }
                    }
            }
        }
        .alert("退出 Claude Code？", isPresented: $showExitConfirm) {
            Button("退出", role: .destructive) {
                exitClaude()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将发送 Ctrl+C 退出 Claude Code，回到终端")
        }
        .onAppear {
            // 进入视图 5 秒内即便列表尚未刷新也不自动退出
            surfaceValidityGraceUntil = Date().addingTimeInterval(5)
            detectMode()
            startModeDetection()
        }
        .onDisappear {
            modeDetectTask?.cancel()
            modeDetectTask = nil
        }
        .onChange(of: messageStore.surfaces) { _, new in
            // Mac 重启后 surface UUID 会全部更新；若当前详情页的 surface 已不在列表，
            // 且宽限期已过，自动回到列表页，避免用户卡在"加载失败"的壳里。
            guard Date() > surfaceValidityGraceUntil else { return }
            if !new.contains(where: { $0.id == surfaceID }) {
                print("[terminal] surface \(surfaceID) 已失效，自动返回列表")
                dismiss()
            }
        }
        // 接收 ClaudeChatView 发来的"打开终端 Sheet"请求（TUI-only 命令输出）
        .onReceive(NotificationCenter.default.publisher(for: .cmuxOpenTerminalSheet)) { note in
            guard let target = note.userInfo?["surfaceID"] as? String,
                  target == surfaceID else { return }
            showTerminalSheet = true
        }
    }

    // MARK: - 周期性模式检测

    /// 周期性检测终端模式（失败时自动降频，避免日志刷屏）
    private func startModeDetection() {
        modeDetectTask?.cancel()
        modeDetectTask = Task {
            while !Task.isCancelled {
                // 正常 3 秒，连续失败后逐步延长到 30 秒
                let delay = min(3 + readScreenState.failCount * 3, 30)
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                guard !Task.isCancelled else { break }
                detectMode()
            }
        }
    }

    // MARK: - 检测模式

    private func detectMode() {
        // 用户手动退出后暂停检测，等 Claude 进程退出
        guard Date() > suppressAutoDetectUntil else { return }

        // 已在 Claude 模式时：只检查标题是否仍然有效（轻量检测）
        // 不再用 read_screen 重新检测，避免工具执行时 TUI 输出变化导致闪回终端
        if isClaudeMode {
            // 标题仍然是 Claude → 保持，顺便补一次会话信息（菜单"会话信息"区块需要）
            if detectModeFromTitle() {
                if sessionModel.isEmpty { fetchSessionInfo() }
                registerClaudeSession()
                return
            }
            // 标题不再是 Claude（进程已退出，标题恢复为 shell 目录）→ 退出 Claude 模式
            // 但给一个缓冲期：Claude 退出后标题可能有延迟更新
            // 用 read_screen 二次确认
            let token = requestGate.begin("mode-detect")
            relayConnection.sendWithResponse([
                "method": "read_screen",
                "params": ["surface_id": surfaceID],
            ]) { result in
                guard requestGate.isLatest(token, for: "mode-detect") else { return }
                let resultDict = result["result"] as? [String: Any] ?? result
                if let lines = resultDict["lines"] as? [String] {
                    let stillClaude = ClaudeOutputParser.isClaudeSession(lines)
                    if !stillClaude && !detectModeFromTitle() {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isClaudeMode = false
                        }
                    }
                }
            }
            return
        }

        // 不在 Claude 模式时：尝试检测是否进入了 Claude
        // 优先用 surface 标题检测（无需 RPC，零延迟）
        if detectModeFromTitle() {
            withAnimation(.easeInOut(duration: 0.2)) {
                isClaudeMode = true
            }
            // 快路径不包含模型/上下文，异步补一次（菜单"会话信息"区块需要）
            fetchSessionInfo()
            registerClaudeSession()
            return
        }

        // 标题未检测到时，尝试 read_screen（兼容旧版）
        let token = requestGate.begin("mode-detect")
        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
            guard requestGate.isLatest(token, for: "mode-detect") else { return }
            let resultDict = result["result"] as? [String: Any] ?? result
            if let lines = resultDict["lines"] as? [String] {
                readScreenState.failCount = 0
                let detected = ClaudeOutputParser.isClaudeSession(lines)
                if detected {
                    let info = ClaudeOutputParser.parseSessionInfo(lines)
                    sessionModel = info.model
                    sessionContext = info.context
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isClaudeMode = true
                    }
                    registerClaudeSession()
                }
            } else {
                readScreenState.failCount += 1
            }
        }
    }

    /// 在 SessionManager 中登记/刷新当前 Claude 会话
    /// 由于 Claude 运行时会把标题临时改成摘要文本（如 "Fix..."），
    /// 单靠 SessionManager.syncFromSurfaces 的标题匹配无法稳定识别，
    /// 这里由已确认 Claude 模式的 TerminalDetailView 主动登记
    private func registerClaudeSession() {
        let surface = messageStore.surfaces.first { $0.id == surfaceID }
        sessionManager.markAsClaudeSession(
            surfaceID: surfaceID,
            title: surface?.title ?? surfaceTitle,
            cwd: surface?.cwd
        )
    }

    /// 异步拉取 Claude 会话信息（模型 / 上下文），仅用于填充三点菜单"会话信息"区块
    /// 快路径（标题检测）不会触发 read_screen，这里单独补一次
    private func fetchSessionInfo() {
        let token = requestGate.begin("session-info")
        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
            guard requestGate.isLatest(token, for: "session-info") else { return }
            let resultDict = result["result"] as? [String: Any] ?? result
            guard let lines = resultDict["lines"] as? [String] else { return }
            let info = ClaudeOutputParser.parseSessionInfo(lines)
            if !info.model.isEmpty { sessionModel = info.model }
            if !info.context.isEmpty { sessionContext = info.context }
        }
    }

    /// 从 surface 标题和 cwd 检测 Claude 模式
    /// Claude Code 运行时终端标题会变为 "✳ ..." 或包含 "Claude Code"
    private func detectModeFromTitle() -> Bool {
        // 从 messageStore 中查找当前 surface
        guard let surface = messageStore.surfaces.first(where: { $0.id == surfaceID }) else {
            return false
        }
        let title = surface.title
        // ✳ 是 cmux 为 Claude Code 会话添加的标识前缀
        if title.hasPrefix("✳") { return true }
        // 标题直接包含 Claude Code
        if title.contains("Claude Code") { return true }
        return false
    }

    // MARK: - 退出 Claude

    private func exitClaude() {
        // 暂停自动检测 10 秒，防止 Claude 还没退出就被重新检测到
        suppressAutoDetectUntil = Date().addingTimeInterval(10)

        // 发送 Ctrl+C 退出 Claude Code
        relayConnection.send([
            "method": "surface.send_key",
            "params": ["surface_id": surfaceID, "key": "ctrl-c"],
        ])
        // 切换到终端模式
        withAnimation {
            isClaudeMode = false
        }
    }
}
