# Batch 1: Push Notifications + Live Activity + Protocol Reliability

## Overview

Five features that let users monitor Claude from lock screen and Dynamic Island, receive actionable notifications, and ensure reliable message delivery.

1. **Mac 端阶段上报** — RelayBridge 检测 Claude 状态变化，推送到 relay → iPhone
2. **APNs 推送通知** — 完成/审批/出错时弹通知，审批通知带 approve/reject action
3. **Live Activity + 灵动岛** — Widget Extension，全局单 Activity，阶段驱动更新
4. **推送 token 自修复** — APNs 错误码自动清理无效 token
5. **RPC 请求去重** — requestId 防重复提交

---

## 1. Mac 端阶段上报

### 现状

RelayBridge.swift 已有 Claude 状态跟踪（lines 1169-1203）：
- `"idle"` — 空闲
- `"thinking"` — assistant 消息无 stop_reason
- `"tool_running"` — stop_reason == "tool_use"

通过 `claude.messages` 推送时已包含 `status` 字段。

### 设计

新增 `phase.update` 事件类型，**仅在状态变化时**推送（非每次消息更新）：

```swift
// Mac 端 RelayBridge — 新增阶段追踪
private var lastReportedPhase: String = "idle"

// 在 processJsonlMessages() 末尾，status 确定后：
let newPhase = status // "idle" | "thinking" | "tool_running"
if newPhase != lastReportedPhase {
    lastReportedPhase = newPhase
    pushPhaseEvent(phase: newPhase, surfaceID: surfaceID)
}
```

Phase 事件 payload：

```json
{
  "type": "event",
  "payload": {
    "event": "phase.update",
    "surface_id": "uuid",
    "phase": "thinking",
    "tool_name": "Read",
    "project_name": "cmux-mobile",
    "project_path": "/Users/jackie/code/cmux-mobile",
    "last_user_message": "帮我修复 bug",
    "last_assistant_summary": "我来看看...",
    "push_hint": {
      "event": "phase",
      "phase": "thinking",
      "summary": "Claude is thinking..."
    }
  }
}
```

新增两个额外阶段（不由 JSONL status 推断，由事件触发）：
- `"waiting_approval"` — 收到 `agent.approval_required` 事件时
- `"ended"` — Claude 输出完成且无更多活动（idle 超过 5 秒确认）

### Relay Server 行为

Server 收到 `phase.update` 事件：
1. 转发给已连接的 iPhone（现有行为）
2. 检查 `push_hint`，决定是否触发 APNs 推送（新增逻辑）
3. 检查 `push_hint`，决定是否更新 Live Activity（新增逻辑）

### 改动范围

| 项目 | 文件 | 改动 |
|------|------|------|
| cmux | `Sources/Relay/RelayBridge.swift` | 新增 `lastReportedPhase`，阶段变化时 `pushPhaseEvent()` |
| cmux | `Sources/Relay/RelayBootstrap.swift` | approval_required 事件触发 `waiting_approval` 阶段 |
| cmux-relay | Go server | 新增 APNs 推送 + Live Activity 更新逻辑 |

---

## 2. APNs 推送通知

### 触发规则

| 阶段变化 | 通知类型 | 标题 | 正文 |
|----------|---------|------|------|
| `* → ended` | completion | 项目名 或 "Claude 已完成" | 最后 assistant 摘要（前 200 字） |
| `* → waiting_approval` | approval | "需要审批" | "工具: {tool_name} — {action 摘要}" |
| tool error | error | "执行出错" | 错误摘要 |

### 审批通知 Action

使用 iOS Notification Category 实现通知内操作：

```swift
// 注册 category（PushNotificationManager）
let approveAction = UNNotificationAction(
    identifier: "APPROVE",
    title: String(localized: "notification.approve", defaultValue: "批准"),
    options: [.authenticationRequired]
)
let rejectAction = UNNotificationAction(
    identifier: "REJECT", 
    title: String(localized: "notification.reject", defaultValue: "拒绝"),
    options: [.destructive, .authenticationRequired]
)
let approvalCategory = UNNotificationCategory(
    identifier: "APPROVAL_REQUEST",
    actions: [approveAction, rejectAction],
    intentIdentifiers: []
)
```

APNs payload 格式：

```json
{
  "aps": {
    "alert": {
      "title": "需要审批",
      "body": "工具: Bash — rm -rf /tmp/test"
    },
    "category": "APPROVAL_REQUEST",
    "sound": "default",
    "mutable-content": 1
  },
  "request_id": "approval-uuid",
  "surface_id": "surface-uuid"
}
```

用户点击 "批准"/"拒绝" → `userNotificationCenter(_:didReceive:)` → 从 payload 提取 `request_id` + `surface_id` → 通过 RelayConnection 发送 `agent.approve` / `agent.reject` RPC。

### Relay Server APNs 实现

Go server 新增 APNs HTTP/2 client（借鉴 CodeLight 的 `apns.ts`）：

```go
// APNs JWT auth (ES256)
type APNsClient struct {
    keyID    string
    teamID   string
    key      *ecdsa.PrivateKey
    bundleID string
    host     string // api.push.apple.com or api.sandbox.push.apple.com
    token    string // 缓存 50 分钟
    tokenAt  time.Time
}

func (c *APNsClient) SendAlert(token string, payload AlertPayload) (*PushResult, error)
func (c *APNsClient) SendLiveActivity(token string, state ContentState, event string) (*PushResult, error)
```

终端错误检测（自修复 — 见 Feature 4）：

```go
func isTerminalError(status int, reason string) bool {
    if status == 410 { return true } // Unregistered / ExpiredToken
    if status == 400 && (reason == "BadDeviceToken" || reason == "DeviceTokenNotForTopic") { return true }
    return false
}
```

### 改动范围

| 项目 | 文件 | 改动 |
|------|------|------|
| cmux-mobile | `PushNotificationManager.swift` | 完善 category 注册，实现 action handler |
| cmux-mobile | `AppDelegate.swift` | 完善 push notification delegate 方法 |
| cmux-relay | Go server | 新增 `apns.go`（HTTP/2 client）、`push_routes.go`（token API） |

---

## 3. Live Activity + 灵动岛

### Activity Attributes

借鉴 CodeLight 的 `CodeLightActivityAttributes`，适配 cmux：

```swift
struct CmuxActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var activeSessionId: String      // 当前活跃 session 的 surface_id
        var projectName: String          // 项目名
        var phase: String                // thinking | tool_running | waiting_approval | idle | ended | error
        var toolName: String?            // 当前工具名（phase == tool_running 时）
        var lastUserMessage: String?     // 最近用户消息（前 120 字）
        var lastAssistantSummary: String? // 最近 Claude 回复（前 200 字）
        var totalSessions: Int           // 总会话数
        var activeSessions: Int          // 活跃会话数
        var startedAt: TimeInterval      // 活动开始时间戳
        
        var startedAtDate: Date {
            Date(timeIntervalSince1970: startedAt)
        }
    }
    var serverName: String               // relay server 名（静态，创建时设置）
}
```

### 灵动岛布局

**展开态：**
```
┌──────────────────────────────────────────┐
│ [🐱] 项目名 (2)      Tool: Read   0:42  │
│                                          │
│ ● Claude 正在分析代码...                  │
└──────────────────────────────────────────┘
```

- Leading: cmux 图标 + 项目名 + 活跃数
- Trailing: 工具名或阶段标签 + 阶段颜色 + 计时器
- Bottom: 最新 assistant 摘要

**紧凑态：**
```
┌──────────────┐
│ [🐱]  Think… │
└──────────────┘
```

- Leading: cmux 图标
- Trailing: 阶段/工具名（最多 7 字符截断）

**锁屏：**
```
┌──────────────────────────────────────────┐
│ [🐱] cmux-mobile  Thinking       0:42   │
│──────────────────────────────────────────│
│ You: 帮我修复这个 bug                     │
│ Claude: 我来看看 src/login.swift...      │
└──────────────────────────────────────────┘
```

### 阶段颜色映射

| 阶段 | 颜色 | 显示文本 |
|------|------|---------|
| thinking | 紫色 | 思考中 |
| tool_running | 青色 | 执行工具 |
| waiting_approval | 橙色 | 需要审批 |
| idle | 灰色 | 空闲 |
| ended | 绿色 | 完成 |
| error | 红色 | 出错 |

### LiveActivityManager

全局单例，管理一个 Activity 的生命周期：

```swift
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activity: Activity<CmuxActivityAttributes>?
    
    /// 创建或更新全局 Activity
    func updateGlobal(
        activeSessionId: String,
        projectName: String,
        phase: String,
        toolName: String?,
        lastUserMessage: String?,
        lastAssistantSummary: String?,
        totalSessions: Int,
        activeSessions: Int,
        serverName: String
    ) {
        let state = CmuxActivityAttributes.ContentState(
            activeSessionId: activeSessionId,
            projectName: projectName,
            phase: phase,
            toolName: toolName,
            lastUserMessage: lastUserMessage,
            lastAssistantSummary: lastAssistantSummary,
            totalSessions: totalSessions,
            activeSessions: activeSessions,
            startedAt: activity?.content.state.startedAt ?? Date().timeIntervalSince1970
        )
        
        if let existing = activity {
            // 更新现有 Activity
            Task {
                await existing.update(ActivityContent(state: state, staleDate: nil))
            }
        } else {
            // 创建新 Activity
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = CmuxActivityAttributes(serverName: serverName)
            activity = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: .token
            )
            // 监听 push token 更新
            Task {
                guard let activity else { return }
                for await tokenData in activity.pushTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    registerLiveActivityToken(token)
                }
            }
        }
    }
    
    /// 结束 Activity
    func end() { ... }
    
    /// 注册 Live Activity push token 到 relay server
    private func registerLiveActivityToken(_ token: String) { ... }
}
```

### Push 驱动更新

Live Activity 通过 APNs push-type `liveactivity` 更新（app 在后台时也能更新）：

- Relay server 收到 Mac 的 `phase.update` 事件
- 查找已注册的 Live Activity token
- 发送 APNs HTTP/2 请求，topic = `{bundleId}.push-type.liveactivity`
- Payload 包含 `ContentState` JSON

iPhone 在前台时也通过 WebSocket 事件直接更新（更快，不走 APNs）。

### Widget Extension 目标

新增 Xcode target `cmuxWidget`：
- `CmuxActivityAttributes.swift` — 属性定义（与 app 共享）
- `CmuxLiveActivity.swift` — 灵动岛 + 锁屏视图
- `CmuxWidgetBundle.swift` — Widget 注册
- `Info.plist` — `NSSupportsLiveActivities: true`

### 改动范围

| 项目 | 文件 | 改动 |
|------|------|------|
| cmux-mobile | 新增 `cmuxWidget/` target | Widget Extension（3 个文件） |
| cmux-mobile | 新增 `Sources/Models/CmuxActivityAttributes.swift` | 共享属性定义 |
| cmux-mobile | 新增 `Sources/Core/LiveActivityManager.swift` | Activity 生命周期管理 |
| cmux-mobile | `Sources/Core/MessageStore.swift` | phase.update 事件触发 LiveActivityManager |
| cmux-mobile | Xcode project | 新增 Widget Extension target |
| cmux-relay | Go server | `sendLiveActivityUpdate()` via HTTP/2 |

---

## 4. 推送 Token 自修复

### 问题

设备卸载 app 后 APNs token 失效，但 server 仍持有该 token。每次推送都失败。

### 设计

Relay server 在每次 APNs 推送后检查响应：

```go
result, err := apns.SendAlert(token, payload)
if err != nil { continue }

if isTerminalError(result.Status, result.Reason) {
    // 立即删除无效 token
    deleteToken(deviceID, token)
    log.Printf("[apns] terminal error %d/%s for device %s, token deleted", 
        result.Status, result.Reason, deviceID[:10])
}
```

终端错误码：
- `410` — Unregistered / ExpiredToken
- `400` + `BadDeviceToken` — 格式错误
- `400` + `DeviceTokenNotForTopic` — sandbox/production 不匹配

同样适用于 Live Activity token。

### 孤儿 token 检测

如果设备已取消所有配对（无 DeviceLink），推送前检查：

```go
func sendPushToDevice(deviceID string, payload AlertPayload) {
    // 检查设备是否仍有有效配对
    linkCount := countDeviceLinks(deviceID)
    if linkCount == 0 {
        // 孤儿设备 — 删除所有 token
        deleteAllTokens(deviceID)
        return
    }
    // 正常推送...
}
```

### 改动范围

| 项目 | 文件 | 改动 |
|------|------|------|
| cmux-relay | `apns.go` | `isTerminalError()` 判断 + 推送后自动删除 |
| cmux-relay | `push_routes.go` | token CRUD API + 孤儿检测 |

---

## 5. RPC 请求去重

### 问题

网络不稳定时，mobile 端 `sendWithResponse` 超时后可能重试。如果原始请求已到达 Mac 并执行（如 `surface.send_text`），重试会导致重复输入。

### 设计

**Mobile 端：** 为每个 RPC 请求生成唯一 `requestId`（UUID），缓存最近 60 秒内的 requestId：

```swift
// RelayConnection.swift
private var sentRequestIds: Set<String> = []
private var requestIdTimestamps: [String: Date] = [:]

func sendWithResponse(_ payload: [String: Any], handler: @escaping Handler) {
    let requestId = payload["request_id"] as? String ?? UUID().uuidString
    
    // 检查重复
    cleanupStaleRequestIds()
    guard !sentRequestIds.contains(requestId) else {
        // 已发送过，跳过
        return
    }
    
    sentRequestIds.insert(requestId)
    requestIdTimestamps[requestId] = Date()
    
    var enriched = payload
    enriched["request_id"] = requestId
    // ... 正常发送逻辑
}

private func cleanupStaleRequestIds() {
    let cutoff = Date().addingTimeInterval(-60)
    requestIdTimestamps = requestIdTimestamps.filter { $0.value > cutoff }
    sentRequestIds = Set(requestIdTimestamps.keys)
}
```

**Mac 端：** RelayBridge 缓存最近 60 秒的 `request_id → response`：

```swift
// RelayBridge.swift
private var recentResponses: [String: (response: [String: Any], timestamp: Date)] = [:]

func handleRPCRequest(_ request: [String: Any]) {
    if let requestId = request["request_id"] as? String {
        // 检查缓存
        if let cached = recentResponses[requestId] {
            sendRPCResponse(cached.response)
            return  // 返回缓存结果，不重复执行
        }
    }
    
    // 正常执行...
    let response = executeRPC(request)
    
    // 缓存结果
    if let requestId = request["request_id"] as? String {
        recentResponses[requestId] = (response, Date())
        cleanupStaleResponses()
    }
    
    sendRPCResponse(response)
}
```

### 改动范围

| 项目 | 文件 | 改动 |
|------|------|------|
| cmux-mobile | `Sources/Core/RelayConnection.swift` | 发送端去重（sentRequestIds 缓存） |
| cmux | `Sources/Relay/RelayBridge.swift` | 接收端去重（recentResponses 缓存） |

---

## 数据流总结

```
Mac (cmux)                    Relay Server (Go)              iPhone (cmux-mobile)
┌────────────────┐           ┌──────────────────┐          ┌──────────────────────┐
│ RelayBridge    │           │                  │          │                      │
│  · JSONL 监听   │──phase──→│  · 转发 WebSocket │──event──→│ MessageStore         │
│  · 状态追踪     │  update  │  · APNs HTTP/2   │          │  · phase.update 处理  │
│  · RPC 去重缓存 │          │  · Token 管理     │──push───→│ LiveActivityManager  │
│                │          │  · 自修复 token    │          │  · 灵动岛更新         │
│ approval_req   │──event──→│                  │──alert──→│ PushNotificationManager│
│                │          │                  │          │  · 通知 + 审批 action  │
└────────────────┘          └──────────────────┘          └──────────────────────┘
     ↑                                                           │
     └──── agent.approve/reject RPC ─────────────────────────────┘
```

---

## 非目标

- 不做本地消息持久化（Mac JSONL 是唯一源头）
- 不做多 Mac 支持（保持一对一配对）
- 不做 E2E 加密推送 payload（Phase 2）
- 不做通知偏好设置 UI（Phase 2，先全部推送）
- 不做像素猫动画（用 cmux 图标代替）

## 测试策略

- **ConversationTurn 模型** — 已有 7 个单元测试
- **RPC 去重** — 单元测试：重复 requestId 返回缓存、过期清理、不同 requestId 正常执行
- **Phase 上报** — 单元测试：状态变化时推送、相同状态不推送
- **Live Activity** — 需真机测试（模拟器不支持 ActivityKit）
- **APNs 推送** — 需 Apple Developer 证书 + 真机
