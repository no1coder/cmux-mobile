import SwiftUI

/// 终端详情页 — 自动检测 Claude，无缝切换模式
struct TerminalDetailView: View {
    let surfaceID: String
    let surfaceTitle: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

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

    /// 从标题中提取项目名
    private var projectName: String {
        let title = surfaceTitle
        // ~/code/aiapi → aiapi
        if let last = title.split(separator: "/").last {
            return String(last)
        }
        return title.isEmpty ? "终端" : title
    }

    var body: some View {
        Group {
            if isClaudeMode {
                // approvalManager 通过 SwiftUI 环境链从 TerminalListView 自动传播
                // 不在本视图声明 @EnvironmentObject 以避免不必要的重渲染
                ClaudeChatView(surfaceID: surfaceID)
                    .environmentObject(messageStore)
                    .environmentObject(relayConnection)
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
        .toolbar {
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
            detectMode()
            startModeDetection()
        }
        .onDisappear {
            modeDetectTask?.cancel()
            modeDetectTask = nil
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
            // 标题仍然是 Claude → 保持
            if detectModeFromTitle() { return }
            // 标题不再是 Claude（进程已退出，标题恢复为 shell 目录）→ 退出 Claude 模式
            // 但给一个缓冲期：Claude 退出后标题可能有延迟更新
            // 用 read_screen 二次确认
            relayConnection.sendWithResponse([
                "method": "read_screen",
                "params": ["surface_id": surfaceID],
            ]) { result in
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
            return
        }

        // 标题未检测到时，尝试 read_screen（兼容旧版）
        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
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
                }
            } else {
                readScreenState.failCount += 1
            }
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
