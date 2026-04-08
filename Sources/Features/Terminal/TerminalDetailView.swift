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
                ClaudeChatView(surfaceID: surfaceID)
                    .environmentObject(messageStore)
                    .environmentObject(inputManager)
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

    /// 每 3 秒检测一次终端是否进入/退出 Claude 模式
    private func startModeDetection() {
        modeDetectTask?.cancel()
        modeDetectTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                detectMode()
            }
        }
    }

    // MARK: - 检测模式

    private func detectMode() {
        // 用户手动退出后暂停检测，等 Claude 进程退出
        guard Date() > suppressAutoDetectUntil else { return }

        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let lines = resultDict["lines"] as? [String] {
                let detected = ClaudeOutputParser.isClaudeSession(lines)
                let info = ClaudeOutputParser.parseSessionInfo(lines)
                sessionModel = info.model
                sessionContext = info.context
                withAnimation(.easeInOut(duration: 0.2)) {
                    isClaudeMode = detected
                }
            }
        }
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
