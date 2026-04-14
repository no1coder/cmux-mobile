import Testing
#if canImport(cmux_mobile)
@testable import cmux_mobile
#elseif canImport(cmux_core)
@testable import cmux_core
#endif

@Suite("LatestOnlyRequestGate Tests")
@MainActor
struct LatestOnlyRequestGateTests {

    @Test("Only the latest token may update state")
    func latestTokenWins() {
        let gate = LatestOnlyRequestGate()

        let first = gate.begin("file-list")
        let second = gate.begin("file-list")

        #expect(gate.isLatest(first, for: "file-list") == false)
        #expect(gate.isLatest(second, for: "file-list") == true)
    }
}
