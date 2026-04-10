import Foundation

/// 基于 requestId 的 RPC 去重缓存，防止网络重试导致重复执行
/// 60 秒 TTL，过期后允许重发
final class RpcDedupCache {
    private var sentIds: [String: Date] = [:]
    private let ttlSeconds: TimeInterval

    init(ttlSeconds: TimeInterval = 60) {
        self.ttlSeconds = ttlSeconds
    }

    /// 检查是否应发送此请求（未见过或已过期则返回 true）
    func shouldSend(_ requestId: String) -> Bool {
        cleanupExpired()
        if sentIds[requestId] != nil {
            return false
        }
        sentIds[requestId] = Date()
        return true
    }

    /// 清理过期的请求记录
    func cleanupExpired() {
        let cutoff = Date().addingTimeInterval(-ttlSeconds)
        sentIds = sentIds.filter { $0.value > cutoff }
    }

    /// 清空全部记录（断连重置时使用）
    func reset() {
        sentIds.removeAll()
    }
}
