import Testing
#if canImport(cmux_mobile)
@testable import cmux_mobile
#elseif canImport(cmux_core)
@testable import cmux_core
#endif

@Suite("ConnectionStatus Tests")
struct ConnectionStatusTests {

    @Test("所有状态枚举值存在")
    func allCasesExist() {
        let connected = ConnectionStatus.connected
        let connecting = ConnectionStatus.connecting
        let disconnected = ConnectionStatus.disconnected
        let macOffline = ConnectionStatus.macOffline

        #expect(connected != connecting)
        #expect(connecting != disconnected)
        #expect(disconnected != macOffline)
    }

    @Test("rawValue 往返编码")
    func rawValueRoundTrip() {
        #expect(ConnectionStatus(rawValue: "connected") == .connected)
        #expect(ConnectionStatus(rawValue: "connecting") == .connecting)
        #expect(ConnectionStatus(rawValue: "disconnected") == .disconnected)
        #expect(ConnectionStatus(rawValue: "macOffline") == .macOffline)
    }

    @Test("无效 rawValue 返回 nil")
    func invalidRawValueReturnsNil() {
        #expect(ConnectionStatus(rawValue: "unknown") == nil)
        #expect(ConnectionStatus(rawValue: "") == nil)
    }

    @Test("相等性判断")
    func equality() {
        #expect(ConnectionStatus.connected == ConnectionStatus.connected)
        #expect(ConnectionStatus.disconnected != ConnectionStatus.connected)
    }
}
