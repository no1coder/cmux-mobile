import SwiftUI

/// 配对设置视图：展示已配对设备信息，支持解除配对和自托管服务器配置
struct PairingSettingsView: View {

    // MARK: - Keychain 键名

    private static let keyDeviceID = "pairedDeviceID"
    private static let keyServerURL = "pairedServerURL"
    private static let keySelfHostedURL = "selfHostedServerURL"

    // MARK: - 状态

    /// 已配对的设备 ID（从 Keychain 读取）
    @State private var deviceID: String?
    /// 已配对的服务器 URL（从 Keychain 读取）
    @State private var serverURL: String?
    /// 自托管服务器 URL（可编辑）
    @State private var selfHostedURL: String = ""
    /// 是否显示解除配对确认弹窗
    @State private var showUnpairConfirm: Bool = false
    /// 操作结果反馈信息
    @State private var feedbackMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                pairedDeviceSection
                selfHostedSection
            }
            .navigationTitle(String(localized: "settings.pairing.title", defaultValue: "配对设置"))
            .onAppear { loadFromKeychain() }
            .alert(
                String(localized: "settings.pairing.unpair_confirm_title", defaultValue: "解除配对"),
                isPresented: $showUnpairConfirm
            ) {
                Button(
                    String(localized: "settings.pairing.unpair_action", defaultValue: "解除配对"),
                    role: .destructive
                ) {
                    unpair()
                }
                Button(
                    String(localized: "settings.pairing.cancel", defaultValue: "取消"),
                    role: .cancel
                ) {}
            } message: {
                Text(String(
                    localized: "settings.pairing.unpair_confirm_message",
                    defaultValue: "解除配对后，应用将无法连接到此设备，确认继续？"
                ))
            }
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

    // MARK: - Section：已配对设备

    @ViewBuilder
    private var pairedDeviceSection: some View {
        Section(
            header: Text(String(localized: "settings.pairing.device_section", defaultValue: "已配对设备"))
        ) {
            if let id = deviceID, !id.isEmpty {
                // 设备 ID 行
                LabeledContent(
                    String(localized: "settings.pairing.device_id", defaultValue: "设备 ID"),
                    value: id
                )
                .font(.system(.body, design: .monospaced))

                // 服务器 URL 行
                if let url = serverURL, !url.isEmpty {
                    LabeledContent(
                        String(localized: "settings.pairing.server_url", defaultValue: "服务器地址"),
                        value: url
                    )
                }

                // 解除配对按钮
                Button(role: .destructive) {
                    showUnpairConfirm = true
                } label: {
                    Label(
                        String(localized: "settings.pairing.unpair_button", defaultValue: "解除配对"),
                        systemImage: "xmark.circle"
                    )
                    .foregroundStyle(.red)
                }
            } else {
                // 尚未配对提示
                Label(
                    String(localized: "settings.pairing.no_device", defaultValue: "尚未配对任何设备"),
                    systemImage: "link.badge.plus"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Section：自托管服务器

    private var selfHostedSection: some View {
        Section(
            header: Text(String(localized: "settings.pairing.self_hosted_section", defaultValue: "自托管服务器")),
            footer: Text(String(localized: "settings.pairing.self_hosted_footer", defaultValue: "如使用自托管 Relay，请在此填入服务器地址（无需 https://）"))
        ) {
            TextField(
                String(localized: "settings.pairing.self_hosted_placeholder", defaultValue: "例如：relay.example.com"),
                text: $selfHostedURL
            )
            #if os(iOS)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #endif

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

    /// 从 Keychain 加载配对信息
    private func loadFromKeychain() {
        #if canImport(Security)
        deviceID = KeychainHelper.load(key: Self.keyDeviceID)
        serverURL = KeychainHelper.load(key: Self.keyServerURL)
        selfHostedURL = KeychainHelper.load(key: Self.keySelfHostedURL) ?? ""
        #endif
    }

    /// 解除配对：删除 Keychain 中的凭据
    private func unpair() {
        #if canImport(Security)
        if let id = deviceID {
            // 删除配对凭据（pairSecret 和 serverURL 以 deviceID 为后缀存储）
            KeychainHelper.delete(key: "pairSecret_\(id)")
            KeychainHelper.delete(key: "serverURL_\(id)")
        }
        KeychainHelper.delete(key: Self.keyDeviceID)
        KeychainHelper.delete(key: Self.keyServerURL)
        #endif

        deviceID = nil
        serverURL = nil
        showFeedback(String(localized: "settings.pairing.unpaired_success", defaultValue: "已成功解除配对"))
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
