import SwiftUI

/// 审批策略设置：自动批准规则、工具白名单
struct ApprovalPolicySettingsView: View {
    @EnvironmentObject private var approvalManager: ApprovalManager
    @AppStorage("approvalAutoReadOnly") private var approveReadOnlyTools = true
    @AppStorage("approvalApproveAll") private var approveAllForSession = false

    var body: some View {
        List {
            toggleSection
            toolListSection
        }
        .navigationTitle(String(localized: "settings.approval.title", defaultValue: "审批策略"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { syncPolicy() }
        .onChange(of: approveReadOnlyTools) { _, _ in syncPolicy() }
        .onChange(of: approveAllForSession) { _, _ in syncPolicy() }
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
            if approveReadOnlyTools {
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
            } else {
                Text(String(localized: "settings.approval.disabled_hint", defaultValue: "当前未启用自动批准只读工具。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 辅助

    private func syncPolicy() {
        var newPolicy = ApprovalPolicy.default
        newPolicy.autoApproveTools = approveReadOnlyTools ? ApprovalPolicy.readOnlyTools : []
        newPolicy.approveAllForSession = approveAllForSession
        approvalManager.policy = newPolicy
        approvalManager.savePolicy()
    }
}
