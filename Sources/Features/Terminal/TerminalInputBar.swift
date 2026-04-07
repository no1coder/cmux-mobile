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
        ShortcutKey(id: "ctrl_c", label: "^C",     key: "c",      mods: "ctrl"),
        ShortcutKey(id: "ctrl_d", label: "^D",     key: "d",      mods: "ctrl"),
        ShortcutKey(id: "ctrl_z", label: "^Z",     key: "z",      mods: "ctrl"),
        ShortcutKey(id: "ctrl_l", label: "^L",     key: "l",      mods: "ctrl"),
        ShortcutKey(id: "enter",  label: "↵",      key: "return", mods: ""),
    ]

    /// Claude Code 快捷命令
    private let claudeCommands: [(label: String, command: String)] = [
        ("claude", "claude\n"),
        ("/help", "/help\n"),
        ("/status", "/status\n"),
        ("/compact", "/compact\n"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 分隔线
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 0.5)

            // 快捷键水平滚动栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Ctrl 模式切换按钮
                    Button {
                        inputManager.toggleCtrlMode()
                    } label: {
                        Text("Ctrl")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                inputManager.isCtrlMode
                                    ? Color.green
                                    : Color.white.opacity(0.12)
                            )
                            .foregroundStyle(
                                inputManager.isCtrlMode ? Color.black : Color.white
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }

                    // 快捷键按钮
                    ForEach(shortcuts) { shortcut in
                        Button {
                            handleShortcut(shortcut)
                        } label: {
                            Text(shortcut.label)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.12))
                                .foregroundStyle(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            // Claude 快捷命令行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(claudeCommands, id: \.label) { cmd in
                        Button {
                            onSendText(cmd.command)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 10))
                                Text(cmd.label)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.3))
                            .foregroundStyle(Color.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            }

            // 文本输入行
            HStack(spacing: 8) {
                TextField("", text: $inputText, prompt: Text("输入命令…").foregroundStyle(.gray))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        guard !inputText.isEmpty else { return }
                        onSendText(inputText)
                        inputText = ""
                    }

                Button {
                    guard !inputText.isEmpty else { return }
                    onSendText(inputText)
                    inputText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(inputText.isEmpty ? Color.gray : Color.green)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(Color(white: 0.1))
    }

    // MARK: - 私有方法

    private func handleShortcut(_ shortcut: ShortcutKey) {
        if !shortcut.mods.isEmpty {
            onSendKey(shortcut.key, shortcut.mods)
            return
        }
        let input = inputManager.applyModifiers(to: shortcut.key)
        onSendKey(input.key, input.mods)
    }
}
