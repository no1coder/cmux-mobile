# P0 Chat Interaction Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add message send status feedback, conversation turn grouping with collapsible history, and code block copy feedback to the cmux-mobile iOS chat UI.

**Architecture:** Three independent features, no shared dependencies. Task 1 (copy feedback) is a small isolated change. Task 2 (send status) adds local state to ClaudeChatView. Task 3–4 (turn grouping) introduces a new model + view and rewires the chat area. All changes are in the `cmux-mobile` SPM package.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, SPM test target `cmux-mobileTests`

**Spec:** `docs/superpowers/specs/2026-04-10-p0-chat-interaction-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/Components/SyntaxHighlighter.swift` | Modify (lines 558–577) | Add copy feedback state |
| `Sources/Features/Claude/ClaudeChatView.swift` | Modify | Add PendingSend state, replace flat ForEach with TurnView |
| `Sources/Models/ConversationTurn.swift` | **Create** | Turn model + grouping algorithm |
| `Sources/Features/Claude/TurnView.swift` | **Create** | Collapsible turn view |
| `Tests/ConversationTurnTests.swift` | **Create** | Unit tests for grouping algorithm |

---

### Task 1: Code Block Copy Feedback

**Files:**
- Modify: `Sources/Components/SyntaxHighlighter.swift:558-577`

- [ ] **Step 1: Add `copied` state and update the copy button**

In `SyntaxHighlightedCodeView`, add a `@State` property and replace the button:

```swift
// In SyntaxHighlightedCodeView, add after the existing @State properties:
@State private var copied = false

// Replace the existing Button (lines 571-577) with:
Button {
    UIPasteboard.general.string = code
    copied = true
    Task {
        try? await Task.sleep(for: .seconds(1.5))
        copied = false
    }
} label: {
    Image(systemName: copied ? "checkmark" : "doc.on.doc")
        .font(.system(size: 12))
        .foregroundStyle(copied ? .green : .white.opacity(0.4))
        .contentTransition(.symbolEffect(.replace))
}
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/jackie/code/cmux-mobile && swift build 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add Sources/Components/SyntaxHighlighter.swift
git commit -m "feat(chat): add copy feedback animation to code blocks"
```

---

### Task 2: Message Send Three-Stage Status

**Files:**
- Modify: `Sources/Features/Claude/ClaudeChatView.swift`

- [ ] **Step 1: Add PendingSend model and state to ClaudeChatView**

Add these definitions inside `ClaudeChatView`, before the `body` property:

```swift
// MARK: - 发送状态

/// 消息发送阶段
private enum SendStage: Equatable {
    case sending    // WebSocket 已发出，等待 Mac ACK
    case delivered  // Mac bridge ACK 已收到
    case thinking   // Claude 开始处理
    case failed(String) // 发送失败，附带错误信息
}

/// 待确认的发送状态
@State private var pendingSend: (id: String, stage: SendStage)?
```

- [ ] **Step 2: Add the SendStatusFooter view**

Add a private view at the bottom of `ClaudeChatView` (after the `extractClaudeOutput` method, before the closing brace):

```swift
// MARK: - 发送状态指示

/// 消息发送阶段指示器（显示在聊天底部）
@ViewBuilder
private var sendStatusFooter: some View {
    if let pending = pendingSend {
        HStack(spacing: 6) {
            switch pending.stage {
            case .sending:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text(String(localized: "chat.status.sending", defaultValue: "发送中..."))
            case .delivered:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                Text(String(localized: "chat.status.delivered", defaultValue: "已送达"))
            case .thinking:
                ThinkingDotsView()
                Text(String(localized: "chat.status.thinking", defaultValue: "Claude 正在思考..."))
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

/// 三点级联动画视图
private struct ThinkingDotsView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.purple.opacity(i <= phase ? 1.0 : 0.3))
                    .frame(width: 4, height: 4)
                    .scaleEffect(i <= phase ? 1.2 : 0.8)
            }
        }
        .frame(width: 20, height: 12)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { timer in
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = (phase + 1) % 4
                }
            }
        }
    }
}
```

- [ ] **Step 3: Wire up the send lifecycle**

Modify the `send()` method to create `pendingSend` and use `sendWithResponse`:

```swift
private func send() {
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    let messageId = UUID().uuidString
    inputText = ""; showSlashMenu = false; showFilePicker = false

    // 本地立即显示用户消息
    appendMessage(ClaudeChatItem(id: messageId, role: .user, content: text, timestamp: Date()))

    // 设置发送状态
    withAnimation { pendingSend = (id: messageId, stage: .sending) }
    lastSendText = text

    // 发送到终端（使用带回调的版本）
    relayConnection.sendWithResponse([
        "method": "surface.send_text",
        "params": ["surface_id": surfaceID, "text": text + "\n"],
    ]) { result in
        let resultDict = result["result"] as? [String: Any] ?? result
        if resultDict["error"] as? String != nil {
            withAnimation { pendingSend = (id: messageId, stage: .failed("发送失败")) }
            return
        }
        // Mac ACK 成功 → delivered
        withAnimation { pendingSend = (id: messageId, stage: .delivered) }
        isThinking = true
    }
}
```

Also add a stored property for retry:

```swift
/// 上一次发送的文本（用于重试）
@State private var lastSendText = ""
```

And the retry method:

```swift
private func retrySend() {
    guard let pending = pendingSend, case .failed = pending.stage else { return }
    withAnimation { pendingSend = (id: pending.id, stage: .sending) }
    relayConnection.sendWithResponse([
        "method": "surface.send_text",
        "params": ["surface_id": surfaceID, "text": lastSendText + "\n"],
    ]) { result in
        let resultDict = result["result"] as? [String: Any] ?? result
        if resultDict["error"] as? String != nil {
            withAnimation { pendingSend = (id: pending.id, stage: .failed("发送失败")) }
            return
        }
        withAnimation { pendingSend = (id: pending.id, stage: .delivered) }
        isThinking = true
    }
}
```

- [ ] **Step 4: Transition stages on Claude response**

In the `startWatching()` method, inside the `onClaudeUpdate` callback where `processJsonlMessages` is called (around line 960-971), add stage transitions:

```swift
// After: processJsonlMessages(messages)
// Add:

// 更新发送状态：收到 assistant/thinking 消息 → thinking 阶段
if let pending = pendingSend,
   pending.stage == .delivered || pending.stage == .sending {
    let hasAssistantOrThinking = messages.contains { msg in
        let type = msg["type"] as? String ?? ""
        return type == "assistant"
    }
    if hasAssistantOrThinking || status == "thinking" || status == "tool_running" {
        withAnimation { pendingSend = (id: pending.id, stage: .thinking) }
    }
}

// 收到完整 assistant 回复（非 thinking 状态）→ 清除发送状态
if !isThinking && pendingSend != nil {
    withAnimation { pendingSend = nil }
}
```

Also add the same clearing logic in `fetchMessages()` after `processJsonlMessages(messages)`:

```swift
// 轮询拉取也清除发送状态
if !isThinking && pendingSend != nil {
    withAnimation { pendingSend = nil }
}
```

- [ ] **Step 5: Render sendStatusFooter in the chat area**

In the `chatArea` computed property, add `sendStatusFooter` inside the `LazyVStack`, right after the `isThinking` streaming preview block and before the `Color.clear` spacer:

```swift
// After:
if isThinking {
    streamingPreviewView.id("thinking")
}

// Add:
sendStatusFooter
    .id("send-status")

// Keep:
Color.clear.frame(height: 4).id("end")
```

- [ ] **Step 6: Also wire sendComposedMessage**

In `sendComposedMessage()`, add the same pending state (after `appendMessage`, before `sender.send`):

```swift
// After appendMessage:
withAnimation { pendingSend = (id: UUID().uuidString, stage: .sending) }
lastSendText = displayText

// Note: ComposedMessageSender uses fire-and-forget (send, not sendWithResponse),
// so transition to .delivered after a short delay as a heuristic:
Task {
    try? await Task.sleep(for: .seconds(1.0))
    if let p = pendingSend, p.stage == .sending {
        withAnimation { pendingSend = (id: p.id, stage: .delivered) }
    }
}
isThinking = true
```

- [ ] **Step 7: Build and verify**

Run: `cd /Users/jackie/code/cmux-mobile && swift build 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 8: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add Sources/Features/Claude/ClaudeChatView.swift
git commit -m "feat(chat): add three-stage send status feedback (sending/delivered/thinking)"
```

---

### Task 3: ConversationTurn Model + Grouping Algorithm

**Files:**
- Create: `Sources/Models/ConversationTurn.swift`
- Create: `Tests/ConversationTurnTests.swift`

- [ ] **Step 1: Write tests for the grouping algorithm**

Create `Tests/ConversationTurnTests.swift`:

```swift
import XCTest
@testable import cmux_mobile

final class ConversationTurnTests: XCTestCase {

    // MARK: - 空消息列表

    func testEmptyMessages() {
        let turns = ConversationTurn.group([])
        XCTAssertTrue(turns.isEmpty)
    }

    // MARK: - 单个用户消息（无回复）

    func testSingleUserMessage() {
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "hello", timestamp: Date())
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].question?.id, "u1")
        XCTAssertTrue(turns[0].replies.isEmpty)
    }

    // MARK: - 标准多轮对话

    func testMultiTurnConversation() {
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "Q1", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "A1", timestamp: Date()),
            ClaudeChatItem(id: "t1", role: .tool(name: "Bash"), content: "ls", timestamp: Date()),
            ClaudeChatItem(id: "u2", role: .user, content: "Q2", timestamp: Date()),
            ClaudeChatItem(id: "a2", role: .assistant, content: "A2", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 2)
        // Turn 1
        XCTAssertEqual(turns[0].question?.content, "Q1")
        XCTAssertEqual(turns[0].replies.count, 2) // a1 + t1
        XCTAssertEqual(turns[0].replyCount, 2)
        // Turn 2
        XCTAssertEqual(turns[1].question?.content, "Q2")
        XCTAssertEqual(turns[1].replies.count, 1) // a2
    }

    // MARK: - 会话开头有 assistant 消息（无 user 前缀）

    func testSessionStartReplies() {
        let items = [
            ClaudeChatItem(id: "a0", role: .assistant, content: "Welcome", timestamp: Date()),
            ClaudeChatItem(id: "u1", role: .user, content: "Hi", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "Hello", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 2)
        // Session start pseudo-turn
        XCTAssertNil(turns[0].question)
        XCTAssertTrue(turns[0].isSessionStart)
        XCTAssertEqual(turns[0].replies.count, 1) // a0
        // Turn 1
        XCTAssertEqual(turns[1].question?.content, "Hi")
        XCTAssertEqual(turns[1].replies.count, 1)
    }

    // MARK: - 只有 assistant 消息（全部是 session start）

    func testOnlyAssistantMessages() {
        let items = [
            ClaudeChatItem(id: "a1", role: .assistant, content: "A1", timestamp: Date()),
            ClaudeChatItem(id: "a2", role: .assistant, content: "A2", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns[0].isSessionStart)
        XCTAssertEqual(turns[0].replies.count, 2)
    }

    // MARK: - Thinking 和 Tool 归入正确的 Turn

    func testThinkingAndToolsGroupedCorrectly() {
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "fix bug", timestamp: Date()),
            ClaudeChatItem(id: "th1", role: .thinking, content: "let me think", timestamp: Date()),
            ClaudeChatItem(id: "t1", role: .tool(name: "Read"), content: "file.swift", timestamp: Date()),
            ClaudeChatItem(id: "t2", role: .tool(name: "Edit"), content: "file.swift", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "Fixed", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].replies.count, 4) // th1, t1, t2, a1
    }

    // MARK: - 连续 user 消息各自成为独立 Turn

    func testConsecutiveUserMessages() {
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "Q1", timestamp: Date()),
            ClaudeChatItem(id: "u2", role: .user, content: "Q2", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "A", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].question?.content, "Q1")
        XCTAssertTrue(turns[0].replies.isEmpty)
        XCTAssertEqual(turns[1].question?.content, "Q2")
        XCTAssertEqual(turns[1].replies.count, 1)
    }
}
```

- [ ] **Step 2: Run tests — they should fail**

Run: `cd /Users/jackie/code/cmux-mobile && swift test --filter ConversationTurnTests 2>&1 | tail -10`
Expected: Compilation error — `ConversationTurn` not found

- [ ] **Step 3: Implement ConversationTurn model**

Create `Sources/Models/ConversationTurn.swift`:

```swift
import Foundation

/// 对话轮次 — 一个用户问题 + Claude 的所有回复（直到下一个用户消息）
struct ConversationTurn: Identifiable {
    /// 使用第一条用户消息 ID，或 "__session_start__"
    let id: String
    /// 用户消息（session start pseudo-turn 为 nil）
    let question: ClaudeChatItem?
    /// 所有回复（assistant + thinking + tool + system）
    let replies: [ClaudeChatItem]

    /// 是否为会话开始的伪 Turn（开头的非 user 消息）
    var isSessionStart: Bool { question == nil }

    /// 回复数量（用于折叠态显示）
    var replyCount: Int { replies.count }

    /// 排序用序号（第一条消息在原始列表中的位置）
    let firstIndex: Int

    /// 将平铺消息列表分组为对话轮次
    static func group(_ items: [ClaudeChatItem]) -> [ConversationTurn] {
        guard !items.isEmpty else { return [] }

        var turns: [ConversationTurn] = []
        // 收集会话开始前的非 user 消息
        var pendingReplies: [ClaudeChatItem] = []
        var currentQuestion: ClaudeChatItem?
        var currentReplies: [ClaudeChatItem] = []
        var currentFirstIndex = 0

        for (index, item) in items.enumerated() {
            if item.role == .user {
                // 遇到新的 user 消息：关闭前一个 Turn
                if let q = currentQuestion {
                    turns.append(ConversationTurn(
                        id: q.id, question: q,
                        replies: currentReplies, firstIndex: currentFirstIndex
                    ))
                } else if !pendingReplies.isEmpty {
                    // 会话开头的非 user 消息 → session start pseudo-turn
                    turns.append(ConversationTurn(
                        id: "__session_start__", question: nil,
                        replies: pendingReplies, firstIndex: 0
                    ))
                    pendingReplies = []
                }
                currentQuestion = item
                currentReplies = []
                currentFirstIndex = index
            } else {
                if currentQuestion != nil {
                    currentReplies.append(item)
                } else {
                    pendingReplies.append(item)
                }
            }
        }

        // 关闭最后一个 Turn
        if let q = currentQuestion {
            turns.append(ConversationTurn(
                id: q.id, question: q,
                replies: currentReplies, firstIndex: currentFirstIndex
            ))
        } else if !pendingReplies.isEmpty {
            turns.append(ConversationTurn(
                id: "__session_start__", question: nil,
                replies: pendingReplies, firstIndex: 0
            ))
        }

        return turns
    }
}
```

- [ ] **Step 4: Run tests — they should pass**

Run: `cd /Users/jackie/code/cmux-mobile && swift test --filter ConversationTurnTests 2>&1 | tail -15`
Expected: All 7 tests pass

- [ ] **Step 5: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add Sources/Models/ConversationTurn.swift Tests/ConversationTurnTests.swift
git commit -m "feat(chat): add ConversationTurn model with grouping algorithm and tests"
```

---

### Task 4: TurnView + ClaudeChatView Integration

**Files:**
- Create: `Sources/Features/Claude/TurnView.swift`
- Modify: `Sources/Features/Claude/ClaudeChatView.swift`

- [ ] **Step 1: Create TurnView**

Create `Sources/Features/Claude/TurnView.swift`:

```swift
import SwiftUI

/// 对话轮次视图 — 折叠态显示问题摘要 + 回复数，展开态显示全部回复
struct TurnView: View {
    let turn: ConversationTurn
    let isExpanded: Bool
    let onToggle: () -> Void
    let onToolTap: (ClaudeChatItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            turnHeader
            if isExpanded {
                repliesSection
            }
        }
    }

    // MARK: - Turn Header

    private var turnHeader: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 8) {
                // 左侧竖线
                RoundedRectangle(cornerRadius: 1)
                    .fill(turn.isSessionStart ? Color.purple.opacity(0.5) : Color.purple)
                    .frame(width: 2)
                    .frame(height: headerContentHeight)

                // 内容
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // 角色标签
                        Text(turn.isSessionStart
                            ? String(localized: "turn.session_start", defaultValue: "会话开始")
                            : "YOU")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(CMColors.textTertiary)

                        Spacer()

                        // 回复计数
                        if turn.replyCount > 0 {
                            Text(String(localized: "turn.reply_count \(turn.replyCount)",
                                        defaultValue: "\(turn.replyCount) 条回复"))
                                .font(.system(size: 10))
                                .foregroundStyle(CMColors.textTertiary)
                        }

                        // 展开/折叠箭头
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CMColors.textTertiary)
                    }

                    // 问题文本预览
                    if let question = turn.question {
                        Text(question.content)
                            .font(.system(size: 14))
                            .foregroundStyle(CMColors.textPrimary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 估算 header 内容高度（用于左侧竖线）
    private var headerContentHeight: CGFloat {
        turn.question != nil ? 44 : 20
    }

    // MARK: - Replies Section

    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(turn.replies.enumerated()), id: \.element.id) { index, reply in
                VStack(spacing: 0) {
                    // 节奏间距：同类消息 2pt，类型切换 10pt
                    if index > 0 {
                        let prevRole = turn.replies[index - 1].role
                        let spacing: CGFloat = isSameRoleGroup(prevRole, reply.role) ? 2 : 10
                        Spacer().frame(height: spacing)
                    }

                    HStack(alignment: .top, spacing: 0) {
                        // 左侧连接线
                        Rectangle()
                            .fill(CMColors.textTertiary.opacity(0.15))
                            .frame(width: 1)
                            .padding(.leading, 1)  // 对齐 header 的 2pt 竖线中心

                        Spacer().frame(width: 9)

                        ChatMessageRow(msg: reply, onToolTap: onToolTap)
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    /// 判断两个 role 是否属于同一组（用于间距决策）
    private func isSameRoleGroup(_ a: ClaudeChatItem.Role, _ b: ClaudeChatItem.Role) -> Bool {
        switch (a, b) {
        case (.tool, .tool): return true
        case (.assistant, .assistant): return true
        case (.thinking, .thinking): return true
        default: return false
        }
    }
}
```

- [ ] **Step 2: Add turn state and grouping to ClaudeChatView**

In `ClaudeChatView`, add state for expanded turns (near the other `@State` properties):

```swift
/// 展开的 Turn ID 集合
@State private var expandedTurnIds: Set<String> = []
```

Add a computed property for turns (near the `chatMessages` computed property):

```swift
/// 将平铺消息分组为对话轮次
private var chatTurns: [ConversationTurn] {
    ConversationTurn.group(chatMessages)
}
```

- [ ] **Step 3: Replace flat ForEach with TurnView in chatArea**

In the `chatArea` computed property, replace the flat message loop (the `ForEach(chatMessages)` block, approximately lines 238-242):

**Replace:**
```swift
ForEach(chatMessages) { msg in
    ChatMessageRow(msg: msg) { tool in
        selectedTool = tool
    }.id(msg.id)
}
```

**With:**
```swift
ForEach(chatTurns) { turn in
    TurnView(
        turn: turn,
        isExpanded: expandedTurnIds.contains(turn.id),
        onToggle: { toggleTurn(turn.id) },
        onToolTap: { tool in selectedTool = tool }
    )
    .id(turn.id)
}
```

- [ ] **Step 4: Add the toggleTurn method and auto-expand logic**

Add at the end of ClaudeChatView (before the closing brace):

```swift
// MARK: - Turn 折叠管理

/// 切换 Turn 展开/折叠状态
private func toggleTurn(_ turnId: String) {
    withAnimation(.easeInOut(duration: 0.2)) {
        if expandedTurnIds.contains(turnId) {
            expandedTurnIds.remove(turnId)
        } else {
            expandedTurnIds.insert(turnId)
        }
    }
}

/// 自动展开最后一个 Turn，折叠其余
private func autoExpandLastTurn() {
    let turns = chatTurns
    guard let lastTurn = turns.last else { return }
    expandedTurnIds = [lastTurn.id]
}
```

- [ ] **Step 5: Call autoExpandLastTurn on message updates**

In the `.onChange(of: chatMessages.count)` modifier (around line 272), add `autoExpandLastTurn()` when new messages arrive:

**Replace:**
```swift
.onChange(of: chatMessages.count) { oldCount, newCount in
    if oldCount == 0 && newCount > 0 {
        // 首次加载消息，无动画直接跳到底部
        proxy.scrollTo("end", anchor: .bottom)
    } else if newCount > oldCount {
        // 新增消息，平滑滚动到底部
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("end", anchor: .bottom)
        }
    }
}
```

**With:**
```swift
.onChange(of: chatMessages.count) { oldCount, newCount in
    if oldCount == 0 && newCount > 0 {
        autoExpandLastTurn()
        proxy.scrollTo("end", anchor: .bottom)
    } else if newCount > oldCount {
        autoExpandLastTurn()
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("end", anchor: .bottom)
        }
    }
}
```

- [ ] **Step 6: Build and verify**

Run: `cd /Users/jackie/code/cmux-mobile && swift build 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 7: Run all tests**

Run: `cd /Users/jackie/code/cmux-mobile && swift test 2>&1 | tail -15`
Expected: All tests pass (including ConversationTurnTests)

- [ ] **Step 8: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add Sources/Features/Claude/TurnView.swift Sources/Features/Claude/ClaudeChatView.swift
git commit -m "feat(chat): add conversation turn grouping with collapsible history"
```

---

## Verification Checklist

After all tasks complete:

- [ ] `swift build` succeeds with no warnings
- [ ] `swift test` — all tests pass
- [ ] Code block copy button shows checkmark feedback for 1.5s
- [ ] Sending a message shows sending → delivered → thinking status
- [ ] Failed send shows error + retry button
- [ ] Chat history groups into collapsible turns
- [ ] Last turn auto-expands, previous turns auto-collapse
- [ ] Tapping a collapsed turn expands it
- [ ] Session start messages (no user prefix) show as "会话开始" pseudo-turn
