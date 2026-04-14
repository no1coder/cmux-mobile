import SwiftUI

// MARK: - 历史消息加载
//
// ClaudeChatView 的历史拉取与 JSONL 处理逻辑：
// - requestHistoryFetch / finishHistoryFetch / fetchMessages：协调增量 / 分页 / 全量三种模式
// - processJsonlMessages：将 Mac 端返回的 JSONL 消息转换为 UI 气泡
// - upsertNewItem / reconcilePendingLocalEcho / updateOrAppendStreamingMessage：增量合并
// - preserveExpandedHistoryWindow* / preserveVisibleWindowForIncrementalAppend：分页/流式窗口维护
// - formatModelName / formatToolInput / updatePlanModeState：渲染辅助

extension ClaudeChatView {
    // MARK: - 从 JSONL 拉取消息（跟 happy 的 sessionScanner 一样）

    func requestHistoryFetch(mode: HistoryFetchMode = .incremental) {
        if let activeHistoryFetchMode {
            if activeHistoryFetchMode.priority >= mode.priority {
                return
            }
            queuedHistoryFetchMode = mode
            return
        }

        fetchMessages(mode: mode)
    }

    func finishHistoryFetch(_ mode: HistoryFetchMode) {
        guard activeHistoryFetchMode == mode else { return }
        activeHistoryFetchMode = nil

        guard let queuedHistoryFetchMode else { return }
        self.queuedHistoryFetchMode = nil
        fetchMessages(mode: queuedHistoryFetchMode)
    }

    func fetchMessages(mode: HistoryFetchMode = .incremental) {
        activeHistoryFetchMode = mode
        let startedAt = Date()
        let token = requestGate.begin(mode.requestGateKey)
        let hadCachedMessages = !(messageStore.claudeChats[surfaceID] ?? []).isEmpty
        let previousCachedCount = messageStore.claudeChats[surfaceID]?.count ?? 0
        if mode != .incremental {
            fullHistoryState = .loading
            if !hadCachedMessages {
                historyLoadState = .loading
            }
        } else if !hadCachedMessages {
            historyLoadState = .loading
        }

        var params: [String: Any] = ["surface_id": surfaceID]
        switch mode {
        case .incremental:
            params["after_seq"] = lastSeq
        case .recentPage:
            params["limit"] = Self.pageSize
        case .pageBefore(let beforeSeq):
            params["before_seq"] = beforeSeq
            params["limit"] = Self.pageSize
        case .fullRefreshLegacy:
            params["after_seq"] = 0
        }

        relayConnection.sendWithResponse([
            "method": "claude.messages",
            "params": params,
            "client_timeout_seconds": mode.timeoutSeconds,
        ]) { result in
            defer { finishHistoryFetch(mode) }
            guard requestGate.isLatest(token, for: mode.requestGateKey) else { return }
            let resultDict = result["result"] as? [String: Any] ?? result

            if let error = resultDict["error"] as? String {
                let message = (resultDict["message"] as? String)
                    ?? String(localized: "chat.history_load_failed", defaultValue: "加载历史消息失败，请稍后重试。")
                if mode != .incremental {
                    if !hadCachedMessages && chatMessages.isEmpty {
                        historyLoadState = .failed(message)
                    }
                    fullHistoryState = .failed(message)
                } else if !hadCachedMessages && chatMessages.isEmpty {
                    historyLoadState = .failed(message)
                } else {
                    historyLoadState = .loaded
                }
                #if DEBUG
                print("[claude] claude.messages 失败: \(error) \(message)")
                #endif
                return
            }

            if let totalSeq = resultDict["total_seq"] as? Int {
                if mode == .fullRefreshLegacy && totalSeq < lastSeq {
                    // 说明全量回填返回时，本地已经收到了更新的增量；
                    // 不要用较旧快照覆盖当前聊天，再发起一次全量回填。
                    fullHistoryState = .idle
                    viewTaskBag.runAfter(0.2) {
                        requestHistoryFetch(mode: .fullRefreshLegacy)
                    }
                    return
                }
                lastSeq = totalSeq
                messageStore.setClaudeChatSequence(surfaceID, totalSeq: totalSeq)
            }

            // 更新整体状态
            let status = resultDict["status"] as? String ?? "idle"
            activityLabel = status
            isThinking = (status == "thinking" || status == "tool_running")

            // 提取 token 用量
            if let usage = resultDict["usage"] as? [String: Int] {
                tokenUsage = usage
            }

            pagingState.applyResponse(
                fetchKind: mode.coreKind,
                hasMore: resultDict["has_more"] as? Bool,
                serverNextBeforeSeq: resultDict["next_before_seq"] as? Int,
                fallbackOldestLoadedSeq: oldestLoadedSeq
            )
            hasMoreRemoteHistory = pagingState.hasMoreRemoteHistory
            nextBeforeSeq = pagingState.nextBeforeSeq

            guard let messages = resultDict["messages"] as? [[String: Any]] else {
                let existingMessages = messageStore.claudeChats[surfaceID] ?? []
                let normalizedMessages = ClaudeChatItem.normalizeRunningTools(
                    in: existingMessages,
                    allowTrailingRunningTools: status == "tool_running"
                )
                if normalizedMessages != existingMessages {
                    messageStore.setClaudeChat(surfaceID, messages: normalizedMessages, totalSeq: lastSeq > 0 ? lastSeq : nil)
                }
                if mode != .incremental {
                    if !hadCachedMessages && chatMessages.isEmpty {
                        historyLoadState = .failed(String(
                            localized: "chat.history_missing_payload",
                            defaultValue: "未收到会话历史数据，请稍后重试。"
                        ))
                    }
                    fullHistoryState = .failed(String(
                        localized: "chat.history_missing_payload",
                        defaultValue: "未收到会话历史数据，请稍后重试。"
                    ))
                } else if !hadCachedMessages && chatMessages.isEmpty {
                    historyLoadState = .failed(String(
                        localized: "chat.history_missing_payload",
                        defaultValue: "未收到会话历史数据，请稍后重试。"
                    ))
                } else {
                    historyLoadState = .loaded
                }
                return
            }

            #if DEBUG
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[claude] history \(String(describing: mode)) loaded in \(elapsedMs)ms messages=\(messages.count) totalSeq=\(lastSeq) hasMore=\(hasMoreRemoteHistory) nextBefore=\(nextBeforeSeq.map(String.init) ?? "nil") cachedBefore=\(previousCachedCount)")
            #endif

            let prependOlderMessages: Bool = {
                if case .pageBefore = mode { return true }
                return false
            }()

            processJsonlMessages(
                messages,
                resetExisting: mode == .fullRefreshLegacy,
                prependOlderMessages: prependOlderMessages
            )
            if mode != .incremental {
                let refreshedCount = messageStore.claudeChats[surfaceID]?.count ?? 0
                if prependOlderMessages {
                    preserveExpandedHistoryWindowAfterPrepend(
                        previousCount: previousCachedCount,
                        refreshedCount: refreshedCount
                    )
                } else {
                    preserveExpandedHistoryWindowAfterFullRefresh(
                        previousCount: previousCachedCount,
                        refreshedCount: refreshedCount
                    )
                }
                messageStore.setClaudeChatHistoryCompleteness(surfaceID, hasCompleteHistory: !hasMoreRemoteHistory)
                fullHistoryState = .loaded
            }
            historyLoadState = .loaded
            if !isThinking && pendingSend != nil {
                withAnimation { pendingSend = nil }
            }
            if prependOlderMessages {
                viewTaskBag.runAfter(0.3) {
                    suppressAutoScroll = false
                    isLoadingMoreMessages = false
                }
            }
        }
    }

    func preserveExpandedHistoryWindowAfterFullRefresh(previousCount: Int, refreshedCount: Int) {
        guard displayLimit > Self.pageSize else { return }
        guard refreshedCount > previousCount else { return }

        let insertedOlderCount = refreshedCount - previousCount
        displayLimit = min(refreshedCount, displayLimit + insertedOlderCount)
    }

    func preserveExpandedHistoryWindowAfterPrepend(previousCount: Int, refreshedCount: Int) {
        guard refreshedCount > previousCount else { return }
        let insertedOlderCount = refreshedCount - previousCount
        displayLimit = min(refreshedCount, displayLimit + insertedOlderCount)
    }

    /// 将 JSONL 结构化消息转换为 UI 消息
    func processJsonlMessages(
        _ messages: [[String: Any]],
        resetExisting: Bool = false,
        prependOlderMessages: Bool = false
    ) {
        var newItems: [ClaudeChatItem] = []
        var newItemIndexes: [String: Int] = [:]
        // 收集 tool_result，用于关联到 tool_use
        var toolResults: [String: (content: String, isError: Bool)] = [:]

        // HIGH 修复：预构建去重集合，O(1) 查找替代 O(n) contains
        var existingMessages = resetExisting ? [] : (messageStore.claudeChats[surfaceID] ?? [])
        let previousMessageCount = existingMessages.count
        if resetExisting && messages.isEmpty {
            if !(messageStore.claudeChats[surfaceID] ?? []).isEmpty {
                messageStore.setClaudeChat(surfaceID, messages: [], totalSeq: lastSeq > 0 ? lastSeq : nil)
            }
            updatePlanModeState([])
            return
        }

        var existingIDs = Set(existingMessages.map(\.id))
        let existingToolIds = Set(existingMessages.compactMap(\.toolUseId))
        var seenMessageIDs = existingIDs
        var seenToolUseIDs = existingToolIds
        var reconciledLocalEcho = false
        var updatedExistingMessages = false

        // 第一遍：收集所有 tool_result
        for msg in messages {
            let blocks = msg["content"] as? [[String: Any]] ?? []
            for block in blocks {
                if (block["type"] as? String) == "tool_result",
                   let toolUseId = block["tool_use_id"] as? String {
                    let content = block["content"] as? String ?? ""
                    let isError = block["is_error"] as? Bool ?? false
                    toolResults[toolUseId] = (content, isError)
                }
            }
        }


        // 第二遍：构建消息列表
        for msg in messages {
            let type = msg["type"] as? String ?? ""
            let uuid = msg["uuid"] as? String ?? UUID().uuidString
            let seq = msg["seq"] as? Int
            let blocks = msg["content"] as? [[String: Any]] ?? []
            let stopReason = msg["stop_reason"] as? String

            if type == "user" {
                // 用户消息：只显示纯文本，跳过 tool_result
                let textBlocks = blocks.filter { ($0["type"] as? String) == "text" }
                let hasToolResult = blocks.contains { ($0["type"] as? String) == "tool_result" }
                // 纯 tool_result 消息不显示为用户消息
                if hasToolResult && textBlocks.isEmpty { continue }

                if !textBlocks.isEmpty {
                    let text = textBlocks.compactMap { $0["text"] as? String }.joined()
                    if !text.isEmpty {
                        // 过滤系统注入的 user 消息（skill 展开、任务通知等）
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("Base directory for this skill:")
                            || trimmed.hasPrefix("<task-notification>")
                            || trimmed.hasPrefix("<command-name>")
                            || trimmed.hasPrefix("<local-command-caveat>")
                            || trimmed.hasPrefix("<local-command-stdout>")
                            || trimmed.hasPrefix("<local-command-stderr>")
                            || trimmed.hasPrefix("<system-reminder>") {
                            continue
                        }
                        if !resetExisting,
                           reconcilePendingLocalEcho(
                            remoteID: uuid,
                            text: text,
                            existingMessages: &existingMessages,
                            existingIDs: &existingIDs,
                            seenMessageIDs: &seenMessageIDs
                           ) {
                            reconciledLocalEcho = true
                            continue
                        }

                        if !seenMessageIDs.contains(uuid) {
                            upsertNewItem(
                                ClaudeChatItem(id: uuid, seq: seq, role: .user, content: text, timestamp: Date()),
                                key: uuid,
                                into: &newItems,
                                indexes: &newItemIndexes
                            )
                            seenMessageIDs.insert(uuid)
                        }
                    }
                }
            } else if type == "assistant" {
                // 提取模型名（用于标注每条消息）
                let rawModel = (msg["message"] as? [String: Any])?["model"] as? String
                    ?? msg["model"] as? String
                let displayModel = formatModelName(rawModel)

                for block in blocks {
                    let blockType = block["type"] as? String ?? ""
                    switch blockType {
                    case "text":
                        if let text = block["text"] as? String, !text.isEmpty {
                            let msgID = "\(uuid)-text"
                            // 已有同 ID 消息 → 内容可能更新（流式追加），就地替换
                            if existingIDs.contains(msgID) {
                                updatedExistingMessages = updateOrAppendStreamingMessage(
                                    &newItems,
                                    newItemIndexes: &newItemIndexes,
                                    existingMessages: &existingMessages,
                                    existingIDs: existingIDs,
                                    id: msgID, role: .assistant,
                                    content: text, modelName: displayModel
                                ) || updatedExistingMessages
                            } else if !seenMessageIDs.contains(msgID) {
                                upsertNewItem(
                                    ClaudeChatItem(
                                        id: msgID, seq: seq, role: .assistant,
                                        content: text, timestamp: Date(),
                                        modelName: displayModel
                                    ),
                                    key: msgID,
                                    into: &newItems,
                                    indexes: &newItemIndexes
                                )
                                seenMessageIDs.insert(msgID)
                            }
                        }
                    case "thinking":
                        // 思考过程（extended thinking）
                        if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                            let thinkingID = "\(uuid)-thinking"
                            if !seenMessageIDs.contains(thinkingID) {
                                upsertNewItem(
                                    ClaudeChatItem(
                                        id: thinkingID, seq: seq, role: .thinking,
                                        content: thinking, timestamp: Date()
                                    ),
                                    key: thinkingID,
                                    into: &newItems,
                                    indexes: &newItemIndexes
                                )
                                seenMessageIDs.insert(thinkingID)
                            }
                        }
                    case "tool_use":
                        let toolName = block["name"] as? String ?? "Tool"
                        let toolUseId = block["id"] as? String ?? ""
                        let toolInput = block["input"] as? [String: Any] ?? [:]
                        let summary = formatToolInput(name: toolName, input: toolInput)

                        // 查找对应的 tool_result
                        let result = toolResults[toolUseId]
                        let toolState: ClaudeChatItem.ToolState
                        if let result {
                            toolState = result.isError ? .error : .completed
                        } else if stopReason == "tool_use" || stopReason == nil {
                            toolState = .running
                        } else {
                            toolState = .none
                        }

                        // O(1) 去重
                        if !seenToolUseIDs.contains(toolUseId) {
                            upsertNewItem(
                                ClaudeChatItem(
                                    id: "\(uuid)-tool-\(toolUseId.prefix(8))",
                                    seq: seq,
                                    role: .tool(name: toolName),
                                    content: summary,
                                    timestamp: Date(),
                                    toolResult: result?.content,
                                    toolState: toolState,
                                    toolUseId: toolUseId,
                                    completedAt: result != nil ? Date() : nil
                                ),
                                key: "tool-\(toolUseId)",
                                into: &newItems,
                                indexes: &newItemIndexes
                            )
                            seenToolUseIDs.insert(toolUseId)
                        }
                    default:
                        break
                    }
                }

                // 提取模型信息
                if let model = msg["model"] as? String, sessionInfo.model.isEmpty {
                    var info = sessionInfo
                    if model.contains("opus") { info.model = "Opus" }
                    else if model.contains("sonnet") { info.model = "Sonnet" }
                    else if model.contains("haiku") { info.model = "Haiku" }
                    sessionInfo = info
                }
            }
        }

        // 更新已有消息（工具状态更新）
        var all: [ClaudeChatItem] = []
        var updated = reconciledLocalEcho || updatedExistingMessages
        for item in existingMessages {
            if let toolId = item.toolUseId, item.toolState == .running,
               let result = toolResults[toolId] {
                // 创建新实例替代就地修改
                let updatedItem = ClaudeChatItem(
                    id: item.id,
                    seq: item.seq,
                    role: item.role,
                    content: item.content,
                    timestamp: item.timestamp,
                    toolResult: result.content,
                    toolState: result.isError ? .error : .completed,
                    toolUseId: item.toolUseId,
                    completedAt: Date()
                )
                all.append(updatedItem)
                updated = true
            } else {
                all.append(item)
            }
        }

        if !newItems.isEmpty {
            if prependOlderMessages {
                all = newItems + all
            } else {
                all.append(contentsOf: newItems)
            }
            updated = true
        }

        let normalizedAll = ClaudeChatItem.normalizeRunningTools(
            in: all,
            allowTrailingRunningTools: activityLabel == "tool_running"
        )
        if normalizedAll != all {
            all = normalizedAll
            updated = true
        }

        if updated {
            if !prependOlderMessages {
                preserveVisibleWindowForIncrementalAppend(
                    previousCount: previousMessageCount,
                    newCount: all.count,
                    resetExisting: resetExisting
                )
            }
            messageStore.setClaudeChat(surfaceID, messages: all)
            if let latestActivityAt = newItems.map(\.timestamp).max() {
                sessionManager.touchActivity(surfaceID: surfaceID, at: latestActivityAt)
            }
            // 有新消息到达时清空流式预览（已被结构化消息替代）
            if !newItems.isEmpty { streamingPreview = "" }

            // HIGH 修复：更新 Plan 模式缓存（避免每次渲染遍历全部消息）
            updatePlanModeState(all)
        }
    }

    func preserveVisibleWindowForIncrementalAppend(
        previousCount: Int,
        newCount: Int,
        resetExisting: Bool
    ) {
        guard !resetExisting else { return }
        guard newCount > previousCount else { return }
        guard displayLimit > Self.pageSize || !shouldAutoScroll else { return }

        let appendedCount = newCount - previousCount
        displayLimit = min(newCount, displayLimit + appendedCount)
    }

    func upsertNewItem(
        _ item: ClaudeChatItem,
        key: String,
        into newItems: inout [ClaudeChatItem],
        indexes: inout [String: Int]
    ) {
        if let index = indexes[key] {
            newItems[index] = item
        } else {
            indexes[key] = newItems.count
            newItems.append(item)
        }
    }

    func reconcilePendingLocalEcho(
        remoteID: String,
        text: String,
        existingMessages: inout [ClaudeChatItem],
        existingIDs: inout Set<String>,
        seenMessageIDs: inout Set<String>
    ) -> Bool {
        guard let pendingIndex = pendingLocalEchoes.firstIndex(where: { $0.content == text }) else {
            return false
        }

        let localEcho = pendingLocalEchoes[pendingIndex]
        guard let existingIndex = existingMessages.firstIndex(where: { $0.id == localEcho.localID }) else {
            pendingLocalEchoes.remove(at: pendingIndex)
            return false
        }

        let existingMessage = existingMessages[existingIndex]
        existingMessages[existingIndex] = ClaudeChatItem(
            id: remoteID,
            role: .user,
            content: text,
            timestamp: existingMessage.timestamp
        )
        existingIDs.remove(localEcho.localID)
        seenMessageIDs.remove(localEcho.localID)
        existingIDs.insert(remoteID)
        seenMessageIDs.insert(remoteID)
        pendingLocalEchoes.remove(at: pendingIndex)
        return true
    }

    /// 流式消息：更新已有的同 ID 消息内容，或追加新消息
    func updateOrAppendStreamingMessage(
        _ newItems: inout [ClaudeChatItem],
        newItemIndexes: inout [String: Int],
        existingMessages: inout [ClaudeChatItem],
        existingIDs: Set<String>,
        id: String, role: ClaudeChatItem.Role,
        content: String, modelName: String?
    ) -> Bool {
        // 检查已有消息中是否有同 ID 的流式消息
        if let idx = existingMessages.firstIndex(where: { $0.id == id }) {
            // 内容不变则跳过
            guard existingMessages[idx].content != content else { return false }
            // 替换为新内容（不可变：创建新实例）
            existingMessages[idx] = ClaudeChatItem(
                id: id, role: role,
                content: content, timestamp: existingMessages[idx].timestamp,
                modelName: modelName
            )
            return true
        } else if !existingIDs.contains(id) {
            upsertNewItem(
                ClaudeChatItem(
                    id: id, role: role,
                    content: content, timestamp: Date(),
                    modelName: modelName
                ),
                key: id,
                into: &newItems,
                indexes: &newItemIndexes
            )
            return true
        }
        return false
    }

    /// 将原始模型 ID 格式化为可读名称
    func formatModelName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.contains("opus") { return "Opus" }
        if raw.contains("sonnet") { return "Sonnet" }
        if raw.contains("haiku") { return "Haiku" }
        // 其他模型保留原始名（截取最后部分）
        if let last = raw.split(separator: "/").last {
            return String(last)
        }
        return raw
    }

    /// 根据最新消息列表更新 Plan 模式状态
    /// 根据最后一个 Plan 相关工具消息确定 Plan 模式状态
    /// 只有明确找到 EnterPlanMode/ExitPlanMode 时才更新，避免无关消息误重置
    func updatePlanModeState(_ messages: [ClaudeChatItem]) {
        for msg in messages.reversed() {
            if case .tool(name: let name) = msg.role {
                if name == "ExitPlanMode" { isInPlanMode = false; return }
                if name == "EnterPlanMode" { isInPlanMode = true; return }
            }
        }
        // 没找到任何 Plan 工具消息时不修改状态（保持当前值）
    }

    /// 格式化工具输入为简要描述
    func formatToolInput(name: String, input: [String: Any]) -> String {
        switch name {
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Write":
            return input["file_path"] as? String ?? ""
        case "Edit":
            return input["file_path"] as? String ?? ""
        case "Bash":
            return input["command"] as? String ?? ""
        case "Grep":
            let pattern = input["pattern"] as? String ?? ""
            let path = input["path"] as? String ?? ""
            return "\(pattern) in \(path)"
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Agent":
            return input["description"] as? String ?? input["prompt"] as? String ?? ""
        default:
            // 通用：显示第一个字符串参数
            for (_, v) in input {
                if let s = v as? String, !s.isEmpty { return String(s.prefix(100)) }
            }
            return ""
        }
    }
}
