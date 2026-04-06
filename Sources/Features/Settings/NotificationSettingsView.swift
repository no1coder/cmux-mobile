import SwiftUI

/// 推送通知设置视图，用户可以配置推送通知偏好
struct NotificationSettingsView: View {
    @AppStorage("push_approval") private var pushApproval = true
    @AppStorage("push_task_complete") private var pushTaskComplete = true
    @AppStorage("push_task_failed") private var pushTaskFailed = true
    @AppStorage("push_terminal_exit") private var pushTerminalExit = false

    var body: some View {
        List {
            Section(
                header: Text(String(localized: "settings.notifications.title", defaultValue: "推送通知")),
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
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle(String(localized: "settings.notifications.nav_title", defaultValue: "通知设置"))
    }
}

#if DEBUG
struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NotificationSettingsView()
        }
    }
}
#endif
