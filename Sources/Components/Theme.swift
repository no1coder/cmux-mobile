import SwiftUI

// 统一颜色系统，避免硬编码颜色值散落各文件
enum CMColors {
    static let backgroundPrimary = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let backgroundSecondary = Color(white: 0.1)
    static let backgroundTertiary = Color(white: 0.12)
    static let surfaceCard = Color(white: 0.08)
    static let userBubble = Color(red: 0.22, green: 0.42, blue: 0.82)
    static let inputBarBackground = Color(red: 0.08, green: 0.08, blue: 0.1)
    static let menuBackground = Color(red: 0.1, green: 0.1, blue: 0.12)
    static let separator = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.9)
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.3)
}
