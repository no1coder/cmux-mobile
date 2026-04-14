import SwiftUI

@main
struct cmuxMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var messageStore = MessageStore()
    @StateObject private var relayConnection = RelayConnection()
    @StateObject private var inputManager = InputManager()
    @StateObject private var approvalManager = ApprovalManager()
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var activityStore = ActivityStore()
    @State private var hasPairedDevice = DeviceStore.hasPairedDevice()

    /// 主题偏好：跟随系统 / 亮色 / 暗色
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.dark.rawValue

    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .dark
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasPairedDevice {
                    PairMacOnboardingView(
                        title: String(localized: "pairing.onboarding.title", defaultValue: "先连接你的 Mac"),
                        message: String(localized: "pairing.onboarding.message", defaultValue: "配对完成后，你就可以在手机或 iPad 上查看终端、Claude 会话、文件与审批请求。"),
                        highlights: [
                            String(localized: "pairing.onboarding.highlight.agent", defaultValue: "随时处理 Agent 审批与任务状态"),
                            String(localized: "pairing.onboarding.highlight.terminal", defaultValue: "查看终端、文件与浏览器 surface"),
                            String(localized: "pairing.onboarding.highlight.chat", defaultValue: "继续 Claude Code 对话，不必回到电脑前")
                        ]
                    )
                    .environmentObject(relayConnection)
                } else if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad：使用 NavigationSplitView 侧栏 + 详情
                    iPadSplitView
                } else {
                    // iPhone：使用 TabView
                    iPhoneTabView
                }
            }
            .preferredColorScheme(appTheme.colorScheme)
            .onChange(of: scenePhase) { _, newPhase in
                // 从后台回到前台：清理过期 snapshot，避免长期常驻的累积
                if newPhase == .active {
                    messageStore.pruneStaleSnapshots()
                    hasPairedDevice = DeviceStore.hasPairedDevice()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .deviceStoreDidChange)) { _ in
                hasPairedDevice = DeviceStore.hasPairedDevice()
            }
            .onAppear {
                // 注册 Nerd Font
                FontLoader.registerFonts()

                // 注入 approvalManager 到 messageStore
                messageStore.approvalManager = approvalManager
                approvalManager.loadPolicy()

                // 连接消息管道：relay 收到消息 → messageStore 处理
                relayConnection.onMessage = { [weak messageStore] data in
                    Task { @MainActor in
                        messageStore?.processRawMessage(data)
                    }
                }

                // surface 列表更新回调：直接解码并更新 messageStore
                relayConnection.onSurfacesUpdated = { [weak messageStore] surfaceDicts in
                    Task { @MainActor in
                        let decoded = surfaceDicts.compactMap { dict -> Surface? in
                            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                                  let surface = try? JSONDecoder().decode(Surface.self, from: data) else { return nil }
                            return surface
                        }
                        print("[app] 更新 surfaces: \(decoded.count) 个")
                        messageStore?.surfaces = decoded
                    }
                }

                // Claude 推送事件：MessageStore → RelayConnection → ClaudeChatView
                messageStore.onClaudeUpdate = { [weak relayConnection] payload in
                    relayConnection?.dispatchClaudeUpdate(payload)
                }

                // 初始化推送通知
                PushNotificationManager.shared.relayConnection = relayConnection
                if AppFeatureFlags.notificationsEnabled {
                    PushNotificationManager.shared.requestAuthorization()
                    LiveActivityManager.shared.onPushTokenUpdate = { token in
                        Task { @MainActor in
                            PushNotificationManager.shared.reportLiveActivityToken(token)
                        }
                    }
                } else {
                    LiveActivityManager.shared.onPushTokenUpdate = nil
                }

                // 如果已配对，自动连接
                autoConnectIfPaired()
            }
        }
    }

    // MARK: - iPhone TabView 布局

    @State private var selectedTab: Int = 0

    private var iPhoneTabView: some View {
        VStack(spacing: 0) {
            // 连接状态指示条
            ConnectionStatusBar()
                .environmentObject(relayConnection)

            TabView(selection: $selectedTab) {
                // Agent Tab（第一个）
                AgentDashboard()
                    .environmentObject(approvalManager)
                    .environmentObject(relayConnection)
                    .environmentObject(activityStore)
                    .tabItem {
                        Label(
                            String(localized: "tab.agent", defaultValue: "Agent"),
                            systemImage: "cpu"
                        )
                    }
                    .badge(approvalManager.pendingRequests.count)
                    .tag(0)

                // 终端列表 Tab
                TerminalListView()
                    .tabItem {
                        Label(
                            String(localized: "tab.terminal", defaultValue: "终端"),
                            systemImage: "terminal"
                        )
                    }
                    .environmentObject(messageStore)
                    .environmentObject(relayConnection)
                    .environmentObject(inputManager)
                    .environmentObject(sessionManager)
                    .environmentObject(approvalManager)
                    .tag(1)

                // 文件浏览器 Tab
                FileExplorerView()
                    .environmentObject(relayConnection)
                    .environmentObject(messageStore)
                    .tabItem {
                        Label(
                            String(localized: "tab.files", defaultValue: "文件"),
                            systemImage: "folder"
                        )
                    }
                    .tag(2)

                // 设置 Tab
                SettingsView()
                    .environmentObject(relayConnection)
                    .environmentObject(messageStore)
                    .environmentObject(approvalManager)
                    .tabItem {
                        Label(
                            String(localized: "tab.settings", defaultValue: "设置"),
                            systemImage: "gear"
                        )
                    }
                    .tag(3)
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
    }

    // MARK: - 自动连接

    /// 如果已配对（DeviceStore 中有活跃设备），自动发起 WebSocket 连接
    private func autoConnectIfPaired() {
        #if canImport(Security)
        // 调试：检查设备存储状态
        let devices = DeviceStore.getDevices()
        let activeDevice = DeviceStore.getActiveDevice()
        print("[autoConnect] 设备数=\(devices.count) 活跃设备=\(activeDevice?.name ?? "nil")")

        // 兜底：如果 DeviceStore 为空，尝试用旧的 Keychain 数据直接连接
        if activeDevice == nil {
            if let deviceID = KeychainHelper.load(key: "pairedDeviceID"),
               let serverURL = KeychainHelper.load(key: "pairedServerURL"),
               let pairSecret = KeychainHelper.load(key: "pairSecret_\(deviceID)") {
                print("[autoConnect] 使用旧版凭据连接: \(deviceID)")
                let phoneID = KeychainHelper.load(key: "phoneID") ?? "phone-unknown"
                relayConnection.serverURL = serverURL
                relayConnection.phoneID = phoneID
                relayConnection.pairSecret = pairSecret
                relayConnection.connect()
                return
            }
            print("[autoConnect] 无任何配对凭据")
            return
        }

        guard let activeDevice else { return }

        // 获取或生成 phoneID
        let phoneID = KeychainHelper.load(key: "phoneID") ?? {
            let newID = "phone-" + UUID().uuidString.prefix(8).lowercased()
            try? KeychainHelper.save(key: "phoneID", value: newID)
            return newID
        }()

        relayConnection.serverURL = activeDevice.serverURL
        relayConnection.phoneID = phoneID
        relayConnection.pairSecret = activeDevice.pairSecret
        relayConnection.connect()

        DeviceStore.updateLastConnected(id: activeDevice.id)
        #endif
    }

    // MARK: - iPad NavigationSplitView 布局

    private var iPadSplitView: some View {
        iPadSplitViewContent()
            .environmentObject(messageStore)
            .environmentObject(relayConnection)
            .environmentObject(inputManager)
            .environmentObject(approvalManager)
            .environmentObject(sessionManager)
            .environmentObject(activityStore)
    }
}

// MARK: - iPad SplitView 内容（独立 View，避免泛型嵌套问题）

/// iPad 自适应分栏视图：侧栏（Agent / 终端 / 文件 / 设置）+ 详情区
private struct iPadSplitViewContent: View {
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var relayConnection: RelayConnection
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var approvalManager: ApprovalManager
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var activityStore: ActivityStore

    /// 当前选中的侧栏项
    @State private var selectedTab: SidebarTab? = .agent

    enum SidebarTab: String, CaseIterable, Identifiable {
        case agent
        case terminal
        case files
        case settings

        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .agent: return "Agent"
            case .terminal: return "终端"
            case .files: return "文件"
            case .settings: return "设置"
            }
        }

        var systemImage: String {
            switch self {
            case .agent: return "cpu"
            case .terminal: return "terminal"
            case .files: return "folder"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebarList
                .navigationTitle(String(localized: "sidebar.title", defaultValue: "cmux"))
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detailView
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - 侧栏

    private var sidebarList: some View {
        List(SidebarTab.allCases, selection: $selectedTab) { tab in
            Label(tab.label, systemImage: tab.systemImage)
                .tag(tab)
        }
        .listStyle(.sidebar)
    }

    // MARK: - 详情区

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .agent:
            AgentDashboard()
                .environmentObject(approvalManager)
                .environmentObject(relayConnection)
                .environmentObject(activityStore)

        case .terminal:
            TerminalListView()
                .environmentObject(messageStore)
                .environmentObject(relayConnection)
                .environmentObject(inputManager)
                .environmentObject(sessionManager)
                .environmentObject(approvalManager)

        case .files:
            FileExplorerView()
                .environmentObject(relayConnection)
                .environmentObject(messageStore)

        case .settings:
            SettingsView()
                .environmentObject(relayConnection)
                .environmentObject(messageStore)
                .environmentObject(approvalManager)

        case nil:
            // 未选中时的占位视图
            Text(String(localized: "sidebar.select_item", defaultValue: "请从左侧选择功能"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
