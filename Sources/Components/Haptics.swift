import UIKit

/// 触感反馈工具 — 为不同交互类型提供对应的触感
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    /// 轻触 — 导航、选择、列表滑动
    static func light() { lightGenerator.impactOccurred() }

    /// 中等 — 按钮点击、选择器
    static func medium() { mediumGenerator.impactOccurred() }

    /// 重触 — 发送消息、启动会话等郑重操作
    static func rigid() { rigidGenerator.impactOccurred() }

    /// 成功 — 配对成功、审批通过
    static func success() { notificationGenerator.notificationOccurred(.success) }

    /// 警告 — 破坏性操作确认前
    static func warning() { notificationGenerator.notificationOccurred(.warning) }

    /// 错误 — 操作失败
    static func error() { notificationGenerator.notificationOccurred(.error) }

    /// 选择 — tab 切换、分段控件
    static func selection() { selectionGenerator.selectionChanged() }
}
