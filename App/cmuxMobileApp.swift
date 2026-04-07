import SwiftUI

#if os(iOS)
@main
struct cmuxMobileApp: App {
    @StateObject private var messageStore = MessageStore()
    @StateObject private var relayConnection = RelayConnection()
    @StateObject private var inputManager = InputManager()
    @StateObject private var approvalManager = ApprovalManager()

    var body: some Scene {
        WindowGroup {
            // 将 approvalManager 注入 messageStore
            let _ = {
                messageStore.approvalManager = approvalManager
            }()

            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad：使用 NavigationSplitView 侧栏 + 详情
                iPadSplitView
            } else {
                // iPhone：使用 TabView
                iPhoneTabView
            }
        }
    }

    // MARK: - iPhone TabView 布局

    private var iPhoneTabView: some View {
        TabView {
            // Agent Tab（第一个）
            AgentDashboard()
                .environmentObject(approvalManager)
                .environmentObject(relayConnection)
                .tabItem {
                    Label(
                        String(localized: "tab.agent", defaultValue: "Agent"),
                        systemImage: "cpu"
                    )
                }

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

            // 文件浏览器 Tab
            FileExplorerView()
                .environmentObject(relayConnection)
                .tabItem {
                    Label(
                        String(localized: "tab.files", defaultValue: "文件"),
                        systemImage: "folder"
                    )
                }

            // 设置 Tab
            PairingSettingsView()
                .tabItem {
                    Label(
                        String(localized: "tab.settings", defaultValue: "设置"),
                        systemImage: "gear"
                    )
                }
        }
    }

    // MARK: - iPad NavigationSplitView 布局

    private var iPadSplitView: some View {
        iPadSplitViewContent
            .environmentObject(messageStore)
            .environmentObject(relayConnection)
            .environmentObject(inputManager)
            .environmentObject(approvalManager)
    }
}

// MARK: - iPad SplitView 内容（独立 View，避免泛型嵌套问题）

/// iPad 自适应分栏视图：侧栏（Agent / 终端 / 文件 / 设置）+ 详情区
private struct iPadSplitViewContent: View {
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var relayConnection: RelayConnection
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var approvalManager: ApprovalManager

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
        } detail: {
            detailView
        }
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

        case .terminal:
            TerminalListView()
                .environmentObject(messageStore)
                .environmentObject(relayConnection)
                .environmentObject(inputManager)

        case .files:
            FileExplorerView()
                .environmentObject(relayConnection)

        case .settings:
            PairingSettingsView()

        case nil:
            // 未选中时的占位视图
            Text(String(localized: "sidebar.select_item", defaultValue: "请从左侧选择功能"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#else
/// macOS 构建占位入口（仅供 Swift PM 满足链接需求）
@main
enum cmuxMobileApp {
    static func main() {}
}
#endif
