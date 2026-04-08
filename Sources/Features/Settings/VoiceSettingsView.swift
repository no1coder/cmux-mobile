import SwiftUI
import Speech

/// 语音输入设置：语言、自动标点、权限状态
struct VoiceSettingsView: View {
    @AppStorage("voiceLanguage") private var voiceLanguage: String = "zh-Hans"
    @AppStorage("voiceAutoPunctuation") private var autoPunctuation = true
    @State private var speechPermission: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @State private var micPermission: AVAudioSession.RecordPermission = .undetermined

    var body: some View {
        List {
            languageSection
            optionsSection
            permissionSection
        }
        .navigationTitle(String(localized: "settings.voice.title", defaultValue: "语音输入设置"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshPermissions() }
    }

    // MARK: - 语言选择

    private var languageSection: some View {
        Section(String(localized: "settings.voice.language_section", defaultValue: "识别语言")) {
            ForEach(VoiceLanguageOption.allCases) { option in
                Button {
                    voiceLanguage = option.localeIdentifier
                } label: {
                    HStack {
                        Text(option.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if voiceLanguage == option.localeIdentifier {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 选项

    private var optionsSection: some View {
        Section(String(localized: "settings.voice.options_section", defaultValue: "选项")) {
            Toggle(
                String(localized: "settings.voice.auto_punctuation", defaultValue: "自动标点"),
                isOn: $autoPunctuation
            )
        }
    }

    // MARK: - 权限状态

    private var permissionSection: some View {
        Section(
            header: Text(String(localized: "settings.voice.permission_section", defaultValue: "权限状态")),
            footer: Text(String(localized: "settings.voice.permission_footer", defaultValue: "语音识别需要麦克风和语音识别两项权限。"))
        ) {
            permissionRow(
                title: String(localized: "settings.voice.speech_permission", defaultValue: "语音识别"),
                granted: speechPermission == .authorized
            )

            permissionRow(
                title: String(localized: "settings.voice.mic_permission", defaultValue: "麦克风"),
                granted: micPermission == .granted
            )

            if speechPermission == .denied || micPermission == .denied {
                Button(String(localized: "settings.voice.open_settings", defaultValue: "前往系统设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - 辅助

    private func permissionRow(title: String, granted: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(granted
                ? String(localized: "settings.voice.granted", defaultValue: "已授权")
                : String(localized: "settings.voice.denied", defaultValue: "未授权"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshPermissions() {
        speechPermission = SFSpeechRecognizer.authorizationStatus()
        micPermission = AVAudioSession.sharedInstance().recordPermission
    }
}

// MARK: - 语言选项

private enum VoiceLanguageOption: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en-US"
    case japanese = "ja-JP"

    var id: String { rawValue }

    var localeIdentifier: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }
}
