import SwiftUI
import UIKit

/// 轻量级语法高亮器 — 支持主流编程语言的关键字、字符串、注释着色
/// 采用正则匹配方式，无需依赖第三方库
enum SyntaxHighlighter {

    // MARK: - 语言配置

    /// 语言高亮规则
    struct LanguageRules {
        let keywords: Set<String>
        let typeKeywords: Set<String>
        let builtins: Set<String>
        let singleLineComment: String
        let multiLineCommentStart: String
        let multiLineCommentEnd: String
        let stringDelimiters: [Character]
    }

    /// 获取语言规则（根据代码块语言标识）
    static func rules(for language: String) -> LanguageRules? {
        switch language.lowercased() {
        case "swift":
            return swiftRules
        case "python", "py":
            return pythonRules
        case "javascript", "js", "jsx":
            return javascriptRules
        case "typescript", "ts", "tsx":
            return typescriptRules
        case "go", "golang":
            return goRules
        case "rust", "rs":
            return rustRules
        case "java":
            return javaRules
        case "c", "cpp", "c++", "cc", "cxx", "h", "hpp":
            return cppRules
        case "ruby", "rb":
            return rubyRules
        case "bash", "sh", "zsh", "shell":
            return bashRules
        case "sql":
            return sqlRules
        case "json":
            return jsonRules
        case "yaml", "yml":
            return yamlRules
        case "html", "xml", "svg":
            return htmlRules
        case "css", "scss", "less":
            return cssRules
        case "kotlin", "kt":
            return kotlinRules
        default:
            return nil
        }
    }

    // MARK: - 高亮颜色

    /// 语法元素颜色
    enum TokenColor {
        case keyword      // 关键字 — 紫色
        case typeKeyword  // 类型 — 青色
        case string       // 字符串 — 橙色
        case number       // 数字 — 蓝色
        case comment      // 注释 — 灰色
        case builtin      // 内置函数 — 黄色
        case normal       // 普通文本

        var color: Color {
            switch self {
            case .keyword:     return Color(red: 0.78, green: 0.46, blue: 0.93)   // 紫
            case .typeKeyword: return Color(red: 0.35, green: 0.78, blue: 0.82)   // 青
            case .string:      return Color(red: 0.90, green: 0.58, blue: 0.30)   // 橙
            case .number:      return Color(red: 0.45, green: 0.65, blue: 0.95)   // 蓝
            case .comment:     return Color(red: 0.55, green: 0.55, blue: 0.58)   // 灰
            case .builtin:     return Color(red: 0.85, green: 0.75, blue: 0.35)   // 黄
            case .normal:      return Color(red: 0.85, green: 0.85, blue: 0.85)   // 浅灰白
            }
        }
    }

    /// 高亮后的文本片段
    struct Token {
        let text: String
        let color: TokenColor
    }

    // MARK: - 高亮入口

    /// 将代码文本按语言高亮，返回着色 token 列表（按行分组）
    static func highlight(code: String, language: String) -> [[Token]] {
        guard let rules = rules(for: language) else {
            // 不支持的语言，尝试通用高亮
            return highlightGeneric(code: code)
        }
        return highlightWithRules(code: code, rules: rules)
    }

    /// 将 token 列表转为 SwiftUI Text（单行）
    static func coloredText(tokens: [Token]) -> Text {
        var result = Text("")
        for token in tokens {
            result = result + Text(token.text).foregroundColor(token.color.color)
        }
        return result
    }

    // MARK: - 核心高亮逻辑

    private static func highlightWithRules(code: String, rules: LanguageRules) -> [[Token]] {
        let lines = code.components(separatedBy: "\n")
        var result: [[Token]] = []
        var inMultiLineComment = false

        for line in lines {
            var tokens: [Token] = []
            var i = line.startIndex

            while i < line.endIndex {
                // 多行注释结束
                if inMultiLineComment {
                    if let endRange = line.range(of: rules.multiLineCommentEnd, range: i..<line.endIndex) {
                        let commentText = String(line[i..<endRange.upperBound])
                        tokens.append(Token(text: commentText, color: .comment))
                        i = endRange.upperBound
                        inMultiLineComment = false
                    } else {
                        tokens.append(Token(text: String(line[i...]), color: .comment))
                        break
                    }
                    continue
                }

                // 多行注释开始
                if !rules.multiLineCommentStart.isEmpty &&
                   line[i...].hasPrefix(rules.multiLineCommentStart) {
                    // 安全偏移：确保不越界
                    guard let searchStart = line.index(i, offsetBy: rules.multiLineCommentStart.count, limitedBy: line.endIndex) else {
                        // 行末不够长，整行剩余部分作为注释开始
                        tokens.append(Token(text: String(line[i...]), color: .comment))
                        inMultiLineComment = true
                        break
                    }
                    if let endRange = line.range(of: rules.multiLineCommentEnd,
                                                  range: searchStart..<line.endIndex) {
                        let commentText = String(line[i..<endRange.upperBound])
                        tokens.append(Token(text: commentText, color: .comment))
                        i = endRange.upperBound
                    } else {
                        tokens.append(Token(text: String(line[i...]), color: .comment))
                        inMultiLineComment = true
                        break
                    }
                    continue
                }

                // 单行注释
                if !rules.singleLineComment.isEmpty &&
                   line[i...].hasPrefix(rules.singleLineComment) {
                    tokens.append(Token(text: String(line[i...]), color: .comment))
                    break
                }

                // 字符串
                let ch = line[i]
                if rules.stringDelimiters.contains(ch) {
                    let stringResult = consumeString(line: line, from: i, delimiter: ch)
                    tokens.append(Token(text: stringResult.text, color: .string))
                    i = stringResult.end
                    continue
                }

                // 数字（含小数点和负号后的数字）
                if ch.isNumber || (ch == "." && i < line.endIndex && line.index(after: i) < line.endIndex && line[line.index(after: i)].isNumber) {
                    let numResult = consumeNumber(line: line, from: i)
                    tokens.append(Token(text: numResult.text, color: .number))
                    i = numResult.end
                    continue
                }

                // 标识符 / 关键字
                if ch.isLetter || ch == "_" || ch == "$" || ch == "@" {
                    let wordResult = consumeWord(line: line, from: i)
                    let word = wordResult.text

                    if rules.keywords.contains(word) {
                        tokens.append(Token(text: word, color: .keyword))
                    } else if rules.typeKeywords.contains(word) {
                        tokens.append(Token(text: word, color: .typeKeyword))
                    } else if rules.builtins.contains(word) {
                        tokens.append(Token(text: word, color: .builtin))
                    } else {
                        tokens.append(Token(text: word, color: .normal))
                    }
                    i = wordResult.end
                    continue
                }

                // 其他字符
                tokens.append(Token(text: String(ch), color: .normal))
                i = line.index(after: i)
            }

            result.append(tokens)
        }

        return result
    }

    /// 通用高亮（无语言规则时）：仅识别字符串和数字
    private static func highlightGeneric(code: String) -> [[Token]] {
        let lines = code.components(separatedBy: "\n")
        return lines.map { line in
            [Token(text: line, color: .normal)]
        }
    }

    // MARK: - Token 消费器

    private static func consumeString(line: String, from start: String.Index, delimiter: Character) -> (text: String, end: String.Index) {
        var i = line.index(after: start)
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\\" {
                // 跳过转义字符
                i = line.index(after: i)
                if i < line.endIndex {
                    i = line.index(after: i)
                }
                continue
            }
            if ch == delimiter {
                i = line.index(after: i)
                return (String(line[start..<i]), i)
            }
            i = line.index(after: i)
        }
        return (String(line[start...]), line.endIndex)
    }

    private static func consumeNumber(line: String, from start: String.Index) -> (text: String, end: String.Index) {
        var i = start
        var hasDot = false
        // 支持 0x 十六进制前缀
        if i < line.endIndex && line[i] == "0" {
            let next = line.index(after: i)
            if next < line.endIndex && (line[next] == "x" || line[next] == "X") {
                i = line.index(after: next)
                while i < line.endIndex && line[i].isHexDigit {
                    i = line.index(after: i)
                }
                return (String(line[start..<i]), i)
            }
        }
        while i < line.endIndex {
            let ch = line[i]
            if ch == "." && !hasDot {
                hasDot = true
                i = line.index(after: i)
            } else if ch.isNumber {
                i = line.index(after: i)
            } else {
                break
            }
        }
        return (String(line[start..<i]), i)
    }

    private static func consumeWord(line: String, from start: String.Index) -> (text: String, end: String.Index) {
        var i = start
        while i < line.endIndex {
            let ch = line[i]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "$" {
                i = line.index(after: i)
            } else {
                break
            }
        }
        return (String(line[start..<i]), i)
    }
}

// MARK: - 语言规则定义

extension SyntaxHighlighter {

    static let swiftRules = LanguageRules(
        keywords: ["import", "func", "var", "let", "if", "else", "guard", "return", "switch", "case", "default",
                    "for", "while", "repeat", "break", "continue", "in", "where", "do", "try", "catch", "throw",
                    "throws", "async", "await", "class", "struct", "enum", "protocol", "extension", "typealias",
                    "init", "deinit", "self", "Self", "super", "nil", "true", "false", "static", "private",
                    "public", "internal", "fileprivate", "open", "override", "final", "lazy", "weak", "unowned",
                    "mutating", "nonmutating", "some", "any", "as", "is", "inout", "defer", "associatedtype"],
        typeKeywords: ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional",
                       "Result", "Error", "Void", "Any", "AnyObject", "Never", "Data", "URL", "Date",
                       "View", "Text", "Color", "Image", "Button", "VStack", "HStack", "ZStack",
                       "ObservableObject", "Published", "StateObject", "State", "Binding", "Environment"],
        builtins: ["print", "debugPrint", "fatalError", "precondition", "assert", "map", "filter",
                   "reduce", "forEach", "compactMap", "flatMap", "sorted", "contains", "isEmpty"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\""]
    )

    static let pythonRules = LanguageRules(
        keywords: ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as",
                    "try", "except", "finally", "raise", "with", "yield", "lambda", "pass", "break",
                    "continue", "and", "or", "not", "in", "is", "del", "global", "nonlocal", "assert",
                    "async", "await", "True", "False", "None", "self"],
        typeKeywords: ["int", "float", "str", "bool", "list", "dict", "tuple", "set", "bytes",
                       "type", "object", "Exception", "Optional", "Any", "Union", "List", "Dict"],
        builtins: ["print", "len", "range", "enumerate", "zip", "map", "filter", "sorted", "isinstance",
                   "input", "open", "super", "property", "staticmethod", "classmethod"],
        singleLineComment: "#",
        multiLineCommentStart: "",
        multiLineCommentEnd: "",
        stringDelimiters: ["\"", "'"]
    )

    static let javascriptRules = LanguageRules(
        keywords: ["function", "var", "let", "const", "if", "else", "for", "while", "do", "switch",
                    "case", "default", "break", "continue", "return", "throw", "try", "catch", "finally",
                    "new", "delete", "typeof", "instanceof", "in", "of", "class", "extends", "super",
                    "this", "import", "export", "from", "async", "await", "yield", "true", "false",
                    "null", "undefined", "void", "static", "get", "set"],
        typeKeywords: ["Array", "Object", "String", "Number", "Boolean", "Symbol", "BigInt",
                       "Map", "Set", "WeakMap", "WeakSet", "Promise", "Date", "RegExp", "Error"],
        builtins: ["console", "JSON", "Math", "parseInt", "parseFloat", "setTimeout", "setInterval",
                   "fetch", "require", "module", "process", "Buffer"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'", "`"]
    )

    static let typescriptRules = LanguageRules(
        keywords: javascriptRules.keywords.union(["type", "interface", "enum", "namespace", "declare",
                    "abstract", "implements", "readonly", "keyof", "as", "is", "never", "unknown",
                    "any", "private", "public", "protected", "override"]),
        typeKeywords: javascriptRules.typeKeywords.union(["Partial", "Required", "Readonly", "Record",
                       "Pick", "Omit", "Exclude", "Extract", "ReturnType", "Parameters", "void"]),
        builtins: javascriptRules.builtins,
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'", "`"]
    )

    static let goRules = LanguageRules(
        keywords: ["func", "var", "const", "type", "struct", "interface", "map", "chan", "if", "else",
                    "for", "range", "switch", "case", "default", "break", "continue", "return", "go",
                    "select", "defer", "package", "import", "true", "false", "nil", "fallthrough",
                    "goto"],
        typeKeywords: ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32",
                       "uint64", "float32", "float64", "complex64", "complex128", "string", "bool",
                       "byte", "rune", "error", "any", "comparable"],
        builtins: ["fmt", "len", "cap", "make", "new", "append", "copy", "delete", "close",
                   "panic", "recover", "print", "println"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'", "`"]
    )

    static let rustRules = LanguageRules(
        keywords: ["fn", "let", "mut", "const", "if", "else", "match", "for", "while", "loop",
                    "return", "break", "continue", "struct", "enum", "impl", "trait", "type", "use",
                    "mod", "pub", "crate", "self", "super", "as", "in", "ref", "move", "async",
                    "await", "where", "true", "false", "unsafe", "extern", "dyn", "static"],
        typeKeywords: ["i8", "i16", "i32", "i64", "i128", "u8", "u16", "u32", "u64", "u128",
                       "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result",
                       "Box", "Rc", "Arc", "Cell", "RefCell", "HashMap", "HashSet", "Self"],
        builtins: ["println", "eprintln", "format", "panic", "todo", "unimplemented", "assert",
                   "assert_eq", "assert_ne", "dbg", "vec", "Some", "None", "Ok", "Err"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\""]
    )

    static let javaRules = LanguageRules(
        keywords: ["public", "private", "protected", "static", "final", "abstract", "class", "interface",
                    "extends", "implements", "new", "this", "super", "if", "else", "for", "while", "do",
                    "switch", "case", "default", "break", "continue", "return", "try", "catch", "finally",
                    "throw", "throws", "import", "package", "void", "null", "true", "false",
                    "synchronized", "volatile", "transient", "native", "instanceof", "enum", "assert"],
        typeKeywords: ["int", "long", "short", "byte", "float", "double", "char", "boolean",
                       "String", "Integer", "Long", "Double", "Float", "Boolean", "Object",
                       "List", "Map", "Set", "ArrayList", "HashMap", "Optional"],
        builtins: ["System", "Math", "Arrays", "Collections", "Thread", "Runnable"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"]
    )

    static let cppRules = LanguageRules(
        keywords: ["if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue",
                    "return", "class", "struct", "enum", "union", "typedef", "namespace", "using",
                    "public", "private", "protected", "virtual", "override", "static", "const", "constexpr",
                    "auto", "extern", "inline", "volatile", "template", "typename", "new", "delete",
                    "try", "catch", "throw", "true", "false", "nullptr", "sizeof", "include", "define"],
        typeKeywords: ["int", "long", "short", "char", "float", "double", "bool", "void", "size_t",
                       "string", "vector", "map", "set", "pair", "tuple", "array", "unique_ptr",
                       "shared_ptr", "weak_ptr", "optional", "variant"],
        builtins: ["std", "cout", "cin", "endl", "printf", "scanf", "malloc", "free",
                   "memcpy", "strlen", "strcmp", "assert"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"]
    )

    static let rubyRules = LanguageRules(
        keywords: ["def", "end", "class", "module", "if", "elsif", "else", "unless", "while", "until",
                    "for", "do", "begin", "rescue", "ensure", "raise", "return", "yield", "block_given?",
                    "require", "require_relative", "include", "extend", "attr_accessor", "attr_reader",
                    "attr_writer", "self", "super", "true", "false", "nil", "and", "or", "not", "in",
                    "then", "when", "case", "lambda", "proc"],
        typeKeywords: ["String", "Integer", "Float", "Array", "Hash", "Symbol", "Proc", "Lambda",
                       "Object", "Class", "Module", "Struct", "Regexp", "Range", "IO", "File"],
        builtins: ["puts", "print", "p", "pp", "gets", "chomp", "each", "map", "select",
                   "reject", "reduce", "inject", "sort", "flatten", "compact", "freeze"],
        singleLineComment: "#",
        multiLineCommentStart: "=begin",
        multiLineCommentEnd: "=end",
        stringDelimiters: ["\"", "'"]
    )

    static let bashRules = LanguageRules(
        keywords: ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
                    "in", "function", "return", "exit", "local", "export", "source", "eval", "exec",
                    "set", "unset", "readonly", "declare", "typeset", "shift", "break", "continue",
                    "true", "false"],
        typeKeywords: [],
        builtins: ["echo", "printf", "read", "cd", "pwd", "ls", "cp", "mv", "rm", "mkdir", "rmdir",
                   "cat", "grep", "sed", "awk", "find", "sort", "uniq", "wc", "head", "tail",
                   "chmod", "chown", "curl", "wget", "tar", "gzip", "git", "docker", "npm", "yarn"],
        singleLineComment: "#",
        multiLineCommentStart: "",
        multiLineCommentEnd: "",
        stringDelimiters: ["\"", "'"]
    )

    static let sqlRules = LanguageRules(
        keywords: ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
                    "CREATE", "ALTER", "DROP", "TABLE", "INDEX", "VIEW", "JOIN", "INNER", "LEFT",
                    "RIGHT", "OUTER", "ON", "AND", "OR", "NOT", "IN", "BETWEEN", "LIKE", "IS",
                    "NULL", "AS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "UNION",
                    "ALL", "DISTINCT", "EXISTS", "CASE", "WHEN", "THEN", "ELSE", "END", "PRIMARY",
                    "KEY", "FOREIGN", "REFERENCES", "CASCADE", "CONSTRAINT", "DEFAULT", "AUTO_INCREMENT",
                    // 小写版本
                    "select", "from", "where", "insert", "into", "values", "update", "set", "delete",
                    "create", "alter", "drop", "table", "index", "view", "join", "inner", "left",
                    "right", "outer", "on", "and", "or", "not", "in", "between", "like", "is",
                    "null", "as", "order", "by", "group", "having", "limit", "offset", "union",
                    "all", "distinct", "exists", "case", "when", "then", "else", "end"],
        typeKeywords: ["INT", "INTEGER", "VARCHAR", "TEXT", "BOOLEAN", "DATE", "TIMESTAMP", "FLOAT",
                       "DOUBLE", "DECIMAL", "BLOB", "SERIAL", "BIGINT", "SMALLINT",
                       "int", "integer", "varchar", "text", "boolean", "date", "timestamp", "float",
                       "double", "decimal", "blob", "serial", "bigint", "smallint"],
        builtins: ["COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "IFNULL", "CONCAT",
                   "SUBSTRING", "TRIM", "UPPER", "LOWER", "NOW", "CURRENT_TIMESTAMP",
                   "count", "sum", "avg", "min", "max", "coalesce", "ifnull", "concat"],
        singleLineComment: "--",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["'"]
    )

    static let jsonRules = LanguageRules(
        keywords: ["true", "false", "null"],
        typeKeywords: [],
        builtins: [],
        singleLineComment: "",
        multiLineCommentStart: "",
        multiLineCommentEnd: "",
        stringDelimiters: ["\""]
    )

    static let yamlRules = LanguageRules(
        keywords: ["true", "false", "null", "yes", "no", "on", "off"],
        typeKeywords: [],
        builtins: [],
        singleLineComment: "#",
        multiLineCommentStart: "",
        multiLineCommentEnd: "",
        stringDelimiters: ["\"", "'"]
    )

    static let htmlRules = LanguageRules(
        keywords: ["html", "head", "body", "div", "span", "p", "a", "img", "ul", "ol", "li",
                    "table", "tr", "td", "th", "form", "input", "button", "script", "style",
                    "link", "meta", "title", "header", "footer", "nav", "main", "section",
                    "article", "aside", "h1", "h2", "h3", "h4", "h5", "h6", "br", "hr"],
        typeKeywords: ["class", "id", "href", "src", "alt", "type", "name", "value", "placeholder",
                       "action", "method", "target", "rel", "charset", "content", "width", "height"],
        builtins: [],
        singleLineComment: "",
        multiLineCommentStart: "<!--",
        multiLineCommentEnd: "-->",
        stringDelimiters: ["\"", "'"]
    )

    static let cssRules = LanguageRules(
        keywords: ["import", "media", "keyframes", "font-face", "supports", "charset",
                    "important", "from", "to"],
        typeKeywords: ["px", "em", "rem", "vh", "vw", "auto", "none", "block", "inline",
                       "flex", "grid", "absolute", "relative", "fixed", "sticky", "inherit",
                       "initial", "unset", "transparent", "solid", "dashed", "dotted"],
        builtins: ["var", "calc", "rgb", "rgba", "hsl", "hsla", "url", "linear-gradient",
                   "radial-gradient", "translate", "rotate", "scale", "opacity"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"]
    )

    static let kotlinRules = LanguageRules(
        keywords: ["fun", "val", "var", "if", "else", "when", "for", "while", "do", "return",
                    "class", "object", "interface", "abstract", "open", "sealed", "data", "enum",
                    "companion", "import", "package", "override", "private", "public", "protected",
                    "internal", "suspend", "coroutine", "try", "catch", "finally", "throw",
                    "true", "false", "null", "this", "super", "is", "as", "in", "by", "lazy",
                    "lateinit", "inline", "reified", "typealias"],
        typeKeywords: ["Int", "Long", "Short", "Byte", "Float", "Double", "Boolean", "Char",
                       "String", "Unit", "Nothing", "Any", "Array", "List", "Map", "Set",
                       "MutableList", "MutableMap", "MutableSet", "Pair", "Triple"],
        builtins: ["println", "print", "listOf", "mapOf", "setOf", "arrayOf", "mutableListOf",
                   "mutableMapOf", "mutableSetOf", "require", "check", "error", "TODO"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"]
    )
}

// MARK: - 语法高亮代码视图

/// 带语法高亮的代码块视图
struct SyntaxHighlightedCodeView: View {
    let code: String
    let language: String
    var showLineNumbers: Bool = true
    var maxLines: Int = 0  // 0 = 不限制

    // 异步计算的高亮结果，避免在 body 中同步执行耗时操作
    @State private var highlighted: [[SyntaxHighlighter.Token]] = []
    @State private var copied = false

    var body: some View {
        let displayLines = maxLines > 0 ? Array(highlighted.prefix(maxLines)) : highlighted
        let totalLines = highlighted.count

        VStack(alignment: .leading, spacing: 0) {
            // 语言标签 + 复制按钮
            HStack {
                if !language.isEmpty {
                    Text(language)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    Haptics.light()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(copied ? .green : .white.opacity(0.4))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // 代码行
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if highlighted.isEmpty {
                        // 高亮计算中，显示纯文本占位
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    } else {
                        ForEach(Array(displayLines.enumerated()), id: \.offset) { idx, tokens in
                            HStack(spacing: 0) {
                                if showLineNumbers {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.25))
                                        .frame(width: 32, alignment: .trailing)
                                        .padding(.trailing, 8)
                                }

                                SyntaxHighlighter.coloredText(tokens: tokens)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            .padding(.vertical, 1)
                        }

                        // 截断提示
                        if maxLines > 0 && totalLines > maxLines {
                            Text("… 共 \(totalLines) 行，已显示 \(maxLines) 行")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(.top, 4)
                                .padding(.leading, showLineNumbers ? 40 : 0)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // 仅当 code 或 language 变化时重新计算高亮
        .task(id: "\(code.hashValue)|\(language)") {
            // 输入变化时先清空，显示纯文本占位
            highlighted = []
            let codeSnapshot = code
            let langSnapshot = language
            let result = await Task.detached {
                SyntaxHighlighter.highlight(code: codeSnapshot, language: langSnapshot)
            }.value
            highlighted = result
        }
    }
}
