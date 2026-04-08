import Foundation

/// 工具输入 JSON 解析辅助
enum ToolInputParser {
    /// 从 JSON 字符串中提取指定 key 的字符串值
    static func string(from jsonString: String, key: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[key] as? String else {
            return nil
        }
        return value
    }
}
