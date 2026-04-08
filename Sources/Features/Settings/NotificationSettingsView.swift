import SwiftUI

/// 推送通知设置视图
struct NotificationSettingsView: View {
    @ObservedObject private var pushManager = PushNotificationManager.shared
    @AppStorage("push_approval") private var pushApproval = true
    @AppStorage("push_task_complete") private var pushTaskComplete = true
    @AppStorage("push_task_failed") private var pushTaskFailed = true
    @AppStorage("push_terminal_exit") private var pushTerminalExit = false

    var body: some View {
        List {
            // 推送权限状态
            Section {
                HStack {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle)
                            .font(.system(size: 15, weight: .medium))
                        Text(statusDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if pushManager.authorizationStatus == .denied {
                        Button("设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 13))
                    }
                }
            }

            // 通知类型开关
            Section(
                header: Text(String(localized: "settings.notifications.title", defaultValue: "通知类型")),
                footer: Text(String(localized: "settings.notifications.footer", defaultValue: "推送通知只包含摘要信息，不包含终端内容。"))
            ) {
                Toggle(
                    String(localized: "settings.notifications.approval", defaultValue: "权限审批请求"),
                    isOn: $pushApproval
                )

                Toggle(
                    String(localized: "settings.notifications.task_complete", defaultValue: "任务完成"),
                    isOn: $pushTaskComplete
                )

                Toggle(
                    String(localized: "settings.notifications.task_failed", defaultValue: "任务失败"),
                    isOn: $pushTaskFailed
                )

                Toggle(
                    String(localized: "settings.notifications.terminal_exit", defaultValue: "终端退出"),
                    isOn: $pushTerminalExit
                )
            }
            .disabled(pushManager.authorizationStatus != .authorized)

            // Device Token 信息（调试）
            if let token = pushManager.deviceToken {
                Section(header: Text("Device Token")) {
                    Text(token.prefix(32) + "...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle(String(localized: "settings.notifications.nav_title", defaultValue: "通知设置"))
        .onAppear {
            pushManager.refreshAuthorizationStatus()
        }
    }

    // MARK: - 状态显示

    private var statusIcon: String {
        switch pushManager.authorizationStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .provisional: return "bell.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch pushManager.authorizationStatus {
        case .authorized: return .green
        case .denied: return .red
        case .provisional: return .orange
        default: return .gray
        }
    }

    private var statusTitle: String {
        switch pushManager.authorizationStatus {
        case .authorized: return "推送已启用"
        case .denied: return "推送被拒绝"
        case .provisional: return "临时授权"
        case .notDetermined: return "未设置"
        default: return "未知"
        }
    }

    private var statusDescription: String {
        switch pushManager.authorizationStatus {
        case .authorized: return "将在 Claude 需要审批或任务完成时通知你"
        case .denied: return "请在系统设置中允许推送通知"
        case .notDetermined: return "首次打开时会请求推送权限"
        default: return ""
        }
    }
}
