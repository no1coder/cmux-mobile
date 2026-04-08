import Foundation

/// 活动日志存储 — 记录审批、任务完成、错误等事件
@MainActor
final class ActivityStore: ObservableObject {

    struct ActivityItem: Identifiable {
        let id = UUID()
        let type: ActivityType
        let title: String
        let detail: String
        let timestamp: Date
    }

    enum ActivityType {
        case approval
        case taskComplete
        case taskFailed
        case info

        /// 对应的 SF Symbols 图标
        var icon: String {
            switch self {
            case .approval: return "checkmark.shield"
            case .taskComplete: return "checkmark.circle.fill"
            case .taskFailed: return "xmark.circle.fill"
            case .info: return "info.circle"
            }
        }
    }

    @Published var items: [ActivityItem] = []
    private let maxItems = 100

    /// 添加一条活动记录（环形缓冲区，超过上限丢弃最旧的）
    func add(type: ActivityType, title: String, detail: String = "") {
        let item = ActivityItem(
            type: type,
            title: title,
            detail: detail,
            timestamp: Date()
        )
        let updated = [item] + items
        items = updated.count > maxItems ? Array(updated.prefix(maxItems)) : updated
    }
}
