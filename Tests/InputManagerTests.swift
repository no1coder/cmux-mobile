import Testing
@testable import cmux_mobile

@Suite("InputManager Tests")
struct InputManagerTests {

    // MARK: - 默认状态测试

    @Test("默认输入禁用（App Store 只读模式）")
    func defaultIsReadOnly() {
        let manager = InputManager()
        #expect(manager.isInputEnabled == false)
        #expect(manager.isCtrlMode == false)
    }

    // MARK: - 输入模式切换测试

    @Test("启用/禁用输入")
    func toggleInput() {
        let manager = InputManager()
        manager.enableInput()
        #expect(manager.isInputEnabled == true)

        manager.disableInput()
        #expect(manager.isInputEnabled == false)
    }

    // MARK: - Ctrl 模式组合测试

    @Test("ctrlMode 开启后按键自动关闭")
    func ctrlModeCombine() {
        let manager = InputManager()
        manager.toggleCtrlMode()
        #expect(manager.isCtrlMode == true)

        let result = manager.applyModifiers(to: "c")
        #expect(result.key == "c")
        #expect(result.mods == "ctrl")
        // 使用后自动关闭
        #expect(manager.isCtrlMode == false)
    }

    @Test("无 ctrlMode 时按键不附加修饰符")
    func noCtrlModeNoModifiers() {
        let manager = InputManager()
        let result = manager.applyModifiers(to: "a")
        #expect(result.key == "a")
        #expect(result.mods == "")
    }

    @Test("toggleCtrlMode 多次调用正确切换")
    func toggleCtrlModeMultipleTimes() {
        let manager = InputManager()
        manager.toggleCtrlMode()
        #expect(manager.isCtrlMode == true)
        manager.toggleCtrlMode()
        #expect(manager.isCtrlMode == false)
    }

    // MARK: - JSON-RPC Payload 测试

    @Test("buildSendTextPayload 生成正确的 JSON-RPC")
    func sendTextCommand() {
        let manager = InputManager()
        let payload = manager.buildSendTextPayload(surfaceID: "surf-1", text: "hello")

        #expect(payload["method"] as? String == "surface.send_text")
        let params = payload["params"] as? [String: Any]
        #expect(params?["surface_id"] as? String == "surf-1")
        #expect(params?["text"] as? String == "hello")
    }

    @Test("buildSendKeyPayload 生成正确的 JSON-RPC")
    func sendKeyCommand() {
        let manager = InputManager()
        let payload = manager.buildSendKeyPayload(surfaceID: "surf-2", key: "c", mods: "ctrl")

        #expect(payload["method"] as? String == "surface.send_key")
        let params = payload["params"] as? [String: Any]
        #expect(params?["surface_id"] as? String == "surf-2")
        #expect(params?["key"] as? String == "c")
        #expect(params?["mods"] as? String == "ctrl")
    }
}
