import SwiftUI

// MARK: - Mac 端推送监听 / 轮询 / 流式预览
//
// ClaudeChatView 的事件订阅与流式输出抓取逻辑：
// - startWatching/stopWatching：订阅 Mac 端 JSONL 文件监听推送（主要通道）
// - startPolling/stopPolling：降级轮询（15 秒兜底）
// - startStreamingPreview/stopStreamingPreview：生成时快速轮询终端屏幕

extension ClaudeChatView {
    // MARK: - Mac 端推送监听（主要通道）

    /// 订阅 Mac 端 JSONL 文件监听推送
    func startWatching() {
        if claudeUpdateObserverID != nil { return }
        relayConnection.beginClaudeWatch(surfaceID: surfaceID)

        // 监听推送事件
        let sid = surfaceID
        claudeUpdateObserverID = relayConnection.addClaudeUpdateObserver { payload in
            // 模型切换事件（不含 surface_id 过滤，因为是全局事件）
            if let event = payload["event"] as? String {
                switch event {
                case "claude.model_switching":
                    let model = payload["model"] as? String ?? ""
                    withAnimation { modelSwitchFeedback = "正在切换到 \(model)..." }
                    return
                case "claude.model_switched":
                    let model = payload["model"] as? String ?? ""
                    let ok = payload["ok"] as? Bool ?? false
                    if ok {
                        withAnimation { modelSwitchFeedback = "已切换到 \(model)" }
                    } else {
                        let error = payload["error"] as? String ?? "切换失败"
                        withAnimation { modelSwitchFeedback = "⚠️ \(error)" }
                    }
                    viewTaskBag.runAfter(2.5) {
                        withAnimation { modelSwitchFeedback = nil }
                    }
                    return
                case "claude.session.reset":
                    // Mac 端 JSONL 文件被截断/替换，重置状态并重新拉取
                    let payloadSid = payload["surface_id"] as? String ?? ""
                    guard payloadSid == sid else { return }
                    lastSeq = 0
                    displayLimit = Self.pageSize
                    pagingState.reset()
                    hasMoreRemoteHistory = pagingState.hasMoreRemoteHistory
                    nextBeforeSeq = pagingState.nextBeforeSeq
                    tokenUsage = [:]
                    isThinking = false
                    activityLabel = ""
                    historyLoadState = .loading
                    fullHistoryState = .loading
                    messageStore.setClaudeChatHistoryCompleteness(surfaceID, hasCompleteHistory: false)
                    requestHistoryFetch(mode: .recentPage)
                    return
                default:
                    break
                }
            }

            let payloadSid = payload["surface_id"] as? String ?? ""
            guard payloadSid == sid else { return }

            if let messages = payload["messages"] as? [[String: Any]] {
                let status = payload["status"] as? String ?? "idle"
                activityLabel = status
                isThinking = (status == "thinking" || status == "tool_running")
                historyLoadState = .loaded

                // 提取 token 用量
                if let usage = payload["usage"] as? [String: Int] {
                    tokenUsage = usage
                }

                processJsonlMessages(messages)

                // 更新发送状态
                if let pending = pendingSend,
                   pending.stage == .delivered || pending.stage == .sending || pending.stage == .queued {
                    let hasResponse = messages.contains { ($0["type"] as? String) == "assistant" }
                    if hasResponse || status == "thinking" || status == "tool_running" {
                        withAnimation { pendingSend = PendingSend(id: pending.id, stage: .thinking) }
                    }
                }
                if !isThinking, let pending = pendingSend, pending.stage == .thinking {
                    withAnimation { pendingSend = nil }
                }
            }
        }
    }

    func stopWatching() {
        relayConnection.endClaudeWatch(surfaceID: surfaceID)
        if let claudeUpdateObserverID {
            relayConnection.removeClaudeUpdateObserver(claudeUpdateObserverID)
            self.claudeUpdateObserverID = nil
        }
    }

    // MARK: - 降级轮询（15秒兜底）

    func startPolling() {
        stopPolling()
        refreshTask = Task {
            while !Task.isCancelled {
                // HIGH 修复：推送通道存在时，轮询间隔从 5 秒提升到 15 秒
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                guard relayConnection.status == .connected else { continue }
                requestHistoryFetch(mode: .incremental)
            }
        }
    }

    func stopPolling() { refreshTask?.cancel(); refreshTask = nil }

    // MARK: - 流式预览（生成时轮询终端屏幕）

    /// Claude 生成期间，快速轮询 read_screen 获取实时输出
    func startStreamingPreview() {
        stopStreamingPreview()
        streamingPreview = ""
        let sid = surfaceID
        streamingTask = Task {
            while !Task.isCancelled {
                // 1 秒间隔轮询终端屏幕
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }

                let token = await MainActor.run { requestGate.begin("streaming-preview") }
                await withCheckedContinuation { continuation in
                    relayConnection.sendWithResponse([
                        "method": "read_screen",
                        "params": ["surface_id": sid],
                    ]) { result in
                        guard requestGate.isLatest(token, for: "streaming-preview") else {
                            continuation.resume()
                            return
                        }
                        let resultDict = result["result"] as? [String: Any] ?? result
                        if let lines = resultDict["lines"] as? [String] {
                            let extracted = ClaudeChatTUI.extractClaudeOutput(from: lines)
                            if !extracted.isEmpty {
                                DispatchQueue.main.async {
                                    streamingPreview = extracted
                                }
                            }
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }

    func stopStreamingPreview() {
        streamingTask?.cancel()
        streamingTask = nil
        // 不立即清空 streamingPreview，让 JSONL 消息到达后自然替换
    }
}
