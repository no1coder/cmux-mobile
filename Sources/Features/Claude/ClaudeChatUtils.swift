import SwiftUI

/// 辅助任务袋：聊天视图生命周期内派生的 Task 统一登记，视图销毁时 deinit 自动取消
/// 用于替代 DispatchQueue.main.asyncAfter（闭包强引用 self 且无法取消）
@MainActor
final class ViewTaskBag: ObservableObject {
    private var tasks: Set<UUID> = []
    private var store: [UUID: Task<Void, Never>] = [:]

    /// 注册一个异步任务；返回句柄 id 以便外部取消
    @discardableResult
    func add(_ task: Task<Void, Never>) -> UUID {
        let id = UUID()
        tasks.insert(id)
        store[id] = task
        return id
    }

    /// 延迟执行（带自动取消），替代 DispatchQueue.main.asyncAfter
    func runAfter(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        let t = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
        add(t)
    }

    func cancel(_ id: UUID) {
        store[id]?.cancel()
        store.removeValue(forKey: id)
        tasks.remove(id)
    }

    func cancelAll() {
        for (_, t) in store { t.cancel() }
        store.removeAll()
        tasks.removeAll()
    }

    deinit {
        for (_, t) in store { t.cancel() }
    }
}

extension Array where Element == ClaudeChatItem {
    /// 按 timestamp 升序稳定排序：时间戳相同的消息保持原有相对顺序
    /// 用于合并 WS 推送 / 轮询 / 文件监听多路数据源时，避免末尾不是最新
    /// 快路径：若数组已按 timestamp 非递减，直接返回 self 避免 O(n log n) 成本
    func sortedByTimestampStable() -> [ClaudeChatItem] {
        if count < 2 { return self }
        var alreadySorted = true
        for i in 1..<count {
            if self[i - 1].timestamp > self[i].timestamp {
                alreadySorted = false
                break
            }
        }
        if alreadySorted { return self }
        // 慢路径：有乱序，稳定排序
        return enumerated()
            .sorted { lhs, rhs in
                if lhs.element.timestamp == rhs.element.timestamp {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.timestamp < rhs.element.timestamp
            }
            .map(\.element)
    }
}
