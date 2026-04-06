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
            TabView {
                // 将 approvalManager 注入 messageStore（通过 onAppear 确保 StateObject 已初始化）
                let _ = {
                    messageStore.approvalManager = approvalManager
                }()
                // Agent Dashboard Tab（第一个）
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

                // 设置 Tab
                NavigationStack {
                    List {
                        // Relay 连接状态部分
                        Section(header: Text(String(localized: "tab.settings.relay", defaultValue: "Relay 连接"))) {
                            ConnectionStatusBadge(
                                status: relayConnection.status,
                                latencyMs: relayConnection.latencyMs
                            )
                        }

                        // 通知设置链接
                        NavigationLink(
                            destination: NotificationSettingsView()
                        ) {
                            Label(
                                String(localized: "settings.notifications.nav_title", defaultValue: "通知设置"),
                                systemImage: "bell.fill"
                            )
                        }
                    }
                    .navigationTitle(
                        String(localized: "tab.settings", defaultValue: "设置")
                    )
                }
                .tabItem {
                    Label(
                        String(localized: "tab.settings", defaultValue: "设置"),
                        systemImage: "gear"
                    )
                }
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
