import Testing
@testable import cmux_core

@Suite("ClaudeHistoryPagingState Tests")
struct ClaudeHistoryPagingStateTests {
    @Test("完整缓存不会继续向服务端翻页")
    func bootstrapCompleteHistory() {
        var state = ClaudeHistoryPagingState()
        state.bootstrapFromCache(
            hasCompleteHistory: true,
            cachedHasSeqMetadata: true,
            oldestLoadedSeq: 41
        )

        #expect(state.hasMoreRemoteHistory == false)
        #expect(state.nextBeforeSeq == 41)
    }

    @Test("不完整缓存优先使用服务端返回的上一页游标")
    func responsePrefersServerCursor() {
        var state = ClaudeHistoryPagingState()
        state.bootstrapFromCache(
            hasCompleteHistory: false,
            cachedHasSeqMetadata: true,
            oldestLoadedSeq: 80
        )

        state.applyResponse(
            fetchKind: .recentPage,
            hasMore: true,
            serverNextBeforeSeq: 61,
            fallbackOldestLoadedSeq: 80
        )

        #expect(state.hasMoreRemoteHistory == true)
        #expect(state.nextBeforeSeq == 61)
        #expect(state.nextPageCursor(fallbackOldestLoadedSeq: 80) == 61)
    }

    @Test("服务端未返回游标时分页请求回退到本地最早 seq")
    func responseFallsBackToOldestSeqForPagingRequests() {
        var state = ClaudeHistoryPagingState()
        state.applyResponse(
            fetchKind: .pageBefore(120),
            hasMore: false,
            serverNextBeforeSeq: nil,
            fallbackOldestLoadedSeq: 19
        )

        #expect(state.hasMoreRemoteHistory == false)
        #expect(state.nextBeforeSeq == 19)
    }

    @Test("增量请求不会覆盖现有上一页游标")
    func incrementalResponseKeepsExistingCursor() {
        var state = ClaudeHistoryPagingState(
            hasMoreRemoteHistory: true,
            nextBeforeSeq: 33
        )

        state.applyResponse(
            fetchKind: .incremental,
            hasMore: false,
            serverNextBeforeSeq: nil,
            fallbackOldestLoadedSeq: 12
        )

        #expect(state.hasMoreRemoteHistory == false)
        #expect(state.nextBeforeSeq == 33)
        #expect(state.nextPageCursor(fallbackOldestLoadedSeq: 12) == 33)
    }
}
