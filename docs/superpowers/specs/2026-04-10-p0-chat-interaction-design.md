# P0 Chat Interaction Improvements

Three high-priority improvements to Claude chat interaction UX, informed by competitive analysis of CodeLight.

## 1. Message Send Three-Stage Status

### Problem

User presses send and sees nothing until Claude responds (2–5 seconds). On unstable networks the gap is longer and the user has no idea whether the message was received.

### Design

#### Data Model

```swift
enum SendStage: Equatable {
    case sending    // WebSocket frame sent, awaiting Mac ACK
    case delivered  // Mac bridge ACK received
    case thinking   // First claude.messages.update with assistant/thinking content
}

struct PendingSend: Identifiable {
    let id: String          // matches the user ClaudeChatItem.id
    let text: String        // message preview (first 80 chars)
    var stage: SendStage
    let sentAt: Date
}
```

#### Lifecycle

1. User taps send → `ClaudeChatView` creates `PendingSend(.sending)`, appends user message to chat, calls `relayConnection.sendWithResponse`.
2. `sendWithResponse` callback fires (Mac ACK) → stage becomes `.delivered`.
3. `claude.messages.update` event arrives containing an assistant or thinking block → stage becomes `.thinking`.
4. First real `ClaudeChatItem` with `role == .assistant` is appended to chat → `pendingSend` is set to `nil`. The existing `isThinking` indicator takes over from here.

Timeout: if no ACK within 30 seconds (existing `sendWithResponse` timeout), show inline error "发送失败，点击重试".

#### UI — `SendStatusFooter`

Rendered as a small view below the last message, above the input bar:

```
┌─────────────────────────────────────────┐
│  ● 发送中...                            │  ← .sending (pulsing dot)
│  ✓ 已送达                               │  ← .delivered (checkmark, green, 0.8s then auto-transition)
│  ● Claude 正在思考...                    │  ← .thinking (cascading 3-dot animation)
└─────────────────────────────────────────┘
```

- Font: `.footnote`, secondary text color
- Animated transitions between stages (`.opacity` + `.slide`)
- The `.delivered` stage auto-transitions to `.thinking` visually after 0.8 seconds even if the phase event hasn't arrived yet — this keeps the UI feeling responsive. The actual stage enum still waits for the real event.
- On send failure: red text "发送失败" + "重试" button that re-invokes `sendWithResponse`.

#### Files Changed

| File | Change |
|------|--------|
| `ClaudeChatView.swift` | Add `@State pendingSend: PendingSend?`, manage lifecycle, render `SendStatusFooter` |
| `ClaudeChatView.swift` | New private `SendStatusFooter` view (inline, ~40 lines) |

No new files needed. All state is local to `ClaudeChatView`.

---

## 2. Conversation Turn Grouping with Collapsible History

### Problem

Long conversations are a flat list of messages. Users cannot navigate to previous questions, and scrolling through tool-heavy responses is tedious.

### Design

#### Data Model

```swift
struct ConversationTurn: Identifiable {
    let id: String                      // first user message ID, or "__session_start__"
    let question: ClaudeChatItem?       // nil for session-start pseudo-turn
    let questionImages: [Data]?         // attached images from user
    let replies: [ClaudeChatItem]       // all non-user messages until next user message
    let firstSeq: Int                   // for stable ordering
}
```

New file: `Sources/Features/Claude/ConversationTurn.swift` (~30 lines, model only).

#### Grouping Algorithm

In `ClaudeChatView`, a computed property or method transforms `[ClaudeChatItem]` → `[ConversationTurn]`:

```
for each item in claudeChats[surfaceID]:
    if item.role == .user:
        start new Turn(question: item, replies: [])
    else:
        append to current Turn's replies
    
if first items are non-user:
    create Turn(id: "__session_start__", question: nil, replies: [...])
```

Runs on every message update. The list is small enough (typically <100 turns) that O(n) grouping is negligible.

#### Collapse State

```swift
@State private var expandedTurnIds: Set<String> = []
```

- On message update: if turns changed, auto-expand the **last** turn, collapse all others.
- User tap on a turn header toggles that turn in `expandedTurnIds`.
- When user sends a new message: the previously-last turn auto-collapses, new turn auto-expands.

#### TurnView — New File

`Sources/Features/Claude/TurnView.swift` (~120 lines)

**Collapsed state:**
```
┌────────────────────────────────────────┐
│ ▸  YOU  修复登录页面的 bug，用户点击...  │
│         3 条回复                        │
└────────────────────────────────────────┘
```

- Left: 2pt vertical accent bar (brand color)
- "YOU" label: monospaced, small caps, tracking 1.0
- Question text: 2-line truncated, secondary color
- Reply count badge: "N 条回复"
- Right: `chevron.right`

**Expanded state:**
```
┌────────────────────────────────────────┐
│ ▾  YOU  修复登录页面的 bug，用户点击... │
│                                        │
│  ┊  [assistant] 我来看看这个文件...     │  ← 2pt spacing
│  ┊  [tool: Read] src/login.swift       │  ← 2pt spacing (same type)
│  ┊  [tool: Edit] src/login.swift       │  ← 2pt spacing (same type)
│  ┊                                     │  ← 10pt spacing (type change)
│  ┊  [assistant] 已修复，问题是...       │
└────────────────────────────────────────┘
```

- Same header but chevron points down
- Replies rendered via existing `ChatMessageRow`
- Spacing rhythm: 2pt between same-type consecutive messages, 10pt at type transitions
- Left vertical rail (1pt, subtle gray) connecting all replies visually

**Session start pseudo-turn:**
- Header: sparkle icon + "会话开始" instead of "YOU"
- Always collapsed by default, expandable

#### ClaudeChatView Changes

Replace the current flat `ForEach(messages)` with `ForEach(turns)`:

```swift
// Before:
ForEach(messages) { item in
    ChatMessageRow(item: item)
}

// After:
ForEach(turns) { turn in
    TurnView(
        turn: turn,
        isExpanded: expandedTurnIds.contains(turn.id),
        onToggle: { toggleTurn(turn.id) }
    )
}
```

The existing `ChatMessageRow` is reused inside `TurnView` — no changes to message rendering.

#### Files Changed

| File | Change |
|------|--------|
| `ConversationTurn.swift` | **New file** — model struct (~30 lines) |
| `TurnView.swift` | **New file** — turn view with collapse/expand (~120 lines) |
| `ClaudeChatView.swift` | Add grouping logic, replace flat ForEach, manage `expandedTurnIds` |

---

## 3. Code Block Copy Feedback

### Problem

The copy button in `SyntaxHighlightedCodeView` works but gives no visual feedback. Users don't know if the copy succeeded.

### Design

Add `@State private var copied = false` to the view. On tap:

1. Copy to `UIPasteboard.general`
2. Set `copied = true`
3. Icon changes from `doc.on.doc` to `checkmark` with green tint
4. After 1.5 seconds, reset `copied = false` (icon reverts)

```swift
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

- `.contentTransition(.symbolEffect(.replace))` gives a smooth icon swap animation (iOS 17+)
- No other changes needed

#### Files Changed

| File | Change |
|------|--------|
| `SyntaxHighlighter.swift` | Add `@State copied`, modify Button (~8 lines changed) |

---

## Non-Goals

- No question navigator sheet (P1, can add later on top of Turn model)
- No haptic feedback (P1)
- No Dynamic Island / Live Activity (P1)
- No slash command discovery (P1)
- No changes to relay server or Go backend
- No changes to MessageStore or RelayConnection

## Testing Considerations

Per project test quality policy, these are UI state changes. Meaningful tests:

- `ConversationTurn` grouping: unit test the grouping algorithm with various message sequences (empty, single turn, multi-turn, session-start messages)
- `PendingSend` lifecycle: unit test stage transitions
- Copy feedback: visual-only, no behavioral test needed
