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
