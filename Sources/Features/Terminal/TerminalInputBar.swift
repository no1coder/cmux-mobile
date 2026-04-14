import SwiftUI

/// 终端输入工具栏，提供快捷键按钮和文本发送功能
struct TerminalInputBar: View {
    @EnvironmentObject var inputManager: InputManager
    /// 用于判断当前连接状态，断线时禁用按钮避免用户以为在发但实际丢失
    @EnvironmentObject var relayConnection: RelayConnection

    /// 发送文本时的回调
    let onSendText: (String) -> Void
    /// 发送按键（键名，修饰符）时的回调
    let onSendKey: (String, String) -> Void

    @State private var inputText: String = ""

    /// 是否已连接到 Mac；断线时整个输入栏变灰并禁用交互
    private var isOnline: Bool { relayConnection.status == .connected }

    /// 最近发送过的命令（本地持久化，跨会话保留 20 条）
    /// 用户点击后填入输入框但不自动发送，便于微调再发
    @AppStorage("terminalInputHistory") private var historyRaw: String = ""
    @State private var showHistory = false

    private var history: [String] {
        historyRaw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func pushHistory(_ cmd: String) {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var existing = history.filter { $0 != trimmed }
        existing.insert(trimmed, at: 0)
        if existing.count > 20 { existing = Array(existing.prefix(20)) }
        historyRaw = existing.joined(separator: "\n")
    }

    // MARK: - 触觉反馈

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    // MARK: - 快捷键定义

    private struct ShortcutKey: Identifiable {
        let id: String
        let label: String
        let key: String
        let mods: String
    }

    /// 横向滚动栏的通用快捷键（↵ 和数字键 1/2/3 已单独常驻展示）
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

            // 离线状态横幅：显式告诉用户"按下去不会发出去"
            if !isOnline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11))
                    Text(String(
                        localized: "terminal.offline",
                        defaultValue: "未连接到 Mac，按键将无法送达"
                    ))
                    .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.12))
            }

            // 交互提示快捷行：↵ 回车 + 1/2/3 数字键
            // 解决 Claude Code 等 TUI 出现 "1. Yes / 2. ... / 3. No" 选项时
            // 没有明显的回车/数字键可点的问题
            HStack(spacing: 6) {
                // 回车按钮（绿色突出，确认提示）
                Button {
                    hapticFeedback.impactOccurred()
                    onSendKey("return", "")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "return")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Enter")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.28))
                    .foregroundStyle(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .accessibilityLabel(String(localized: "terminal.send_enter", defaultValue: "发送回车"))

                // 数字 1 / 2 / 3（TUI 选项专用）
                ForEach(["1", "2", "3"], id: \.self) { digit in
                    Button {
                        hapticFeedback.impactOccurred()
                        onSendText(digit)
                    } label: {
                        Text(digit)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .frame(minWidth: 28)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.25))
                            .foregroundStyle(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .accessibilityLabel(String(
                        localized: "terminal.send_digit",
                        defaultValue: "发送数字 \(digit)"
                    ))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // 快捷键水平滚动栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // 清屏按钮（Ctrl+L）
                    Button {
                        hapticFeedback.impactOccurred()
                        onSendKey("l", "ctrl")
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "eraser.line.dashed")
                                .font(.system(size: 11))
                            Text(String(localized: "input.clear", defaultValue: "清屏"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.25))
                        .foregroundStyle(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }

                    // Ctrl 模式切换按钮
                    Button {
                        hapticFeedback.impactOccurred()
                        inputManager.toggleCtrlMode()
                    } label: {
                        Text("Ctrl")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
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
                            hapticFeedback.impactOccurred()
                            handleShortcut(shortcut)
                        } label: {
                            Text(shortcut.label)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
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
                // 历史记录菜单（最近 20 条）
                if !history.isEmpty {
                    Menu {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, cmd in
                            Button {
                                inputText = cmd
                            } label: {
                                Text(cmd)
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            historyRaw = ""
                        } label: {
                            Label("清空历史", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18))
                            .foregroundStyle(.gray)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(String(
                        localized: "terminal.history",
                        defaultValue: "命令历史"
                    ))
                }

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
                        sendCurrentInput()
                    }

                Button {
                    sendCurrentInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(inputText.isEmpty || !isOnline ? Color.gray : Color.green)
                }
                .disabled(inputText.isEmpty || !isOnline)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(CMColors.backgroundSecondary)
        // 整个面板在离线时禁用，保持视觉反馈一致（按钮可见但不可点）
        .disabled(!isOnline)
        .opacity(isOnline ? 1.0 : 0.55)
    }

    // MARK: - 私有方法

    /// 发送当前输入框内容并入历史
    private func sendCurrentInput() {
        let text = inputText
        guard !text.isEmpty else { return }
        pushHistory(text)
        onSendText(text)
        inputText = ""
    }

    private func handleShortcut(_ shortcut: ShortcutKey) {
        if !shortcut.mods.isEmpty {
            onSendKey(shortcut.key, shortcut.mods)
            return
        }
        let input = inputManager.applyModifiers(to: shortcut.key)
        onSendKey(input.key, input.mods)
    }
}
