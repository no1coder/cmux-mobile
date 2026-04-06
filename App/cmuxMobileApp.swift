import SwiftUI

#if os(iOS)
@main
struct cmuxMobileApp: App {
    @StateObject private var messageStore = MessageStore()
    @StateObject private var relayConnection = RelayConnection()

    var body: some Scene {
        WindowGroup {
            TabView {
                TerminalListView()
                    .tabItem {
                        Label("终端", systemImage: "terminal")
                    }
                    .environmentObject(messageStore)

                // 连接状态占位 Tab
                NavigationStack {
                    VStack(spacing: 16) {
                        ConnectionStatusBadge(
                            status: relayConnection.status,
                            latencyMs: relayConnection.latencyMs
                        )
                        Text("Relay 连接")
                            .font(.title2)
                    }
                    .navigationTitle("连接")
                }
                .tabItem {
                    Label("连接", systemImage: "wifi")
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
