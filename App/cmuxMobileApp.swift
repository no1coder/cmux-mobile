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
            // 将 approvalManager 注入 messageStore（通过 let _ 确保 StateObject 已初始化）
            let _ = {
                messageStore.approvalManager = approvalManager
            }()
            iPhoneTabView
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
}
#else
/// macOS 构建占位入口（仅供 Swift PM 满足链接需求）
@main
enum cmuxMobileApp {
    static func main() {}
}
#endif
