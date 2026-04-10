import Foundation
import UserNotifications
import UIKit

/// 管理 APNs 推送通知的注册、token 生命周期和权限状态
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    /// 当前推送权限状态
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// 当前 device token（hex 字符串）
    @Published var deviceToken: String?
    /// 关联的 relay 连接（用于上报 token）
    weak var relayConnection: RelayConnection?

    private override init() {
        super.init()
    }

    // MARK: - 请求推送权限

    /// 请求推送通知权限并注册 APNs
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if let error {
                print("[push] 请求权限失败: \(error.localizedDescription)")
                return
            }
            print("[push] 权限请求结果: \(granted)")

            Task { @MainActor in
                self?.refreshAuthorizationStatus()
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        // 注册通知分类（审批操作按钮）
        registerCategories()
    }

    /// 刷新当前权限状态
    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    // MARK: - Device Token 处理

    /// 注册成功时调用（从 AppDelegate 转发）
    func didRegisterForRemoteNotifications(deviceToken token: Data) {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = tokenString
        print("[push] device token: \(tokenString.prefix(16))...")

        // 上报 token 到 relay server
        reportTokenToServer(tokenString)
    }

    /// 注册失败时调用
    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("[push] 注册失败: \(error.localizedDescription)")
    }

    // MARK: - Token 上报

    /// 将 device token 上报到 relay server
    private func reportTokenToServer(_ token: String) {
        guard let connection = relayConnection,
              !connection.serverURL.isEmpty else {
            print("[push] 无 relay 连接，跳过 token 上报")
            return
        }

        // 通过 HTTP POST 上报（不通过 WebSocket，因为可能未连接）
        let phoneID = connection.phoneID
        guard !phoneID.isEmpty else { return }

        let urlString = "https://\(connection.serverURL)/api/push/token"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "phone_id": phoneID,
            "apns_token": token,
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                print("[push] token 上报失败: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("[push] token 上报完成: status=\(httpResponse.statusCode)")
            }
        }.resume()
    }

    // MARK: - 通知分类

    /// 注册通知操作分类（审批按钮等）
    private func registerCategories() {
        let approveAction = UNNotificationAction(
            identifier: "APPROVE",
            title: "批准",
            options: [.authenticationRequired]
        )
        let denyAction = UNNotificationAction(
            identifier: "DENY",
            title: "拒绝",
            options: [.authenticationRequired, .destructive]
        )

        let approvalCategory = UNNotificationCategory(
            identifier: "APPROVAL_REQUEST",
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([approvalCategory])
    }

    // MARK: - 处理通知响应

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
}

extension Notification.Name {
    /// 从推送通知导航到指定 surface
    static let navigateToSurface = Notification.Name("navigateToSurface")
}
