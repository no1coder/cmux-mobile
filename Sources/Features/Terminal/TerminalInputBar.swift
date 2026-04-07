import SwiftUI

/// 终端输入工具栏，提供快捷键按钮和文本发送功能
struct TerminalInputBar: View {
    @EnvironmentObject var inputManager: InputManager

    /// 发送文本时的回调
    let onSendText: (String) -> Void
    /// 发送按键（键名，修饰符）时的回调
    let onSendKey: (String, String) -> Void

    @State private var inputText: String = ""

    // MARK: - 快捷键定义

    private struct ShortcutKey: Identifiable {
        let id: String
        let label: String
        let key: String
        let mods: String
    }

    private let shortcuts: [ShortcutKey] = [
        ShortcutKey(id: "tab",    label: "Tab",    key: "tab",    mods: ""),
        ShortcutKey(id: "esc",    label: "Esc",    key: "escape", mods: ""),
        ShortcutKey(id: "up",     label: "↑",      key: "up",     mods: ""),
        ShortcutKey(id: "down",   label: "↓",      key: "down",   mods: ""),
        ShortcutKey(id: "left",   label: "←",      key: "left",   mods: ""),
        ShortcutKey(id: "right",  label: "→",      key: "right",  mods: ""),
        ShortcutKey(id: "ctrl_c", label: "Ctrl+C", key: "c",      mods: "ctrl"),
        ShortcutKey(id: "ctrl_d", label: "Ctrl+D", key: "d",      mods: "ctrl"),
        ShortcutKey(id: "ctrl_z", label: "Ctrl+Z", key: "z",      mods: "ctrl"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // 快捷键水平滚动栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Ctrl 模式切换按钮
                    Button {
                        inputManager.toggleCtrlMode()
                    } label: {
                        Text("Ctrl")
                            .font(.system(.footnote, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                inputManager.isCtrlMode
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.2)
                            )
                            .foregroundStyle(
                                inputManager.isCtrlMode ? Color.white : Color.primary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    
                    // 其他快捷键按钮
                    ForEach(shortcuts) { shortcut in
                        Button {
                            handleShortcut(shortcut)
                        } label: {
                            Text(shortcut.label)
                                .font(.system(.footnote, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.2))
                                .foregroundStyle(Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // 文本输入行
            HStack(spacing: 8) {
                TextField(
                    String(localized: "input.placeholder", defaultValue: "输入文本…"),
                    text: $inputText
                )
                .font(.system(.body, design: .monospaced))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    guard !inputText.isEmpty else { return }
                    onSendText(inputText)
                    inputText = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(.body))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!inputManager.isInputEnabled || inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(white: 0.12))
    }

    // MARK: - 私有方法

    /// 处理快捷键点击，若 ctrlMode 激活则附加 ctrl 修饰
    private func handleShortcut(_ shortcut: ShortcutKey) {
        // 固定含 ctrl 修饰的快捷键直接发送
        if !shortcut.mods.isEmpty {
            onSendKey(shortcut.key, shortcut.mods)
            return
        }
        // 其他键通过 inputManager 检查 ctrlMode
        let input = inputManager.applyModifiers(to: shortcut.key)
        onSendKey(input.key, input.mods)
    }
}
