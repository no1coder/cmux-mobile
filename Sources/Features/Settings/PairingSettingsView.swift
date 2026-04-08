import SwiftUI

/// 配对设置视图：展示已配对设备列表，支持扫码配对、解除配对和自托管服务器配置
struct PairingSettingsView: View {
    @EnvironmentObject var relayConnection: RelayConnection

    // MARK: - Keychain 键名

    private static let keySelfHostedURL = "selfHostedServerURL"

    /// 默认中继服务器地址
    static let defaultServerURL = "cmux.rooyun.com"

    // MARK: - 状态

    /// 主题偏好
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.dark.rawValue
    /// 自托管服务器 URL（可编辑）
    @State private var selfHostedURL: String = ""
    /// 操作结果反馈信息
    @State private var feedbackMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 设备列表（带自己的 List 和空状态）
                DeviceListView()
                    .environmentObject(relayConnection)

                // 主题与自托管服务器配置区域
                Form {
                    themeSection
                    selfHostedSection
                }
                .frame(maxHeight: 320)
            }
            .navigationTitle(String(localized: "settings.pairing.title", defaultValue: "配对设置"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadSelfHostedURL() }
            .safeAreaInset(edge: .bottom) {
                if let msg = feedbackMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: feedbackMessage)
        }
    }

    // MARK: - Section：主题设置

    private var themeSection: some View {
        Section(
            header: Text(String(
                localized: "settings.theme.title",
                defaultValue: "外观主题"
            ))
        ) {
            Picker(
                String(localized: "settings.theme.picker", defaultValue: "主题"),
                selection: $appThemeRaw
            ) {
                ForEach(AppTheme.allCases) { theme in
                    Label(theme.title, systemImage: theme.systemImage)
                        .tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Section：自托管服务器

    private var selfHostedSection: some View {
        Section(
            header: Text(String(
                localized: "settings.pairing.self_hosted_section",
                defaultValue: "自托管服务器"
            )),
            footer: Text(String(
                localized: "settings.pairing.self_hosted_footer",
                defaultValue: "如使用自托管 Relay，请在此填入服务器地址（无需 https://）"
            ))
        ) {
            TextField(
                String(
                    localized: "settings.pairing.self_hosted_placeholder",
                    defaultValue: "例如：relay.example.com"
                ),
                text: $selfHostedURL
            )
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            Button {
                saveSelfHostedURL()
            } label: {
                Label(
                    String(localized: "settings.pairing.save_url", defaultValue: "保存地址"),
                    systemImage: "checkmark.circle"
                )
            }
        }
    }

    // MARK: - Keychain 操作

    /// 加载自托管服务器地址
    private func loadSelfHostedURL() {
        #if canImport(Security)
        selfHostedURL = KeychainHelper.load(key: Self.keySelfHostedURL) ?? Self.defaultServerURL
        #endif
    }

    /// 保存自托管服务器地址
    private func saveSelfHostedURL() {
        #if canImport(Security)
        let url = selfHostedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            KeychainHelper.delete(key: Self.keySelfHostedURL)
        } else {
            try? KeychainHelper.save(key: Self.keySelfHostedURL, value: url)
        }
        #endif
        showFeedback(String(localized: "settings.pairing.url_saved", defaultValue: "服务器地址已保存"))
    }

    /// 显示反馈消息并在 2 秒后自动隐藏
    private func showFeedback(_ message: String) {
        feedbackMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            feedbackMessage = nil
        }
    }
}
