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

    @Published var isPairing: Bool = false
    @Published var error: String?
    @Published var pairedDevice: PairResult?

    // MARK: - 静态工具

    /// 解析 QR 码文本，验证字段非空（nonisolated，可在任意上下文调用）
    nonisolated static func parseQRCode(_ text: String) -> QRCodeData? {
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

        return qr
    }

    // MARK: - 配对确认

    /// 向服务器发送配对确认请求，成功后将凭据存入 Keychain
    func confirmPairing(qrData: QRCodeData, phoneID: String, phoneName: String) async {
        isPairing = true
        error = nil

        defer { isPairing = false }

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
}
