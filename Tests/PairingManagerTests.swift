import Testing
@testable import cmux_mobile

struct PairingManagerTests {

    // MARK: - parseQRCode 测试

    @Test func testParseQRCodeValidJSON() {
        let json = """
        {
            "server_url": "relay.example.com",
            "device_id": "mac-abc123",
            "pair_token": "tok_xyz789"
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result != nil)
        #expect(result?.serverURL == "relay.example.com")
        #expect(result?.deviceID == "mac-abc123")
        #expect(result?.pairToken == "tok_xyz789")
    }

    @Test func testParseQRCodeInvalidJSON() {
        let result = PairingManager.parseQRCode("not valid json {{{")
        #expect(result == nil)
    }

    @Test func testParseQRCodeMissingServerURL() {
        let json = """
        {
            "device_id": "mac-abc123",
            "pair_token": "tok_xyz789"
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result == nil)
    }

    @Test func testParseQRCodeMissingDeviceID() {
        let json = """
        {
            "server_url": "relay.example.com",
            "pair_token": "tok_xyz789"
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result == nil)
    }

    @Test func testParseQRCodeMissingPairToken() {
        let json = """
        {
            "server_url": "relay.example.com",
            "device_id": "mac-abc123"
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result == nil)
    }

    @Test func testParseQRCodeEmptyServerURL() {
        let json = """
        {
            "server_url": "",
            "device_id": "mac-abc123",
            "pair_token": "tok_xyz789"
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result == nil)
    }

    @Test func testParseQRCodeEmptyDeviceID() {
        let json = """
        {
            "server_url": "relay.example.com",
            "device_id": "",
            "pair_token": "tok_xyz789"
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result == nil)
    }

    @Test func testParseQRCodeEmptyToken() {
        let json = """
        {
            "server_url": "relay.example.com",
            "device_id": "mac-abc123",
            "pair_token": ""
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result == nil)
    }
}
