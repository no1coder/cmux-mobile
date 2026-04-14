import Combine
import Foundation

// MARK: - 数据模型

/// QR 码解码后的配对信息
struct QRCodeData: Codable {
    let serverURL: String
    let deviceID: String
    let pairToken: String

    enum CodingKeys: String, CodingKey {
        case serverURL = "server_url"
        case deviceID = "device_id"
        case pairToken = "pair_token"
    }
}

/// 配对成功后的结果
struct PairResult: Equatable {
    let deviceID: String
    let deviceName: String
    let pairSecret: String
    let serverURL: String
}

// MARK: - 服务端响应

private struct PairConfirmResponse: Codable {
    let deviceID: String
    let deviceName: String
    let pairSecret: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceName = "device_name"
        case pairSecret = "pair_secret"
    }
}

// MARK: - PairingManager

/// 管理二维码扫描和配对确认流程
@MainActor
final class PairingManager: ObservableObject {
    nonisolated static let selfHostedServerKey = "selfHostedServerURL"
    nonisolated static let defaultServerURL = "devpod.rooyun.com"

    @Published var isPairing: Bool = false
    @Published var error: String?
    @Published var pairedDevice: PairResult?

    // MARK: - 静态工具

    /// 解析 QR 码文本，验证字段非空（nonisolated，可在任意上下文调用）
    nonisolated static func parseQRCode(_ text: String, allowedHosts: Set<String>? = nil) -> QRCodeData? {
        guard let data = text.data(using: .utf8),
              let qr = try? JSONDecoder().decode(QRCodeData.self, from: data) else {
            return nil
        }

        // 验证所有必填字段非空
        guard !qr.serverURL.isEmpty,
              !qr.deviceID.isEmpty,
              !qr.pairToken.isEmpty else {
            return nil
        }

        guard let normalizedAuthority = normalizedServerAuthority(qr.serverURL),
              isAllowedServerHost(normalizedAuthority, allowedHosts: allowedHosts) else {
            return nil
        }

        return QRCodeData(
            serverURL: normalizedAuthority,
            deviceID: qr.deviceID,
            pairToken: qr.pairToken
        )
    }

    nonisolated static func normalizedServerAuthority(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("://"),
              !trimmed.contains("/"),
              !trimmed.contains("?"),
              !trimmed.contains("#") else {
            return nil
        }

        let components = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        switch components.count {
        case 1:
            guard let host = normalizedHostname(String(components[0])) else { return nil }
            return host
        case 2:
            let hostPart = String(components[0])
            let portPart = String(components[1])
            guard let host = normalizedHostname(hostPart),
                  let port = Int(portPart),
                  (1...65535).contains(port) else {
                return nil
            }
            return "\(host):\(port)"
        default:
            return nil
        }
    }

    nonisolated static func normalizedServerHost(_ raw: String) -> String? {
        normalizedServerAuthority(raw)
    }

    nonisolated static func isAllowedServerHost(_ host: String, allowedHosts: Set<String>? = nil) -> Bool {
        let resolvedHosts = allowedHosts ?? configuredAllowedHosts()
        guard let normalized = normalizedServerAuthority(host) else { return false }
        return resolvedHosts.contains(normalized)
    }

    nonisolated static func configuredAllowedHosts() -> Set<String> {
        var hosts: Set<String> = [defaultServerURL]
        #if canImport(Security)
        if let saved = KeychainHelper.load(key: selfHostedServerKey),
           let normalized = normalizedServerAuthority(saved) {
            hosts.insert(normalized)
        }
        #endif
        return hosts
    }

    // MARK: - 配对确认

    /// 向服务器发送配对确认请求，成功后将凭据存入 Keychain
    func confirmPairing(qrData: QRCodeData, phoneID: String, phoneName: String) async {
        isPairing = true
        error = nil

        defer { isPairing = false }

        guard Self.isAllowedServerHost(qrData.serverURL) else {
            error = "不受信任的服务器地址"
            return
        }

        let urlString = "https://\(qrData.serverURL)/api/pair/confirm"
        guard let url = URL(string: urlString) else {
            error = "无效的服务器地址"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "device_id": qrData.deviceID,
            "pair_token": qrData.pairToken,
            "phone_id": phoneID,
            "phone_name": phoneName
        ]

        guard let bodyData = try? JSONEncoder().encode(body) else {
            error = "请求编码失败"
            return
        }
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                error = "服务器返回错误"
                return
            }

            let decoded = try JSONDecoder().decode(PairConfirmResponse.self, from: data)
            let result = PairResult(
                deviceID: decoded.deviceID,
                deviceName: decoded.deviceName,
                pairSecret: decoded.pairSecret,
                serverURL: qrData.serverURL
            )

            // 将凭据安全存入 Keychain
            #if canImport(Security)
            try KeychainHelper.save(key: "pairSecret_\(decoded.deviceID)", value: decoded.pairSecret)
            try KeychainHelper.save(key: "serverURL_\(decoded.deviceID)", value: qrData.serverURL)
            #endif

            pairedDevice = result

        } catch let keychainError as KeychainError {
            error = "Keychain 存储失败: \(keychainError)"
        } catch {
            self.error = "配对失败: \(error.localizedDescription)"
        }
    }

    private nonisolated static func normalizedHostname(_ raw: String) -> String? {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard !host.isEmpty,
              host.unicodeScalars.allSatisfy(allowed.contains),
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains("..") else {
            return nil
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return nil }
        for label in labels {
            guard !label.isEmpty,
                  !label.hasPrefix("-"),
                  !label.hasSuffix("-") else {
                return nil
            }
        }

        return host
    }
}
