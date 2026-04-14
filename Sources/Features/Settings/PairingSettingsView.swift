import SwiftUI

/// 配对设置视图：展示已配对设备列表，支持扫码配对、解除配对和自托管服务器配置
struct PairingSettingsView: View {
    @EnvironmentObject var relayConnection: RelayConnection
    var startScanningOnAppear: Bool = false

    // MARK: - 状态

    /// 自托管服务器 URL（可编辑）
    @State private var selfHostedURL: String = ""
    /// 操作结果反馈信息
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var validationMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // 设备列表（带自己的 List 和空状态）
            DeviceListView(startScanningOnAppear: startScanningOnAppear)
                .environmentObject(relayConnection)

            // 自托管服务器配置区域
            Form {
                selfHostedSection
            }
            .frame(maxHeight: 200)
        }
        .navigationTitle(String(localized: "settings.pairing.title", defaultValue: "配对设置"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSelfHostedURL() }
        .safeAreaInset(edge: .bottom) {
            if let msg = feedbackMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(feedbackIsError ? .red : .green)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: feedbackMessage)
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
                defaultValue: "如使用自托管 Relay，请填入服务器地址；可选端口，无需 https://"
            ))
        ) {
            TextField(
                String(
                    localized: "settings.pairing.self_hosted_placeholder",
                    defaultValue: "例如：relay.example.com 或 relay.example.com:8443"
                ),
                text: $selfHostedURL
            )
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

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
        let stored = KeychainHelper.load(key: PairingManager.selfHostedServerKey)
        selfHostedURL = PairingManager.normalizedServerAuthority(stored ?? "") ?? ""
        #endif
    }

    /// 保存自托管服务器地址
    private func saveSelfHostedURL() {
        #if canImport(Security)
        let url = selfHostedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            KeychainHelper.delete(key: PairingManager.selfHostedServerKey)
            validationMessage = nil
            feedbackIsError = false
            selfHostedURL = ""
        } else if let normalized = PairingManager.normalizedServerAuthority(url) {
            try? KeychainHelper.save(key: PairingManager.selfHostedServerKey, value: normalized)
            selfHostedURL = normalized
            validationMessage = nil
            feedbackIsError = false
        } else {
            validationMessage = String(
                localized: "settings.pairing.invalid_host",
                defaultValue: "请输入服务器地址，可选端口，例如 relay.example.com 或 relay.example.com:8443"
            )
            feedbackIsError = true
            showFeedback(String(
                localized: "settings.pairing.invalid_host",
                defaultValue: "请输入服务器地址，可选端口，例如 relay.example.com 或 relay.example.com:8443"
            ))
            return
        }
        #endif
        feedbackIsError = false
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
