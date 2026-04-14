import SwiftUI

/// 主题设置：系统 / 浅色 / 深色
struct ThemeSettingsView: View {
    @AppStorage("appTheme") private var appTheme: String = "system"
    /// 切换后短暂显示的确认 toast（1.2s 自动消失）
    @State private var confirmation: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        List {
            Section(
                header: Text(String(localized: "settings.theme.section_header", defaultValue: "外观模式")),
                footer: Text(String(localized: "settings.theme.section_footer", defaultValue: "选择「跟随系统」将自动适配设备的浅色/深色模式。"))
            ) {
                ForEach(ThemeOption.allCases) { option in
                    Button {
                        guard appTheme != option.rawValue else { return }
                        appTheme = option.rawValue
                        showConfirmation(option.displayName)
                    } label: {
                        HStack {
                            Label(option.displayName, systemImage: option.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appTheme == option.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .accessibilityLabel(option.displayName)
                    .accessibilityHint(String(
                        localized: "settings.theme.tap_hint",
                        defaultValue: "切换到\(option.displayName)"
                    ))
                }
            }
        }
        .navigationTitle(String(localized: "settings.theme.title", defaultValue: "主题"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let text = confirmation {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(
                        localized: "settings.theme.confirmed",
                        defaultValue: "已切换到\(text)"
                    ))
                    .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onDisappear { toastTask?.cancel() }
    }

    private func showConfirmation(_ name: String) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { confirmation = name }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { confirmation = nil }
        }
    }
}

// MARK: - 主题选项

private enum ThemeOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "settings.theme.system", defaultValue: "跟随系统")
        case .light:
            return String(localized: "settings.theme.light", defaultValue: "浅色")
        case .dark:
            return String(localized: "settings.theme.dark", defaultValue: "深色")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}
