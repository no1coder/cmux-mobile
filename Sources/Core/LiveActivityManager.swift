import Combine
import Foundation
#if os(iOS)
import ActivityKit
#endif

/// 管理全局单 Live Activity 的生命周期 — 创建、更新、结束
@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    #if os(iOS)
    /// 当前活跃的 Activity
    private var activity: Activity<CmuxActivityAttributes>?
    #endif

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
        #if os(iOS)
        let state = CmuxActivityAttributes.ContentState(
            activeSessionId: activeSessionId,
            projectName: projectName,
            phase: phase,
            toolName: toolName,
            lastUserMessage: lastUserMessage.map { String($0.prefix(120)) },
            lastAssistantSummary: lastAssistantSummary.map { String($0.prefix(200)) },
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
        #endif
    }

    // MARK: - 结束 Activity

    /// 结束当前 Live Activity
    func end() {
        #if os(iOS)
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
        #endif
    }

    // MARK: - 内部

    #if os(iOS)
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
            Task { [weak self] in
                for await tokenData in newActivity.pushTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    print("[liveactivity] Push token: \(token.prefix(16))...")
                    await MainActor.run {
                        self?.onPushTokenUpdate?(token)
                    }
                }
            }
        } catch {
            print("[liveactivity] Failed to start: \(error)")
        }
    }
    #endif
}
