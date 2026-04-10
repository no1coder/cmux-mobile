import SwiftUI

/// 综合设置中心：替代原来的 PairingSettingsView 作为设置 Tab 入口
struct SettingsView: View {
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 13
    @AppStorage("showTokenUsage") private var showTokenUsage = true
    @AppStorage("autoScrollToBottom") private var autoScrollToBottom = true

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                displaySection
                terminalSection
                chatSection
                approvalSection
                privacySection
                aboutSection
            }
            .navigationTitle(String(localized: "settings.title", defaultValue: "设置"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 连接

    private var connectionSection: some View {
        Section(String(localized: "settings.section.connection", defaultValue: "连接")) {
            NavigationLink {
                PairingSettingsView()
            } label: {
                Label(
                    String(localized: "settings.pairing.title", defaultValue: "设备配对"),
                    systemImage: "qrcode"
                )
            }

            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label(
                    String(localized: "settings.notifications.nav_title", defaultValue: "通知设置"),
                    systemImage: "bell"
                )
            }
        }
    }

    // MARK: - 显示

    private var displaySection: some View {
        Section(String(localized: "settings.section.display", defaultValue: "显示")) {
            NavigationLink {
                ThemeSettingsView()
            } label: {
                Label(
                    String(localized: "settings.theme.title", defaultValue: "主题"),
                    systemImage: "paintbrush"
                )
            }
        }
    }

    // MARK: - 终端

    private var terminalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "settings.font_size", defaultValue: "终端字体大小"))
                    Spacer()
                    Text("\(Int(terminalFontSize)) pt")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $terminalFontSize, in: 6...20, step: 1)
                    .tint(.purple)
            }
        } header: {
            Text(String(localized: "settings.terminal", defaultValue: "终端"))
        }
    }

    // MARK: - 聊天

    private var chatSection: some View {
        Section(String(localized: "settings.section.chat", defaultValue: "聊天")) {
            Toggle(
                String(localized: "settings.chat.auto_scroll", defaultValue: "自动滚动到底部"),
                isOn: $autoScrollToBottom
            )

            Toggle(
                String(localized: "settings.chat.show_token_usage", defaultValue: "显示 Token 用量"),
                isOn: $showTokenUsage
            )
        }
    }

    // MARK: - 审批

    private var approvalSection: some View {
        Section(String(localized: "settings.section.approval", defaultValue: "审批")) {
            NavigationLink {
                ApprovalPolicySettingsView()
            } label: {
                Label(
                    String(localized: "settings.approval.title", defaultValue: "审批策略"),
                    systemImage: "checkmark.shield"
                )
            }
        }
    }

    // MARK: - 隐私与安全

    private var privacySection: some View {
        Section(String(localized: "settings.section.privacy", defaultValue: "隐私与安全")) {
            HStack {
                Label(
                    String(localized: "settings.privacy.e2e", defaultValue: "E2E 加密"),
                    systemImage: "lock.shield.fill"
                )
                Spacer()
                Text(String(localized: "settings.privacy.enabled", defaultValue: "已启用"))
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section(String(localized: "settings.section.about", defaultValue: "关于")) {
            HStack {
                Label(
                    String(localized: "settings.about.version", defaultValue: "版本"),
                    systemImage: "info.circle"
                )
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://github.com/manaflow-ai/cmux-mobile")!) {
                Label(
                    String(localized: "settings.about.github", defaultValue: "GitHub 开源仓库"),
                    systemImage: "link"
                )
            }
        }
    }

    // MARK: - 辅助

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
