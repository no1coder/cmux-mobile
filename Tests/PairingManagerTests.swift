import Testing
#if canImport(cmux_mobile)
@testable import cmux_mobile
#elseif canImport(cmux_core)
@testable import cmux_core
#endif

struct PairingManagerTests {

    // MARK: - parseQRCode 测试

    @Test func testParseQRCodeValidJSON() {
        let json = """
        {
            "server_url": "devpod.rooyun.com",
            "device_id": "mac-abc123",
            "pair_token": "tok_xyz789"
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result != nil)
        #expect(result?.serverURL == "devpod.rooyun.com")
        #expect(result?.deviceID == "mac-abc123")
        #expect(result?.pairToken == "tok_xyz789")
    }

    @Test func testParseQRCodeAllowsConfiguredSelfHostedHost() {
        let json = """
        {
            "server_url": "relay.example.com",
            "device_id": "mac-abc123",
            "pair_token": "tok_xyz789"
        }
        """
        let result = PairingManager.parseQRCode(
            json,
            allowedHosts: [PairingManager.defaultServerURL, "relay.example.com"]
        )
        #expect(result != nil)
        #expect(result?.serverURL == "relay.example.com")
    }

    @Test func testParseQRCodeAllowsConfiguredSelfHostedHostWithPort() {
        let json = """
        {
            "server_url": "relay.example.com:8443",
            "device_id": "mac-abc123",
            "pair_token": "tok_xyz789"
        }
        """
        let result = PairingManager.parseQRCode(
            json,
            allowedHosts: [PairingManager.defaultServerURL, "relay.example.com:8443"]
        )
        #expect(result != nil)
        #expect(result?.serverURL == "relay.example.com:8443")
    }

    @Test func testParseQRCodeRejectsUnknownHost() {
        let json = """
        {
            "server_url": "relay.example.com",
            "device_id": "mac-abc123",
            "pair_token": "tok_xyz789"
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result == nil)
    }

    @Test func testNormalizeServerHostRejectsPathsAndSchemes() {
        #expect(PairingManager.normalizedServerHost("https://relay.example.com") == nil)
        #expect(PairingManager.normalizedServerHost("relay.example.com/path") == nil)
        #expect(PairingManager.normalizedServerHost("relay.example.com?foo=1") == nil)
    }

    @Test func testNormalizeServerHostLowercasesAndTrims() {
        #expect(PairingManager.normalizedServerHost(" Relay.Example.Com \n") == "relay.example.com")
    }

    @Test func testNormalizeServerHostAllowsPort() {
        #expect(PairingManager.normalizedServerHost(" Relay.Example.Com:8443 \n") == "relay.example.com:8443")
    }

    @Test func testNormalizeServerHostRejectsInvalidPort() {
        #expect(PairingManager.normalizedServerHost("relay.example.com:0") == nil)
        #expect(PairingManager.normalizedServerHost("relay.example.com:99999") == nil)
        #expect(PairingManager.normalizedServerHost("relay.example.com:abc") == nil)
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
            "server_url": "devpod.rooyun.com",
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
            "server_url": "devpod.rooyun.com",
            "device_id": "mac-abc123",
            "pair_token": ""
        }
        """
        let result = PairingManager.parseQRCode(json)
        #expect(result == nil)
    }
}
