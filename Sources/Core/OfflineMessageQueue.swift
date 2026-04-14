import Combine
import Foundation

/// 离线消息队列：断线时缓存消息，重连后按序发送
/// 持久化：每次入队/出队都写入 Documents/offline-queue.json，
/// 保证 App 被杀掉后还能在下次启动时续发
@MainActor
final class OfflineMessageQueue: ObservableObject {
    /// 队列中待发送的消息
    @Published private(set) var pendingCount: Int = 0

    private var queue: [[String: Any]] = []
    private let maxQueueSize = 100

    /// 持久化文件路径
    private let storageURL: URL

    /// 防抖写盘任务，短时间内多次 enqueue/flush/clear 仅触发一次磁盘写
    private var saveWorkItem: DispatchWorkItem?
    /// 防抖延迟（秒）：与 MessageStore 风格保持一致
    private static let saveDebounceInterval: TimeInterval = 0.2

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.storageURL = dir.appendingPathComponent("offline-queue.json")
        self.queue = Self.loadFromDisk(url: storageURL)
        self.pendingCount = queue.count
    }

    /// 注入式构造：允许测试为每个用例指定隔离的持久化文件路径
    init(storageURL: URL) {
        self.storageURL = storageURL
        self.queue = Self.loadFromDisk(url: storageURL)
        self.pendingCount = queue.count
    }

    /// 入队消息（断线时调用）
    func enqueue(_ message: [String: Any]) {
        guard queue.count < maxQueueSize else { return }
        queue.append(message)
        pendingCount = queue.count
        saveToDisk()
    }

    /// 重连后按序发送排队消息。
    /// 只有当 `send` 明确接受该消息时，才会将其从持久化队列中移除。
    @discardableResult
    func flush(using send: ([String: Any]) -> Bool) -> Int {
        var sentCount = 0

        while let message = queue.first {
            guard send(message) else { break }
            queue.removeFirst()
            sentCount += 1
            pendingCount = queue.count
            saveToDisk()
        }

        return sentCount
    }

    /// 清空队列
    func clear() {
        queue = []
        pendingCount = 0
        saveToDisk()
    }

    var isEmpty: Bool { queue.isEmpty }

    // MARK: - 持久化

    private func saveToDisk() {
        // 在主线程先序列化一份 JSON-safe 快照，避免后台线程访问可变队列
        let safe = queue.filter { JSONSerialization.isValidJSONObject($0) }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: safe, options: [])
        } catch {
            print("[offlineQueue] 序列化失败: \(error.localizedDescription)")
            return
        }

        // 防抖：短时间内多次调用只保留最后一次写盘
        saveWorkItem?.cancel()
        let url = storageURL
        let workItem = DispatchWorkItem {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                print("[offlineQueue] 持久化失败: \(error.localizedDescription)")
            }
        }
        saveWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.saveDebounceInterval,
            execute: workItem
        )
    }

    private static func loadFromDisk(url: URL) -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return arr
            }
        } catch {
            print("[offlineQueue] 加载失败: \(error.localizedDescription)")
        }
        return []
    }
}
