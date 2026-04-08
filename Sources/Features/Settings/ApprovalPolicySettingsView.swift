import SwiftUI

/// 审批策略设置：自动批准规则、工具白名单
struct ApprovalPolicySettingsView: View {
    @AppStorage("approveReadOnlyTools") private var approveReadOnlyTools = true
    @AppStorage("approveAllForSession") private var approveAllForSession = false
    @AppStorage("customAutoApproveTools") private var customAutoApproveToolsRaw = ""

    var body: some View {
        List {
            toggleSection
            toolListSection
        }
        .navigationTitle(String(localized: "settings.approval.title", defaultValue: "审批策略"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 开关

    private var toggleSection: some View {
        Section(
            footer: Text(String(
                localized: "settings.approval.toggle_footer",
                defaultValue: "自动批准只读工具（Read、Glob、Grep、WebSearch）可以加速工作流。"
            ))
        ) {
            Toggle(
                String(localized: "settings.approval.auto_readonly", defaultValue: "自动批准只读工具"),
                isOn: $approveReadOnlyTools
            )

            Toggle(
                String(localized: "settings.approval.approve_all_session", defaultValue: "本次会话全部自动批准"),
                isOn: $approveAllForSession
            )
        }
    }

    // MARK: - 已自动批准的工具列表

    private var toolListSection: some View {
        Section(
            header: Text(String(
                localized: "settings.approval.tool_list_header",
                defaultValue: "自动批准的工具"
            )),
            footer: Text(String(
                localized: "settings.approval.tool_list_footer",
                defaultValue: "以下工具在权限请求时将被自动批准。"
            ))
        ) {
            // 默认只读工具
            ForEach(Array(ApprovalPolicy.readOnlyTools.sorted()), id: \.self) { tool in
                HStack {
                    Text(tool)
                        .font(.system(size: 14, design: .monospaced))
                    Spacer()
                    Text(String(localized: "settings.approval.readonly_badge", defaultValue: "只读"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            // 用户自定义工具
            ForEach(customTools, id: \.self) { tool in
                HStack {
                    Text(tool)
                        .font(.system(size: 14, design: .monospaced))
                    Spacer()
                    Text(String(localized: "settings.approval.custom_badge", defaultValue: "自定义"))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - 辅助

    /// 从逗号分隔字符串解析出自定义工具列表
    private var customTools: [String] {
        customAutoApproveToolsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
