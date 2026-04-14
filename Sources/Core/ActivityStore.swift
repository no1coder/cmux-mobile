import Combine
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
    /// 同一 type+title+detail 的重复记录在此时间窗内被去重，避免短时间刷屏
    /// 例如 Mac 端抖动产生的重复通知
    private let dedupeWindow: TimeInterval = 3

    /// 添加一条活动记录（环形缓冲区，超过上限丢弃最旧的）
    func add(type: ActivityType, title: String, detail: String = "") {
        // 去重：如果最近 dedupeWindow 秒内已有完全相同的记录，跳过
        let now = Date()
        if let last = items.first,
           last.type == type,
           last.title == title,
           last.detail == detail,
           now.timeIntervalSince(last.timestamp) < dedupeWindow {
            return
        }
        let item = ActivityItem(
            type: type,
            title: title,
            detail: detail,
            timestamp: now
        )
        let updated = [item] + items
        items = updated.count > maxItems ? Array(updated.prefix(maxItems)) : updated
    }

    /// 清空全部活动日志（供设置页调用）
    func clearAll() {
        items = []
    }
}

extension ActivityStore.ActivityType: Equatable {}
