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

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        storageURL = dir.appendingPathComponent("offline-queue.json")
        queue = Self.loadFromDisk(url: storageURL)
        pendingCount = queue.count
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
        // 仅序列化 JSON-safe 字典；过滤掉含 NSNull/NSDate 等非 JSON 类型的条目
        let safe = queue.filter { JSONSerialization.isValidJSONObject($0) }
        do {
            let data = try JSONSerialization.data(withJSONObject: safe, options: [])
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[offlineQueue] 持久化失败: \(error.localizedDescription)")
        }
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
