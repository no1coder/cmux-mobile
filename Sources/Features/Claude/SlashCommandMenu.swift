import SwiftUI

/// 斜杠命令定义
struct SlashCommand {
    let cmd: String
    let desc: String
    let category: String
    let shortcut: String?

    init(_ cmd: String, _ desc: String, _ category: String, shortcut: String? = nil) {
        self.cmd = cmd; self.desc = desc; self.category = category; self.shortcut = shortcut
    }
}

/// 全部可用的斜杠命令
let allSlashCommands: [SlashCommand] = [
    // 常用
    SlashCommand("/compact", "压缩上下文", "常用", shortcut: "⌘⇧C"),
    SlashCommand("/status", "查看状态", "常用"),
    SlashCommand("/clear", "清空对话", "常用"),
    SlashCommand("/help", "帮助", "常用"),
    SlashCommand("/cost", "费用统计", "常用"),
    // 项目
    SlashCommand("/init", "初始化项目", "项目"),
    SlashCommand("/review", "代码审查", "项目"),
    SlashCommand("/bug", "报告/调试 Bug", "项目"),
    SlashCommand("/terminal-setup", "终端环境配置", "项目"),
    // 配置
    SlashCommand("/config", "配置", "配置"),
    SlashCommand("/permissions", "权限管理", "配置"),
    SlashCommand("/memory", "记忆管理", "配置"),
    SlashCommand("/allowed-tools", "管理允许的工具", "配置"),
    // 工具
    SlashCommand("/mcp", "MCP 服务", "工具"),
    SlashCommand("/model", "切换模型", "工具"),
    SlashCommand("/vim", "Vim 模式", "工具"),
    SlashCommand("/doctor", "诊断", "工具"),
    SlashCommand("/listen", "监听模式", "工具"),
    SlashCommand("/install-github-app", "安装 GitHub App", "工具"),
]

/// 需要原生 UI 处理的交互式命令（不能直接发送文本到终端）
enum InteractiveCommand {
    case model    // 模型选择
}

/// 需要终端 TUI 交互的命令，手机端无法操作，标记为不可用
private let unsupportedInteractiveCommands: Set<String> = [
    "/config", "/permissions", "/vim", "/allowed-tools",
]

/// 斜杠命令菜单视图
struct SlashCommandMenu: View {
    @Binding var inputText: String
    @Binding var showSlashMenu: Bool
    @AppStorage("recentSlashCommands") private var recentCommandsData = ""
    let onSelect: () -> Void
    /// 交互式命令回调（/model、/plan 等需要原生 UI 的命令）
    var onInteractiveCommand: ((InteractiveCommand) -> Void)?
    /// Mac 端推送的动态命令列表（空时降级为硬编码默认值）
    var dynamicCommands: [[String: Any]] = []

    /// 最近使用的命令列表
    var recentCommands: [String] {
        recentCommandsData.isEmpty ? [] : recentCommandsData.components(separatedBy: ",")
    }

    /// 根据动态数据或硬编码兜底构建展示命令列表
    private var displayCommands: [SlashCommand] {
        if dynamicCommands.isEmpty {
            return allSlashCommands
        }
        return dynamicCommands.compactMap { dict -> SlashCommand? in
            guard let command = dict["command"] as? String,
                  let description = dict["description"] as? String else { return nil }
            let category = mapCategory(dict["category"] as? String ?? "common")
            let shortcut = dict["shortcut"] as? String
            return SlashCommand(command, description, category, shortcut: shortcut)
        }
    }

    /// 将英文分类名映射为中文显示名
    private func mapCategory(_ raw: String) -> String {
        switch raw {
        case "common":  return "常用"
        case "project": return "项目"
        case "config":  return "配置"
        case "tools":   return "工具"
        case "user":    return "自定义"
        case "skill":   return "技能"
        case "plugin":  return "插件"
        default:        return "其他"
        }
    }

    var body: some View {
        // 从最后一个 "/" 后提取搜索关键词
        let query: String = {
            guard let slashIdx = inputText.lastIndex(of: "/") else { return "" }
            return String(inputText[inputText.index(after: slashIdx)...]).lowercased()
        }()
        let commands = displayCommands
        let filtered = query.isEmpty ? commands : commands.filter { $0.cmd.contains(query) }

        // 按分类分组
        let categories = ["常用", "项目", "配置", "工具", "自定义", "技能", "插件", "其他"]
        let grouped = Dictionary(grouping: filtered) { $0.category }

        // 最近使用的命令（仅在无搜索时显示）
        let recentItems: [SlashCommand] = query.isEmpty
            ? recentCommands.compactMap { cmd in commands.first { $0.cmd == cmd } }
            : []

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 最近使用
                if !recentItems.isEmpty {
                    sectionHeader("最近使用")
                    ForEach(recentItems, id: \.cmd) { item in
                        slashCommandRow(item)
                    }
                }

                // 分类列表
                ForEach(categories, id: \.self) { category in
                    if let items = grouped[category], !items.isEmpty {
                        sectionHeader(category)
                        ForEach(items, id: \.cmd) { item in
                            slashCommandRow(item)
                        }
                    }
                }
            }
        }.frame(maxHeight: 260).background(CMColors.menuBackground)
    }

    /// 记录最近使用的命令
    func trackRecentCommand(_ cmd: String) {
        var recents = recentCommands.filter { $0 != cmd }
        recents.insert(cmd, at: 0)
        let trimmed = Array(recents.prefix(5))
        recentCommandsData = trimmed.joined(separator: ",")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(CMColors.textTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }

    private func slashCommandRow(_ item: SlashCommand) -> some View {
        Button {
            let isUnsupported = unsupportedInteractiveCommands.contains(item.cmd)
            guard !isUnsupported else { return }
            trackRecentCommand(item.cmd)
            // 交互式命令：通过原生 UI 处理，不发送文本
            if item.cmd == "/model" {
                // 移除最后的 "/..." 部分
                if let slashIdx = inputText.lastIndex(of: "/") {
                    inputText = String(inputText[..<slashIdx])
                }
                showSlashMenu = false
                onInteractiveCommand?(.model)
                return
            }
            // 替换最后一个 "/" 及其后内容为选中的命令
            if let slashIdx = inputText.lastIndex(of: "/") {
                inputText = String(inputText[..<slashIdx]) + item.cmd + " "
            } else {
                inputText = item.cmd + " "
            }
            showSlashMenu = false
            onSelect()
        } label: {
            HStack {
                Text(item.cmd)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(unsupportedInteractiveCommands.contains(item.cmd) ? CMColors.textTertiary : .orange)
                Spacer()
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(CMColors.textTertiary)
                        .padding(.trailing, 4)
                }
                Text(item.desc)
                    .font(.system(size: 12))
                    .foregroundStyle(CMColors.textTertiary)
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}
