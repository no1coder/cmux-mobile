import Testing
import Foundation
@testable import cmux_mobile

@Suite("SyntaxHighlighter Tests")
struct SyntaxHighlighterTests {

    // MARK: - 语言规则查找

    @Test("Swift 语言规则可用")
    func swiftRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "swift") != nil)
    }

    @Test("Python 语言规则可用（含别名）")
    func pythonRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "python") != nil)
        #expect(SyntaxHighlighter.rules(for: "py") != nil)
    }

    @Test("JavaScript 语言规则可用（含别名）")
    func jsRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "javascript") != nil)
        #expect(SyntaxHighlighter.rules(for: "js") != nil)
        #expect(SyntaxHighlighter.rules(for: "jsx") != nil)
    }

    @Test("TypeScript 语言规则可用")
    func tsRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "typescript") != nil)
        #expect(SyntaxHighlighter.rules(for: "ts") != nil)
        #expect(SyntaxHighlighter.rules(for: "tsx") != nil)
    }

    @Test("Go 语言规则可用")
    func goRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "go") != nil)
        #expect(SyntaxHighlighter.rules(for: "golang") != nil)
    }

    @Test("Rust 语言规则可用")
    func rustRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "rust") != nil)
        #expect(SyntaxHighlighter.rules(for: "rs") != nil)
    }

    @Test("不支持的语言返回 nil")
    func unsupportedLanguageReturnsNil() {
        #expect(SyntaxHighlighter.rules(for: "brainfuck") == nil)
        #expect(SyntaxHighlighter.rules(for: "") == nil)
    }

    @Test("语言名大小写不敏感")
    func caseInsensitive() {
        #expect(SyntaxHighlighter.rules(for: "Swift") != nil)
        #expect(SyntaxHighlighter.rules(for: "PYTHON") != nil)
        #expect(SyntaxHighlighter.rules(for: "JavaScript") != nil)
    }

    // MARK: - 所有支持语言检查

    @Test("Bash 语言规则可用")
    func bashRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "bash") != nil)
        #expect(SyntaxHighlighter.rules(for: "sh") != nil)
        #expect(SyntaxHighlighter.rules(for: "zsh") != nil)
    }

    @Test("SQL 语言规则可用")
    func sqlRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "sql") != nil)
    }

    @Test("JSON/YAML 语言规则可用")
    func jsonYamlRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "json") != nil)
        #expect(SyntaxHighlighter.rules(for: "yaml") != nil)
        #expect(SyntaxHighlighter.rules(for: "yml") != nil)
    }

    @Test("HTML/CSS 语言规则可用")
    func htmlCssRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "html") != nil)
        #expect(SyntaxHighlighter.rules(for: "xml") != nil)
        #expect(SyntaxHighlighter.rules(for: "css") != nil)
        #expect(SyntaxHighlighter.rules(for: "scss") != nil)
    }

    @Test("C/C++ 语言规则可用")
    func cCppRulesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "c") != nil)
        #expect(SyntaxHighlighter.rules(for: "cpp") != nil)
        #expect(SyntaxHighlighter.rules(for: "h") != nil)
    }

    @Test("Java/Kotlin/Ruby 语言规则可用")
    func otherLanguagesAvailable() {
        #expect(SyntaxHighlighter.rules(for: "java") != nil)
        #expect(SyntaxHighlighter.rules(for: "kotlin") != nil)
        #expect(SyntaxHighlighter.rules(for: "kt") != nil)
        #expect(SyntaxHighlighter.rules(for: "ruby") != nil)
        #expect(SyntaxHighlighter.rules(for: "rb") != nil)
    }

    // MARK: - highlight 输出测试

    @Test("highlight 返回正确行数")
    func highlightLineCount() {
        let code = "let x = 1\nlet y = 2\nlet z = 3"
        let result = SyntaxHighlighter.highlight(code: code, language: "swift")
        #expect(result.count == 3)
    }

    @Test("highlight 空代码返回单行")
    func highlightEmptyCode() {
        let result = SyntaxHighlighter.highlight(code: "", language: "swift")
        #expect(result.count == 1)
    }

    @Test("highlight 不支持语言使用通用高亮")
    func highlightFallbackGeneric() {
        let result = SyntaxHighlighter.highlight(code: "hello world", language: "unknown")
        #expect(result.count == 1)
        #expect(result[0].count >= 1)
    }

    // MARK: - 关键字高亮测试

    @Test("Swift 关键字被正确标记")
    func swiftKeywordsHighlighted() {
        let code = "func hello() { return true }"
        let tokens = SyntaxHighlighter.highlight(code: code, language: "swift")
        let firstLine = tokens[0]

        let keywordTokens = firstLine.filter { $0.color == .keyword }
        let keywordTexts = keywordTokens.map { $0.text }
        #expect(keywordTexts.contains("func"))
        #expect(keywordTexts.contains("return"))
        #expect(keywordTexts.contains("true"))
    }

    @Test("Swift 类型关键字被标记")
    func swiftTypeKeywordsHighlighted() {
        let code = "let name: String = \"hello\""
        let tokens = SyntaxHighlighter.highlight(code: code, language: "swift")
        let firstLine = tokens[0]

        let typeTokens = firstLine.filter { $0.color == .typeKeyword }
        let typeTexts = typeTokens.map { $0.text }
        #expect(typeTexts.contains("String"))
    }

    // MARK: - 字符串高亮测试

    @Test("字符串字面量被标记")
    func stringLiteralsHighlighted() {
        let code = "let msg = \"hello world\""
        let tokens = SyntaxHighlighter.highlight(code: code, language: "swift")
        let firstLine = tokens[0]

        let stringTokens = firstLine.filter { $0.color == .string }
        #expect(stringTokens.count >= 1)
        let combined = stringTokens.map { $0.text }.joined()
        #expect(combined.contains("hello world"))
    }

    // MARK: - 数字高亮测试

    @Test("数字被标记")
    func numbersHighlighted() {
        let code = "let x = 42"
        let tokens = SyntaxHighlighter.highlight(code: code, language: "swift")
        let firstLine = tokens[0]

        let numberTokens = firstLine.filter { $0.color == .number }
        #expect(numberTokens.count >= 1)
        #expect(numberTokens.first?.text == "42")
    }

    @Test("十六进制数字被标记")
    func hexNumbersHighlighted() {
        let code = "let color = 0xFF00FF"
        let tokens = SyntaxHighlighter.highlight(code: code, language: "swift")
        let firstLine = tokens[0]

        let numberTokens = firstLine.filter { $0.color == .number }
        #expect(numberTokens.count >= 1)
    }

    @Test("浮点数被标记")
    func floatNumbersHighlighted() {
        let code = "let pi = 3.14"
        let tokens = SyntaxHighlighter.highlight(code: code, language: "swift")
        let firstLine = tokens[0]

        let numberTokens = firstLine.filter { $0.color == .number }
        #expect(numberTokens.count >= 1)
    }

    // MARK: - 注释高亮测试

    @Test("单行注释被标记")
    func singleLineCommentHighlighted() {
        let code = "// this is a comment"
        let tokens = SyntaxHighlighter.highlight(code: code, language: "swift")
        let firstLine = tokens[0]

        let commentTokens = firstLine.filter { $0.color == .comment }
        #expect(commentTokens.count >= 1)
    }

    @Test("多行注释跨行被标记")
    func multiLineCommentHighlighted() {
        let code = "/* start\nmiddle\nend */"
        let tokens = SyntaxHighlighter.highlight(code: code, language: "swift")

        // 所有三行都应包含注释 token
        for line in tokens {
            let commentTokens = line.filter { $0.color == .comment }
            #expect(commentTokens.count >= 1)
        }
    }

    // MARK: - Python 特定测试

    @Test("Python 关键字高亮")
    func pythonKeywords() {
        let code = "def hello():\n    return None"
        let tokens = SyntaxHighlighter.highlight(code: code, language: "python")

        let line1Keywords = tokens[0].filter { $0.color == .keyword }.map { $0.text }
        #expect(line1Keywords.contains("def"))

        let line2Keywords = tokens[1].filter { $0.color == .keyword }.map { $0.text }
        #expect(line2Keywords.contains("return"))
        #expect(line2Keywords.contains("None"))
    }

    @Test("Python 注释使用 #")
    func pythonComment() {
        let code = "# this is a comment"
        let tokens = SyntaxHighlighter.highlight(code: code, language: "python")
        let commentTokens = tokens[0].filter { $0.color == .comment }
        #expect(commentTokens.count >= 1)
    }
}
