import SwiftUI

// MARK: - 发送消息与模型切换
//
// ClaudeChatView 的 send / retrySend / sendDirect / sendComposedMessage / sendKey / selectModel
// 以及内嵌审批、发送状态脚注等实现。

extension ClaudeChatView {
    // MARK: - 发送

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Haptics.rigid()
        let messageId = "local-user-\(UUID().uuidString)"
        inputText = ""; showSlashMenu = false; showFilePicker = false

        appendMessage(ClaudeChatItem(id: messageId, role: .user, content: text, timestamp: Date()))
        pendingLocalEchoes.append(PendingLocalEcho(localID: messageId, content: text))
        lastSendText = text

        if relayConnection.status != .connected {
            relayConnection.send([
                "method": "surface.send_text",
                "params": ["surface_id": surfaceID, "text": text + "\n"],
            ])
            withAnimation { pendingSend = PendingSend(id: messageId, stage: .queued) }
            return
        }

        withAnimation { pendingSend = PendingSend(id: messageId, stage: .sending) }

        relayConnection.sendWithResponse([
            "method": "surface.send_text",
            "params": ["surface_id": surfaceID, "text": text + "\n"],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let error = FileExplorerView.extractErrorMessage(from: result) ?? resultDict["error"] as? String {
                withAnimation { pendingSend = PendingSend(id: messageId, stage: .failed(error)) }
                return
            }
            withAnimation { pendingSend = PendingSend(id: messageId, stage: .delivered) }
            isThinking = true
        }
    }

    func retrySend() {
        guard let pending = pendingSend, case .failed = pending.stage else { return }

        if relayConnection.status != .connected {
            relayConnection.send([
                "method": "surface.send_text",
                "params": ["surface_id": surfaceID, "text": lastSendText + "\n"],
            ])
            withAnimation { pendingSend = PendingSend(id: pending.id, stage: .queued) }
            return
        }

        withAnimation { pendingSend = PendingSend(id: pending.id, stage: .sending) }
        relayConnection.sendWithResponse([
            "method": "surface.send_text",
            "params": ["surface_id": surfaceID, "text": lastSendText + "\n"],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let error = FileExplorerView.extractErrorMessage(from: result) ?? resultDict["error"] as? String {
                withAnimation { pendingSend = PendingSend(id: pending.id, stage: .failed(error)) }
                return
            }
            withAnimation { pendingSend = PendingSend(id: pending.id, stage: .delivered) }
            isThinking = true
        }
    }

    func sendDirect(_ text: String) {
        relayConnection.send(["method": "surface.send_text", "params": ["surface_id": surfaceID, "text": text]])

        guard relayConnection.status == .connected else { return }

        // 检测 TUI-only 命令：输出只在终端显示，不会写入 JSONL
        // 发送后抓取屏幕内容，清洗后作为聊天气泡就地展示
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ClaudeChatTUI.isTUIOnlyCommand(trimmed) {
            let label = trimmed.components(separatedBy: .whitespaces).first ?? trimmed
            captureTUIOutput(for: label)
        }
    }

    /// 发送混合消息（文字 + 图片）到终端
    func sendComposedMessage(_ message: ComposedMessage) {
        let correctedMessage = ComposedMessage(
            blocks: message.blocks,
            targetSurfaceID: surfaceID
        )
        guard !correctedMessage.isEmpty else { return }
        Haptics.rigid()

        // 本地显示用户消息（仅显示文字部分 + 图片数量提示）
        let textParts = correctedMessage.effectiveBlocks.compactMap { $0.textContent }
        let imageCount = correctedMessage.imageCount
        var displayText = textParts.joined(separator: "\n")
        if imageCount > 0 {
            let imageLabel = String(localized: "chat.composed.imageCount",
                                    defaultValue: "[\(imageCount) 张图片]")
            displayText = displayText.isEmpty ? imageLabel : displayText + "\n" + imageLabel
        }
        let localMessageID = "local-user-\(UUID().uuidString)"
        appendMessage(ClaudeChatItem(id: localMessageID, role: .user, content: displayText, timestamp: Date()))
        pendingLocalEchoes.append(PendingLocalEcho(localID: localMessageID, content: displayText))

        let composedMsgId = UUID().uuidString
        if relayConnection.status == .connected {
            withAnimation { pendingSend = PendingSend(id: composedMsgId, stage: .sending) }
        } else {
            withAnimation { pendingSend = PendingSend(id: composedMsgId, stage: .queued) }
        }
        lastSendText = displayText
        Task {
            try? await Task.sleep(for: .seconds(Self.kPendingDeliveryConfirmTimeout))
            if pendingSend?.id == composedMsgId, pendingSend?.stage == .sending {
                withAnimation { pendingSend = PendingSend(id: composedMsgId, stage: .delivered) }
            }
        }

        // 通过 composed_msg 协议发送
        let sender = ComposedMessageSender(relayConnection: relayConnection)
        sender.send(correctedMessage)
        if relayConnection.status == .connected {
            isThinking = true
        }
    }

    // MARK: - 内嵌审批

    /// 当前 surface 的待处理审批请求
    var pendingApprovalsForSurface: [ApprovalRequest] {
        approvalManager.pendingRequests.filter { $0.surfaceID == surfaceID }
    }

    func handleInlineApprove(_ request: ApprovalRequest) {
        let payload = approvalManager.buildApprovePayload(requestID: request.requestID)
        relayConnection.send(payload)
        approvalManager.markResolved(requestID: request.requestID, resolution: .approved)
    }

    func handleInlineReject(_ request: ApprovalRequest) {
        let payload = approvalManager.buildRejectPayload(requestID: request.requestID)
        relayConnection.send(payload)
        approvalManager.markResolved(requestID: request.requestID, resolution: .rejected)
    }

    /// 通过 Mac 端 RPC 切换模型（Ctrl+C → --resume + --model 重启）
    func selectModel(key: String, name: String) {
        // 立即显示"切换中"反馈
        withAnimation { modelSwitchFeedback = "正在切换到 \(name)..." }

        relayConnection.sendWithResponse([
            "method": "claude.switch_model",
            "params": ["surface_id": surfaceID, "model": key],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if resultDict["switching"] as? Bool == true {
                // 异步切换已开始，等待 claude.model_switched 事件
                return
            }
            // 旧版 Mac 端或错误响应
            if resultDict["ok"] as? Bool == true {
                withAnimation { modelSwitchFeedback = "已切换到 \(name)" }
            } else {
                let error = resultDict["error"] as? String ?? "切换失败"
                withAnimation { modelSwitchFeedback = "⚠️ \(error)" }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { modelSwitchFeedback = nil }
            }
        }
    }

    func sendKey(_ key: String, _ mods: String) {
        let combinedKey = mods.isEmpty ? key : "\(mods)-\(key)"
        relayConnection.send(["method": "surface.send_key", "params": ["surface_id": surfaceID, "key": combinedKey]])
    }

    // MARK: - 发送状态指示

    @ViewBuilder
    var sendStatusFooter: some View {
        if let pending = pendingSend {
            HStack(spacing: 6) {
                switch pending.stage {
                case .sending:
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text(String(localized: "chat.status.sending", defaultValue: "发送中…"))
                case .queued:
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(String(localized: "chat.status.queued", defaultValue: "离线排队中…"))
                case .delivered:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(String(localized: "chat.status.delivered", defaultValue: "已送达"))
                case .thinking:
                    ThinkingDotsView()
                    Text(String(localized: "chat.status.thinking", defaultValue: "Claude 正在思考…"))
                case .failed(let error):
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                    Button(String(localized: "chat.status.retry", defaultValue: "重试")) {
                        retrySend()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(CMColors.textTertiary)
            .padding(.leading, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

/// 发送状态中 Claude 思考时的动态三点指示器
struct ThinkingDotsView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.purple.opacity(i <= phase ? 1.0 : 0.3))
                    .frame(width: 4, height: 4)
                    .scaleEffect(i <= phase ? 1.2 : 0.8)
            }
        }
        .frame(width: 20, height: 12)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = (phase + 1) % 4
                }
            }
        }
    }
}
