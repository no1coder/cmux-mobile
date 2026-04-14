import Combine
import Foundation

/// Tracks the newest in-flight request per logical key so stale callbacks can be ignored.
@MainActor
final class LatestOnlyRequestGate: ObservableObject {
    private var latestTokens: [String: Int] = [:]

    @discardableResult
    func begin(_ key: String) -> Int {
        let next = (latestTokens[key] ?? 0) + 1
        latestTokens[key] = next
        return next
    }

    func isLatest(_ token: Int, for key: String) -> Bool {
        latestTokens[key] == token
    }
}
