import Testing
#if canImport(cmux_mobile)
@testable import cmux_mobile
#elseif canImport(cmux_core)
@testable import cmux_core
#endif

@Suite("RelayConnection Tests")
@MainActor
struct RelayConnectionTests {

    private func watchedCounts(_ connection: RelayConnection) -> [String: Int] {
        Mirror(reflecting: connection)
            .children
            .first { $0.label == "watchedClaudeSurfaceCounts" }?
            .value as? [String: Int] ?? [:]
    }

    @Test("sendWithResponse returns offline immediately and does not enqueue")
    func sendWithResponseOfflineFailsFast() {
        let connection = RelayConnection()
        connection.offlineQueue.clear()
        var callbackPayload: [String: Any]?

        connection.sendWithResponse([
            "method": "file.list",
            "params": ["path": "~"]
        ]) { result in
            callbackPayload = result
        }

        #expect(callbackPayload?["error"] as? String == "offline")
        #expect(callbackPayload?["method"] as? String == "file.list")
        #expect(connection.offlineQueue.pendingCount == 0)
    }

    @Test("sendWithResponse waits through connecting before reporting offline")
    func sendWithResponseConnectingDefersFailure() async {
        let connection = RelayConnection()
        connection.offlineQueue.clear()
        var callbackPayload: [String: Any]?

        connection.status = .connecting
        connection.sendWithResponse([
            "method": "file.list",
            "params": ["path": "~"]
        ]) { result in
            callbackPayload = result
        }

        #expect(callbackPayload == nil)

        connection.status = .disconnected
        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(callbackPayload?["error"] as? String == "offline")
        #expect(callbackPayload?["method"] as? String == "file.list")
        #expect(connection.offlineQueue.pendingCount == 0)
    }

    @Test("Claude update observers all receive dispatched payloads")
    func claudeUpdateDispatchNotifiesAllObservers() {
        let connection = RelayConnection()
        var receivedByFirst: [String: Any]?
        var receivedBySecond: [String: Any]?

        let firstID = connection.addClaudeUpdateObserver { payload in
            receivedByFirst = payload
        }
        _ = connection.addClaudeUpdateObserver { payload in
            receivedBySecond = payload
        }

        connection.dispatchClaudeUpdate(["event": "claude.messages.update", "surface_id": "s1"])
        connection.removeClaudeUpdateObserver(firstID)
        connection.dispatchClaudeUpdate(["event": "claude.messages.update", "surface_id": "s2"])

        #expect(receivedByFirst?["surface_id"] as? String == "s1")
        #expect(receivedBySecond?["surface_id"] as? String == "s2")
    }

    @Test("Claude watch reference counting avoids duplicate watch and early unwatch")
    func claudeWatchReferenceCounting() {
        let connection = RelayConnection()

        connection.beginClaudeWatch(surfaceID: "surface-1")
        connection.beginClaudeWatch(surfaceID: "surface-1")
        #expect(watchedCounts(connection)["surface-1"] == 2)

        connection.endClaudeWatch(surfaceID: "surface-1")
        #expect(watchedCounts(connection)["surface-1"] == 1)

        connection.endClaudeWatch(surfaceID: "surface-1")
        #expect(watchedCounts(connection)["surface-1"] == nil)
    }

    @Test("Claude watch state changes do not enqueue while disconnected")
    func claudeWatchDoesNotQueueOfflineCommands() {
        let connection = RelayConnection()
        connection.offlineQueue.clear()

        connection.beginClaudeWatch(surfaceID: "surface-offline")
        connection.endClaudeWatch(surfaceID: "surface-offline")

        #expect(connection.offlineQueue.pendingCount == 0)
    }
}
