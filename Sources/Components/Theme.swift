import SwiftUI

// MARK: - 主题偏好

/// 主题模式：跟随系统 / 亮色 / 暗色
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// 用于 UI 展示的本地化标题
    var title: String {
        switch self {
        case .system:
            return String(localized: "theme.system", defaultValue: "跟随系统")
        case .light:
            return String(localized: "theme.light", defaultValue: "亮色")
        case .dark:
            return String(localized: "theme.dark", defaultValue: "暗色")
        }
    }

    /// 系统图标名称
    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// 转换为 SwiftUI 的 ColorScheme（system 返回 nil 表示跟随系统）
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 统一颜色系统

/// 使用自适应颜色，自动适配暗色/亮色模式
enum CMColors {
    static let backgroundPrimary = Color(UIColor.systemBackground)
    static let backgroundSecondary = Color(UIColor.secondarySystemBackground)
    static let backgroundTertiary = Color(UIColor.tertiarySystemBackground)
    static let surfaceCard = Color(UIColor.secondarySystemGroupedBackground)
    static let userBubble = Color(red: 0.22, green: 0.42, blue: 0.82)
    static let inputBarBackground = Color(UIColor.secondarySystemBackground)
    static let menuBackground = Color(UIColor.tertiarySystemBackground)
    static let separator = Color(UIColor.separator)
    static let textPrimary = Color(UIColor.label)
    static let textSecondary = Color(UIColor.secondaryLabel)
    static let textTertiary = Color(UIColor.tertiaryLabel)
}
