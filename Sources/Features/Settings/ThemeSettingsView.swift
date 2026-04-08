import SwiftUI

/// 主题设置：系统 / 浅色 / 深色
struct ThemeSettingsView: View {
    @AppStorage("appTheme") private var appTheme: String = "system"

    var body: some View {
        List {
            Section(
                header: Text(String(localized: "settings.theme.section_header", defaultValue: "外观模式")),
                footer: Text(String(localized: "settings.theme.section_footer", defaultValue: "选择「跟随系统」将自动适配设备的浅色/深色模式。"))
            ) {
                ForEach(ThemeOption.allCases) { option in
                    Button {
                        appTheme = option.rawValue
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
                }
            }
        }
        .navigationTitle(String(localized: "settings.theme.title", defaultValue: "主题"))
        .navigationBarTitleDisplayMode(.inline)
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
