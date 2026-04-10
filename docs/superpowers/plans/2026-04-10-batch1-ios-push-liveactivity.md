# Batch 1 iOS: Live Activity + Push Notifications + RPC Dedup

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Dynamic Island / Live Activity for Claude status, actionable push notifications with inline approval, and RPC request deduplication to the cmux-mobile iOS app.

**Architecture:** Three independent layers: (1) shared Activity attributes model, (2) Widget Extension with Live Activity views, (3) app-side managers (LiveActivityManager, enhanced PushNotificationManager, RPC dedup in RelayConnection). Phase events from Mac drive both Live Activity updates (via WebSocket when foreground, APNs when background) and push notifications.

**Tech Stack:** Swift 5.9, SwiftUI, ActivityKit, WidgetKit, UserNotifications, iOS 17+, XcodeGen (project.yml)

**Spec:** `docs/superpowers/specs/2026-04-10-batch1-push-liveactivity-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/Models/CmuxActivityAttributes.swift` | **Create** | Shared ActivityAttributes (app + widget) |
| `cmuxWidget/CmuxLiveActivity.swift` | **Create** | Dynamic Island + Lock Screen views |
| `cmuxWidget/CmuxWidgetBundle.swift` | **Create** | Widget bundle registration |
| `cmuxWidget/Info.plist` | **Create** | Widget config (NSSupportsLiveActivities) |
| `Sources/Core/LiveActivityManager.swift` | **Create** | Activity lifecycle (create/update/end) |
| `Sources/Core/PushNotificationManager.swift` | **Modify** | Add approval action handler, Live Activity token |
| `Sources/Core/AppDelegate.swift` | **Modify** | Wire approval actions to RelayConnection |
| `Sources/Core/MessageStore.swift` | **Modify** | Handle `phase.update` events, drive LiveActivityManager |
| `Sources/Core/RelayConnection.swift` | **Modify** | Add RPC dedup (requestId cache) |
| `project.yml` | **Modify** | Add cmuxWidget extension target |
| `SupportingFiles/Info.plist` | **Modify** | Add NSSupportsLiveActivities |
| `Tests/RpcDedupTests.swift` | **Create** | Unit tests for RPC dedup logic |

---

### Task 1: CmuxActivityAttributes (Shared Model)

**Files:**
- Create: `Sources/Models/CmuxActivityAttributes.swift`

- [ ] **Step 1: Create the Activity Attributes model**

```swift
// Sources/Models/CmuxActivityAttributes.swift
import ActivityKit
import Foundation

/// Live Activity 属性 — app 和 Widget Extension 共享
struct CmuxActivityAttributes: ActivityAttributes {
    /// 动态状态（通过 push 或本地更新）
    struct ContentState: Codable, Hashable {
        var activeSessionId: String
        var projectName: String
        var phase: String            // thinking | tool_running | waiting_approval | idle | ended | error
        var toolName: String?
        var lastUserMessage: String?
        var lastAssistantSummary: String?
        var totalSessions: Int
        var activeSessions: Int
        var startedAt: TimeInterval

        var startedAtDate: Date {
            Date(timeIntervalSince1970: startedAt)
        }
    }

    /// 静态属性（创建时设置，不再变化）
    var serverName: String
}
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/jackie/code/cmux-mobile && swift build 2>&1 | grep -i "CmuxActivity" | grep error; echo "exit: $?"`
Expected: No errors for this file (UIKit errors from other files are pre-existing)

- [ ] **Step 3: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add Sources/Models/CmuxActivityAttributes.swift
git commit -m "feat(liveactivity): add CmuxActivityAttributes shared model"
```

---

### Task 2: Widget Extension — Live Activity Views

**Files:**
- Create: `cmuxWidget/CmuxLiveActivity.swift`
- Create: `cmuxWidget/CmuxWidgetBundle.swift`
- Create: `cmuxWidget/Info.plist`
- Modify: `project.yml` (add widget target)
- Modify: `SupportingFiles/Info.plist` (add NSSupportsLiveActivities)

- [ ] **Step 1: Create Widget Bundle**

```swift
// cmuxWidget/CmuxWidgetBundle.swift
import WidgetKit
import SwiftUI

@main
struct CmuxWidgetBundle: WidgetBundle {
    var body: some Widget {
        CmuxLiveActivity()
    }
}
```

- [ ] **Step 2: Create Live Activity Widget**

```swift
// cmuxWidget/CmuxLiveActivity.swift
import ActivityKit
import WidgetKit
import SwiftUI

struct CmuxLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CmuxActivityAttributes.self) { context in
            // 锁屏视图
            lockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开态
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.projectName)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            if context.state.activeSessions > 1 {
                                Text("\(context.state.activeSessions) 个会话")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let tool = context.state.toolName, context.state.phase == "tool_running" {
                            Label(String(tool.prefix(12)), systemImage: toolIcon(tool))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(phaseColor(context.state.phase))
                        } else {
                            Text(phaseLabel(context.state.phase))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(phaseColor(context.state.phase))
                        }
                        Text(context.state.startedAtDate, style: .timer)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let summary = context.state.lastAssistantSummary, !summary.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Circle()
                                .fill(phaseColor(context.state.phase))
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)
                            Text(summary)
                                .font(.system(size: 12))
                                .lineLimit(2)
                                .foregroundStyle(.primary.opacity(0.85))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
            } compactTrailing: {
                Text(compactTrailingText(context.state))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(phaseColor(context.state.phase))
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
            }
            .keylineTint(phaseColor(context.state.phase))
        }
    }

    // MARK: - 锁屏视图

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<CmuxActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 顶部行：图标 + 项目名 + 阶段 + 计时器
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)
                Text(context.state.projectName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(phaseLabel(context.state.phase))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(phaseColor(context.state.phase))
                Text(context.state.startedAtDate, style: .timer)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // 分隔线 + 消息区域
            let hasMessages = (context.state.lastUserMessage != nil || context.state.lastAssistantSummary != nil)
            if hasMessages {
                Divider().background(.white.opacity(0.2))
                if let userMsg = context.state.lastUserMessage, !userMsg.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("You:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(userMsg)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                }
                if let assistant = context.state.lastAssistantSummary, !assistant.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("Claude:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.purple.opacity(0.8))
                        Text(assistant)
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                }
            }
        }
        .padding(14)
    }

    // MARK: - 辅助

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "thinking": return .purple
        case "tool_running": return .cyan
        case "waiting_approval": return .orange
        case "idle": return .gray
        case "ended": return .green
        case "error": return .red
        default: return .gray
        }
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "thinking": return "思考中"
        case "tool_running": return "执行工具"
        case "waiting_approval": return "需要审批"
        case "idle": return "空闲"
        case "ended": return "完成"
        case "error": return "出错"
        default: return phase
        }
    }

    private func compactTrailingText(_ state: CmuxActivityAttributes.ContentState) -> String {
        if let tool = state.toolName, state.phase == "tool_running" {
            return String(tool.prefix(7))
        }
        return String(phaseLabel(state.phase).prefix(7))
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder.badge.magnifyingglass"
        default: return "wrench"
        }
    }
}
```

- [ ] **Step 3: Create Widget Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
    <key>NSSupportsLiveActivities</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Add NSSupportsLiveActivities to main app Info.plist**

In `SupportingFiles/Info.plist`, add before the closing `</dict>`:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

- [ ] **Step 5: Add widget target to project.yml**

Append to the `targets:` section in `project.yml`:

```yaml
  cmuxWidget:
    type: app-extension
    platform: iOS
    sources:
      - path: cmuxWidget
      - path: Sources/Models/CmuxActivityAttributes.swift
    settings:
      base:
        INFOPLIST_FILE: cmuxWidget/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.rooyun.devpod.widget
        PRODUCT_NAME: "cmuxWidget"
        DEVELOPMENT_TEAM: "69A75B6U2B"
        TARGETED_DEVICE_FAMILY: "1,2"
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/../../Frameworks"
        SKIP_INSTALL: "YES"
    dependencies:
      - sdk: WidgetKit.framework
      - sdk: ActivityKit.framework
```

And add widget dependency to the main `cmux-mobile` target:

```yaml
    dependencies:
      - target: cmuxWidget
```

- [ ] **Step 6: Regenerate Xcode project**

Run: `cd /Users/jackie/code/cmux-mobile && xcodegen generate 2>&1 | tail -5`
Expected: "Generated project" or similar success message. If xcodegen is not installed, manually verify project.yml is syntactically correct.

- [ ] **Step 7: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add cmuxWidget/ SupportingFiles/Info.plist project.yml Sources/Models/CmuxActivityAttributes.swift
git commit -m "feat(liveactivity): add Widget Extension with Dynamic Island and Lock Screen views"
```

---

### Task 3: LiveActivityManager

**Files:**
- Create: `Sources/Core/LiveActivityManager.swift`

- [ ] **Step 1: Create LiveActivityManager**

```swift
// Sources/Core/LiveActivityManager.swift
import ActivityKit
import Foundation

/// 管理全局单 Live Activity 的生命周期 — 创建、更新、结束
@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    /// 当前活跃的 Activity
    private var activity: Activity<CmuxActivityAttributes>?
    /// push token 上报回调（由 PushNotificationManager 设置）
    var onPushTokenUpdate: ((String) -> Void)?

    private init() {}

    // MARK: - 更新全局 Activity

    /// 创建或更新全局 Live Activity
    func updateGlobal(
        activeSessionId: String,
        projectName: String,
        phase: String,
        toolName: String? = nil,
        lastUserMessage: String? = nil,
        lastAssistantSummary: String? = nil,
        totalSessions: Int = 1,
        activeSessions: Int = 1,
        serverName: String = ""
    ) {
        let state = CmuxActivityAttributes.ContentState(
            activeSessionId: activeSessionId,
            projectName: projectName,
            phase: phase,
            toolName: toolName,
            lastUserMessage: lastUserMessage?.prefix(120).description,
            lastAssistantSummary: lastAssistantSummary?.prefix(200).description,
            totalSessions: totalSessions,
            activeSessions: activeSessions,
            startedAt: activity?.content.state.startedAt ?? Date().timeIntervalSince1970
        )

        if let existing = activity {
            Task {
                await existing.update(ActivityContent(state: state, staleDate: nil))
            }
        } else {
            startNewActivity(state: state, serverName: serverName)
        }
    }

    // MARK: - 结束 Activity

    /// 结束当前 Live Activity
    func end() {
        guard let activity else { return }
        Task {
            let finalState = CmuxActivityAttributes.ContentState(
                activeSessionId: activity.content.state.activeSessionId,
                projectName: activity.content.state.projectName,
                phase: "ended",
                toolName: nil,
                lastUserMessage: activity.content.state.lastUserMessage,
                lastAssistantSummary: activity.content.state.lastAssistantSummary,
                totalSessions: activity.content.state.totalSessions,
                activeSessions: 0,
                startedAt: activity.content.state.startedAt
            )
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 5)
            )
        }
        self.activity = nil
    }

    // MARK: - 内部

    private func startNewActivity(state: CmuxActivityAttributes.ContentState, serverName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[liveactivity] Activities not enabled")
            return
        }
        let attributes = CmuxActivityAttributes(serverName: serverName)
        do {
            let newActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: .token
            )
            self.activity = newActivity
            print("[liveactivity] Started activity: \(newActivity.id)")

            // 监听 push token 更新
            Task {
                for await tokenData in newActivity.pushTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    print("[liveactivity] Push token: \(token.prefix(16))...")
                    onPushTokenUpdate?(token)
                }
            }
        } catch {
            print("[liveactivity] Failed to start: \(error)")
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add Sources/Core/LiveActivityManager.swift
git commit -m "feat(liveactivity): add LiveActivityManager for global activity lifecycle"
```

---

### Task 4: Wire Phase Events to LiveActivityManager

**Files:**
- Modify: `Sources/Core/MessageStore.swift`

- [ ] **Step 1: Add phase.update event handler in MessageStore**

In `MessageStore.swift`, inside the `handleEvent()` method, after the existing `"notification"` case, add a new case for `"phase.update"`:

```swift
case "phase.update":
    handlePhaseUpdate(eventPayload)
```

Then add the handler method:

```swift
// MARK: - 阶段更新（驱动 Live Activity）

/// 处理 Mac 端推送的阶段变化事件
private func handlePhaseUpdate(_ payload: [String: AnyCodable]) {
    let surfaceId = payload["surface_id"]?.stringValue ?? ""
    let phase = payload["phase"]?.stringValue ?? "idle"
    let toolName = payload["tool_name"]?.stringValue
    let projectName = payload["project_name"]?.stringValue ?? ""
    let lastUserMessage = payload["last_user_message"]?.stringValue
    let lastAssistantSummary = payload["last_assistant_summary"]?.stringValue

    // 统计活跃 session 数
    let activeSurfaces = surfaces.filter { surface in
        let title = (surface["title"] as? String) ?? ""
        return title.contains("Claude")
    }

    LiveActivityManager.shared.updateGlobal(
        activeSessionId: surfaceId,
        projectName: projectName,
        phase: phase,
        toolName: toolName,
        lastUserMessage: lastUserMessage,
        lastAssistantSummary: lastAssistantSummary,
        totalSessions: activeSurfaces.count,
        activeSessions: activeSurfaces.count
    )
}
```

- [ ] **Step 2: Also drive Live Activity from existing claude.messages.update events**

In the existing `handleEvent()` method, where `"claude.messages.update"` is handled (the block that calls `onClaudeUpdate`), add Live Activity driving after the callback:

```swift
case "claude.messages.update", "claude.model_switching", "claude.model_switched", "claude.session.reset":
    // 现有逻辑...
    let rawDict: [String: Any] = // ... existing conversion
    onClaudeUpdate?(rawDict)
    
    // 驱动 Live Activity（从 status 字段推断阶段）
    if event == "claude.messages.update" {
        let status = eventPayload["status"]?.stringValue ?? "idle"
        let surfaceId = eventPayload["surface_id"]?.stringValue ?? ""
        if !surfaceId.isEmpty {
            let phase = (status == "thinking" || status == "tool_running") ? status : "idle"
            LiveActivityManager.shared.updateGlobal(
                activeSessionId: surfaceId,
                projectName: "",  // 从现有 session 信息获取
                phase: phase
            )
        }
    }
```

- [ ] **Step 3: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add Sources/Core/MessageStore.swift
git commit -m "feat(liveactivity): wire phase events to LiveActivityManager"
```

---

### Task 5: Push Notification Approval Actions

**Files:**
- Modify: `Sources/Core/PushNotificationManager.swift`

- [ ] **Step 1: Implement approval action handlers**

Replace the `handleNotificationResponse` method in `PushNotificationManager.swift` with:

```swift
/// 用户点击通知或操作按钮时调用
func handleNotificationResponse(_ response: UNNotificationResponse) {
    let userInfo = response.notification.request.content.userInfo
    let requestId = userInfo["request_id"] as? String ?? ""
    let surfaceId = userInfo["surface_id"] as? String ?? ""

    switch response.actionIdentifier {
    case "APPROVE":
        print("[push] 用户批准: request=\(requestId.prefix(8))")
        guard !requestId.isEmpty else { return }
        relayConnection?.send([
            "method": "agent.approve",
            "params": ["request_id": requestId],
        ])
    case "DENY":
        print("[push] 用户拒绝: request=\(requestId.prefix(8))")
        guard !requestId.isEmpty else { return }
        relayConnection?.send([
            "method": "agent.reject",
            "params": ["request_id": requestId],
        ])
    case UNNotificationDefaultActionIdentifier:
        print("[push] 用户点击通知: surface=\(surfaceId.prefix(8))")
        // 发送通知让 app 导航到对应 surface
        if !surfaceId.isEmpty {
            NotificationCenter.default.post(
                name: .navigateToSurface,
                object: nil,
                userInfo: ["surface_id": surfaceId]
            )
        }
    default:
        break
    }
}
```

- [ ] **Step 2: Add Notification.Name extension**

At the bottom of `PushNotificationManager.swift`, add:

```swift
extension Notification.Name {
    /// 从推送通知导航到指定 surface
    static let navigateToSurface = Notification.Name("navigateToSurface")
}
```

- [ ] **Step 3: Add Live Activity token reporting**

Add a method to report Live Activity push token to the relay server:

```swift
// MARK: - Live Activity Token

/// 上报 Live Activity push token 到 relay server
func reportLiveActivityToken(_ token: String) {
    guard let connection = relayConnection,
          !connection.serverURL.isEmpty else { return }

    let phoneID = connection.phoneID
    guard !phoneID.isEmpty else { return }

    let urlString = "https://\(connection.serverURL)/api/push/live-activity-token"
    guard let url = URL(string: urlString) else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: String] = [
        "phone_id": phoneID,
        "token": token,
        "session_id": "__global__",
    ]

    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
    request.httpBody = bodyData

    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error {
            print("[push] Live Activity token 上报失败: \(error.localizedDescription)")
            return
        }
        if let httpResponse = response as? HTTPURLResponse {
            print("[push] Live Activity token 上报: status=\(httpResponse.statusCode)")
        }
    }.resume()
}
```

- [ ] **Step 4: Wire LiveActivityManager token to PushNotificationManager**

In `cmuxMobileApp.swift` (the app entry point), inside the `.onAppear` initialization block where `PushNotificationManager` is set up, add:

```swift
// Live Activity token 上报
LiveActivityManager.shared.onPushTokenUpdate = { token in
    Task { @MainActor in
        PushNotificationManager.shared.reportLiveActivityToken(token)
    }
}
```

- [ ] **Step 5: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add Sources/Core/PushNotificationManager.swift App/cmuxMobileApp.swift
git commit -m "feat(push): implement approval actions and Live Activity token reporting"
```

---

### Task 6: RPC Request Deduplication

**Files:**
- Modify: `Sources/Core/RelayConnection.swift`
- Create: `Tests/RpcDedupTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/RpcDedupTests.swift`:

```swift
import XCTest
@testable import cmux_mobile

final class RpcDedupTests: XCTestCase {

    func testDuplicateRequestIdIsRejected() {
        let dedup = RpcDedupCache()
        XCTAssertTrue(dedup.shouldSend("req-1"))
        XCTAssertFalse(dedup.shouldSend("req-1"))  // 重复
    }

    func testDifferentRequestIdsAllowed() {
        let dedup = RpcDedupCache()
        XCTAssertTrue(dedup.shouldSend("req-1"))
        XCTAssertTrue(dedup.shouldSend("req-2"))
    }

    func testExpiredRequestIdAllowed() {
        let dedup = RpcDedupCache(ttlSeconds: 0)  // 立即过期
        XCTAssertTrue(dedup.shouldSend("req-1"))
        // 过期后应允许重发
        dedup.cleanupExpired()
        XCTAssertTrue(dedup.shouldSend("req-1"))
    }

    func testCleanupRemovesExpiredOnly() {
        let dedup = RpcDedupCache(ttlSeconds: 0)
        _ = dedup.shouldSend("req-1")
        let dedup2 = RpcDedupCache(ttlSeconds: 3600)
        _ = dedup2.shouldSend("req-2")
        dedup.cleanupExpired()
        dedup2.cleanupExpired()
        XCTAssertTrue(dedup.shouldSend("req-1"))   // 已过期，可重发
        XCTAssertFalse(dedup2.shouldSend("req-2")) // 未过期，仍拒绝
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jackie/code/cmux-mobile && swift test --filter RpcDedupTests 2>&1 | tail -5`
Expected: Compilation error — `RpcDedupCache` not found

- [ ] **Step 3: Implement RpcDedupCache**

Add to `Sources/Core/RelayConnection.swift` (at the bottom of the file, outside the RelayConnection class):

```swift
// MARK: - RPC 请求去重缓存

/// 基于 requestId 的去重缓存，防止网络重试导致重复执行
final class RpcDedupCache {
    private var sentIds: [String: Date] = [:]
    private let ttlSeconds: TimeInterval

    init(ttlSeconds: TimeInterval = 60) {
        self.ttlSeconds = ttlSeconds
    }

    /// 检查是否应发送此请求（未见过或已过期则返回 true）
    func shouldSend(_ requestId: String) -> Bool {
        cleanupExpired()
        if sentIds[requestId] != nil {
            return false  // 重复请求
        }
        sentIds[requestId] = Date()
        return true
    }

    /// 清理过期的请求记录
    func cleanupExpired() {
        let cutoff = Date().addingTimeInterval(-ttlSeconds)
        sentIds = sentIds.filter { $0.value > cutoff }
    }

    /// 清空全部记录（断连重置时使用）
    func reset() {
        sentIds.removeAll()
    }
}
```

- [ ] **Step 4: Integrate dedup into sendWithResponse**

In `RelayConnection.swift`, add a property:

```swift
/// RPC 请求去重缓存
let rpcDedup = RpcDedupCache()
```

Then modify `sendWithResponse` to add dedup check at the top:

```swift
func sendWithResponse(_ payload: [String: Any], handler: @escaping ([String: Any]) -> Void) {
    // 去重检查
    if let requestId = payload["request_id"] as? String {
        guard rpcDedup.shouldSend(requestId) else {
            print("[relay] 去重拦截: request_id=\(requestId.prefix(8))")
            return
        }
    }

    let id = payload["id"] as? Int ?? {
        // ... 现有 ID 生成逻辑
    }()
    // ... 现有发送逻辑
}
```

Also reset dedup cache on disconnect (in `handleDisconnect` or `clearPendingHandlers`):

```swift
rpcDedup.reset()
```

- [ ] **Step 5: Run tests**

Run: `cd /Users/jackie/code/cmux-mobile && swift test --filter RpcDedupTests 2>&1 | tail -10`
Expected: All 4 tests pass

- [ ] **Step 6: Commit**

```bash
cd /Users/jackie/code/cmux-mobile
git add Sources/Core/RelayConnection.swift Tests/RpcDedupTests.swift
git commit -m "feat(relay): add RPC request deduplication with 60s TTL cache"
```

---

## Verification Checklist

After all tasks:

- [ ] `swift test` passes (RpcDedupTests + existing tests)
- [ ] `xcodegen generate` produces valid project with widget target
- [ ] Xcode builds main app target without new errors
- [ ] Xcode builds cmuxWidget target without errors
- [ ] CmuxActivityAttributes is accessible from both app and widget
- [ ] PushNotificationManager APPROVE/DENY actions send RPC to relay
- [ ] LiveActivityManager.updateGlobal() creates/updates activity
- [ ] MessageStore handles `phase.update` events
- [ ] RPC dedup blocks duplicate requestIds within 60s
