import Foundation

enum ClaudeHistoryFetchKind: Equatable {
    case incremental
    case recentPage
    case pageBefore(Int)
    case fullRefreshLegacy
}

struct ClaudeHistoryPagingState: Equatable {
    var hasMoreRemoteHistory = false
    var nextBeforeSeq: Int?

    /// 重置分页状态到「认为仍有更多远端历史、游标未知」的初始态
    /// 通常在 claude.session.reset 事件处理中调用
    mutating func reset() {
        hasMoreRemoteHistory = true
        nextBeforeSeq = nil
    }

    mutating func bootstrapFromCache(
        hasCompleteHistory: Bool,
        cachedHasSeqMetadata: Bool,
        oldestLoadedSeq: Int?
    ) {
        nextBeforeSeq = oldestLoadedSeq

        if hasCompleteHistory {
            hasMoreRemoteHistory = false
        } else {
            hasMoreRemoteHistory = cachedHasSeqMetadata || oldestLoadedSeq != nil
        }
    }

    mutating func applyResponse(
        fetchKind: ClaudeHistoryFetchKind,
        hasMore: Bool?,
        serverNextBeforeSeq: Int?,
        fallbackOldestLoadedSeq: Int?
    ) {
        if let hasMore {
            hasMoreRemoteHistory = hasMore
        }

        if let serverNextBeforeSeq, serverNextBeforeSeq > 0 {
            nextBeforeSeq = serverNextBeforeSeq
        } else if fetchKind != .incremental {
            nextBeforeSeq = fallbackOldestLoadedSeq
        }
    }

    func nextPageCursor(fallbackOldestLoadedSeq: Int?) -> Int? {
        nextBeforeSeq ?? fallbackOldestLoadedSeq
    }
}
