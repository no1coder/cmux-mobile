import Combine
import Foundation

/// 按键输入模型，携带按键和修饰符信息
struct KeyInput {
    let key: String
    let mods: String
}

/// 管理终端输入模式，包含 ctrl 组合键和 JSON-RPC 载荷构建
final class InputManager: ObservableObject {

    // MARK: - Published 属性

    /// 输入是否启用（App Store 默认只读）
    @Published var isInputEnabled: Bool = false

    /// Ctrl 组合键模式是否激活
    @Published var isCtrlMode: Bool = false

    // MARK: - 输入模式控制

    /// 启用输入
    func enableInput() {
        isInputEnabled = true
    }

    /// 禁用输入
    func disableInput() {
        isInputEnabled = false
    }

    // MARK: - Ctrl 模式

    /// 切换 Ctrl 组合键模式
    func toggleCtrlMode() {
        isCtrlMode = !isCtrlMode
    }

    /// 为按键应用修饰符；若 ctrlMode 激活，附加 ctrl 修饰并自动关闭 ctrlMode
    func applyModifiers(to key: String) -> KeyInput {
        if isCtrlMode {
            isCtrlMode = false
            return KeyInput(key: key, mods: "ctrl")
        }
        return KeyInput(key: key, mods: "")
    }

    // MARK: - JSON-RPC Payload 构建

    /// 构建 surface.send_text 的 JSON-RPC 载荷
    func buildSendTextPayload(surfaceID: String, text: String) -> [String: Any] {
        [
            "method": "surface.send_text",
            "params": [
                "surface_id": surfaceID,
                "text": text
            ] as [String: Any]
        ]
    }

    /// 构建 surface.send_key 的 JSON-RPC 载荷
    func buildSendKeyPayload(surfaceID: String, key: String, mods: String) -> [String: Any] {
        [
            "method": "surface.send_key",
            "params": [
                "surface_id": surfaceID,
                "key": key,
                "mods": mods
            ] as [String: Any]
        ]
    }
}
