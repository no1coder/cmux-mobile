import Testing
#if canImport(cmux_mobile)
@testable import cmux_mobile
#elseif canImport(cmux_core)
@testable import cmux_core
#endif

struct DeviceStoreTests {

    private func makeDevice(id: String, name: String) -> PairedDevice {
        PairedDevice(
            id: id,
            name: name,
            serverURL: "devpod.rooyun.com",
            pairSecret: "secret-\(id)",
            pairedAt: .distantPast,
            lastConnected: nil
        )
    }

    @Test func testResolveActiveDeviceReturnsExplicitMatch() {
        let devices = [
            makeDevice(id: "mac-a", name: "Mac A"),
            makeDevice(id: "mac-b", name: "Mac B")
        ]

        let resolved = DeviceStore.resolveActiveDevice(in: devices, activeDeviceID: "mac-b")
        #expect(resolved?.id == "mac-b")
    }

    @Test func testResolveActiveDeviceReturnsOnlyDeviceWhenUnspecified() {
        let devices = [makeDevice(id: "mac-a", name: "Mac A")]

        let resolved = DeviceStore.resolveActiveDevice(in: devices, activeDeviceID: nil)
        #expect(resolved?.id == "mac-a")
    }

    @Test func testResolveActiveDeviceReturnsNilWhenMultipleDevicesAndUnspecified() {
        let devices = [
            makeDevice(id: "mac-a", name: "Mac A"),
            makeDevice(id: "mac-b", name: "Mac B")
        ]

        let resolved = DeviceStore.resolveActiveDevice(in: devices, activeDeviceID: nil)
        #expect(resolved == nil)
    }

    @Test func testResolveActiveDeviceReturnsNilWhenStoredIDIsStale() {
        let devices = [
            makeDevice(id: "mac-a", name: "Mac A"),
            makeDevice(id: "mac-b", name: "Mac B")
        ]

        let resolved = DeviceStore.resolveActiveDevice(in: devices, activeDeviceID: "mac-missing")
        #expect(resolved == nil)
    }
}
