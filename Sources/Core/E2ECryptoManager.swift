import Foundation
import CryptoKit

/// E2E 加密管理器，使用 ChaChaPoly 对 relay 消息载荷进行端到端加密
/// 与 Mac 端使用相同的密钥派生和加密算法，relay 服务器为零知识中继
struct E2ECryptoManager {

    /// 协议版本
    private static let version = 1

    /// 派生后的对称密钥
    private let symmetricKey: SymmetricKey

    /// 使用 pairSecret 派生加密密钥
    /// - Parameter pairSecret: 配对时协商的共享密钥
    init(pairSecret: String) {
        // HKDF-SHA256 派生 256-bit 密钥
        let ikm = SymmetricKey(data: Data(pairSecret.utf8))
        let salt = Data("cmux-e2e-v1".utf8)
        let info = Data("encryption".utf8)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        self.symmetricKey = derivedKey
    }

    // MARK: - 加密

    /// 加密业务载荷字典
    /// - Parameter payload: 明文载荷
    /// - Returns: 包含 e2e 标记、nonce、密文的字典；失败返回 nil
    func encrypt(_ payload: [String: Any]) -> [String: Any]? {
        guard let plaintext = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        guard let sealedBox = try? ChaChaPoly.seal(plaintext, using: symmetricKey) else {
            return nil
        }

        let nonceBase64 = sealedBox.nonce.withUnsafeBytes { Data($0) }.base64EncodedString()
        let ciphertextBase64 = sealedBox.ciphertext.base64EncodedString()
        let tagBase64 = sealedBox.tag.base64EncodedString()

        return [
            "e2e": true,
            "v": Self.version,
            "nonce": nonceBase64,
            "ct": "\(ciphertextBase64):\(tagBase64)"
        ]
    }

    // MARK: - 解密

    /// 解密 E2E 载荷字典
    /// - Parameter payload: 包含 e2e 标记的加密载荷
    /// - Returns: 解密后的明文字典；失败返回 nil
    func decrypt(_ payload: [String: Any]) -> [String: Any]? {
        guard Self.isEncrypted(payload),
              let nonceBase64 = payload["nonce"] as? String,
              let ct = payload["ct"] as? String else {
            return nil
        }

        // 解析 nonce
        guard let nonceData = Data(base64Encoded: nonceBase64),
              let nonce = try? ChaChaPoly.Nonce(data: nonceData) else {
            return nil
        }

        // 解析 ciphertext:tag
        let parts = ct.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let ciphertextData = Data(base64Encoded: String(parts[0])),
              let tagData = Data(base64Encoded: String(parts[1])) else {
            return nil
        }

        // 构造 SealedBox 并解密
        guard let sealedBox = try? ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: ciphertextData,
            tag: tagData
        ),
              let plaintext = try? ChaChaPoly.open(sealedBox, using: symmetricKey) else {
            return nil
        }

        // 反序列化为字典
        guard let result = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            return nil
        }

        return result
    }

    // MARK: - 检测

    /// 检查载荷是否为 E2E 加密格式
    static func isEncrypted(_ payload: [String: Any]) -> Bool {
        guard let e2e = payload["e2e"] as? Bool, e2e,
              let v = payload["v"] as? Int, v == version else {
            return false
        }
        return true
    }
}
