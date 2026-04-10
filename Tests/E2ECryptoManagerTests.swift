import Testing
import Foundation
@testable import cmux_mobile

@Suite("E2ECryptoManager Tests")
struct E2ECryptoManagerTests {

    // MARK: - 加密/解密往返测试

    @Test("加密后解密应还原原始数据")
    func encryptDecryptRoundTrip() {
        let crypto = E2ECryptoManager(pairSecret: "test-secret-key-1234567890")
        let original: [String: Any] = [
            "type": "event",
            "payload": "hello world",
        ]

        let encrypted = crypto.encrypt(original)
        #expect(encrypted != nil)
        #expect(encrypted?["e2e"] as? Bool == true)
        #expect(encrypted?["v"] as? Int == 1)
        #expect(encrypted?["nonce"] != nil)
        #expect(encrypted?["ct"] != nil)

        let decrypted = crypto.decrypt(encrypted!)
        #expect(decrypted != nil)
        #expect(decrypted?["type"] as? String == "event")
        #expect(decrypted?["payload"] as? String == "hello world")
    }

    @Test("不同 pairSecret 无法解密")
    func differentSecretCannotDecrypt() {
        let crypto1 = E2ECryptoManager(pairSecret: "secret-alpha")
        let crypto2 = E2ECryptoManager(pairSecret: "secret-beta")

        let payload: [String: Any] = ["msg": "sensitive"]
        let encrypted = crypto1.encrypt(payload)
        #expect(encrypted != nil)

        let decrypted = crypto2.decrypt(encrypted!)
        #expect(decrypted == nil)
    }

    @Test("空 payload 加密解密")
    func emptyPayloadRoundTrip() {
        let crypto = E2ECryptoManager(pairSecret: "empty-test")
        let original: [String: Any] = [:]

        let encrypted = crypto.encrypt(original)
        #expect(encrypted != nil)

        let decrypted = crypto.decrypt(encrypted!)
        #expect(decrypted != nil)
        // 空字典解密后键数为 0
        #expect(decrypted?.keys.count == 0)
    }

    @Test("复杂嵌套数据加密解密")
    func nestedPayloadRoundTrip() {
        let crypto = E2ECryptoManager(pairSecret: "nested-test-secret")
        let original: [String: Any] = [
            "method": "surface.list",
            "params": ["surface_id": "surf-001", "lines": [1, 2, 3]],
            "id": 42,
        ]

        let encrypted = crypto.encrypt(original)
        #expect(encrypted != nil)

        let decrypted = crypto.decrypt(encrypted!)
        #expect(decrypted != nil)
        #expect(decrypted?["method"] as? String == "surface.list")
        #expect(decrypted?["id"] as? Int == 42)

        let params = decrypted?["params"] as? [String: Any]
        #expect(params?["surface_id"] as? String == "surf-001")
    }

    // MARK: - isEncrypted 检测

    @Test("isEncrypted 识别加密载荷")
    func isEncryptedDetectsEncrypted() {
        let encrypted: [String: Any] = ["e2e": true, "v": 1, "nonce": "abc", "ct": "xyz"]
        #expect(E2ECryptoManager.isEncrypted(encrypted) == true)
    }

    @Test("isEncrypted 拒绝非加密载荷")
    func isEncryptedRejectsPlain() {
        let plain: [String: Any] = ["type": "event", "payload": [:]]
        #expect(E2ECryptoManager.isEncrypted(plain) == false)
    }

    @Test("isEncrypted 拒绝版本不匹配")
    func isEncryptedRejectsWrongVersion() {
        let wrongVersion: [String: Any] = ["e2e": true, "v": 2]
        #expect(E2ECryptoManager.isEncrypted(wrongVersion) == false)
    }

    @Test("isEncrypted 拒绝 e2e=false")
    func isEncryptedRejectsE2EFalse() {
        let notEncrypted: [String: Any] = ["e2e": false, "v": 1]
        #expect(E2ECryptoManager.isEncrypted(notEncrypted) == false)
    }

    // MARK: - 解密异常处理

    @Test("篡改密文解密返回 nil")
    func corruptedCiphertextReturnsNil() {
        let crypto = E2ECryptoManager(pairSecret: "tamper-test")
        let original: [String: Any] = ["data": "secret"]
        let encrypted = crypto.encrypt(original)!

        // 篡改密文
        var tampered = encrypted
        tampered["ct"] = "corrupted-base64-data"

        let decrypted = crypto.decrypt(tampered)
        #expect(decrypted == nil)
    }

    @Test("篡改 nonce 解密返回 nil")
    func corruptedNonceReturnsNil() {
        let crypto = E2ECryptoManager(pairSecret: "nonce-tamper")
        let original: [String: Any] = ["data": "test"]
        let encrypted = crypto.encrypt(original)!

        var tampered = encrypted
        tampered["nonce"] = "bad-nonce"

        let decrypted = crypto.decrypt(tampered)
        #expect(decrypted == nil)
    }

    @Test("缺少必要字段解密返回 nil")
    func missingFieldsReturnsNil() {
        let crypto = E2ECryptoManager(pairSecret: "fields-test")

        // 缺少 ct
        let noCT: [String: Any] = ["e2e": true, "v": 1, "nonce": "abc"]
        #expect(crypto.decrypt(noCT) == nil)

        // 缺少 nonce
        let noNonce: [String: Any] = ["e2e": true, "v": 1, "ct": "xyz"]
        #expect(crypto.decrypt(noNonce) == nil)
    }

    // MARK: - 同一 pairSecret 多次加密产生不同密文

    @Test("相同数据多次加密产生不同密文（随机 nonce）")
    func sameDataDifferentCiphertext() {
        let crypto = E2ECryptoManager(pairSecret: "nonce-uniqueness")
        let payload: [String: Any] = ["msg": "hello"]

        let enc1 = crypto.encrypt(payload)
        let enc2 = crypto.encrypt(payload)

        #expect(enc1 != nil)
        #expect(enc2 != nil)

        // nonce 应不同
        let nonce1 = enc1?["nonce"] as? String
        let nonce2 = enc2?["nonce"] as? String
        #expect(nonce1 != nonce2)
    }
}
