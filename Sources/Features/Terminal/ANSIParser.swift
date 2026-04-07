import Foundation
import SwiftUI

/// ANSI 转义码解析器，支持 SGR 属性（颜色、样式）
enum ANSIParser {

    // MARK: - 公共 API

    /// 解析包含 ANSI 转义码的字符串，返回带属性的 AttributedString
    static func parse(_ input: String) -> AttributedString {
        var result = AttributedString()
        var currentStyle = ANSIStyle()
        var index = input.startIndex

        while index < input.endIndex {
            let char = input[index]

            if char == "\u{1B}" {
                // ESC 字符，检测转义序列类型
                guard let nextIndex = input.index(index, offsetBy: 1, limitedBy: input.endIndex),
                      nextIndex < input.endIndex else {
                    index = input.endIndex
                    break
                }

                let nextChar = input[nextIndex]

                if nextChar == "[" {
                    // CSI 序列：ESC[ ... 终止符（0x40-0x7E）
                    let paramStart = input.index(nextIndex, offsetBy: 1, limitedBy: input.endIndex) ?? input.endIndex
                    var scanIndex = paramStart

                    // 跳过参数字节（0x30-0x3F）和中间字节（0x20-0x2F）
                    while scanIndex < input.endIndex {
                        let c = input[scanIndex]
                        if c.asciiValue.map({ $0 >= 0x40 && $0 <= 0x7E }) == true {
                            break
                        }
                        scanIndex = input.index(after: scanIndex)
                    }

                    if scanIndex < input.endIndex {
                        let command = input[scanIndex]
                        // 只处理 SGR 命令 'm'，其他 CSI 命令静默跳过
                        if command == "m" {
                            let paramStr = String(input[paramStart..<scanIndex])
                            currentStyle = applySGR(params: paramStr, to: currentStyle)
                        }
                        index = input.index(after: scanIndex)
                    } else {
                        index = scanIndex
                    }
                } else if nextChar == "]" {
                    // OSC 序列：ESC] ... ST（ESC\ 或 BEL \u{07}）
                    var scanIndex = input.index(nextIndex, offsetBy: 1, limitedBy: input.endIndex) ?? input.endIndex
                    while scanIndex < input.endIndex {
                        let c = input[scanIndex]
                        if c == "\u{07}" {
                            // BEL 终止
                            scanIndex = input.index(after: scanIndex)
                            break
                        }
                        if c == "\u{1B}" {
                            let afterEsc = input.index(scanIndex, offsetBy: 1, limitedBy: input.endIndex) ?? input.endIndex
                            if afterEsc < input.endIndex && input[afterEsc] == "\\" {
                                // ST 终止（ESC\）
                                scanIndex = input.index(after: afterEsc)
                                break
                            }
                        }
                        scanIndex = input.index(after: scanIndex)
                    }
                    index = scanIndex
                } else if nextChar == "(" || nextChar == ")" {
                    // 字符集选择序列：ESC( 或 ESC)，后跟一个字符
                    let skip = input.index(nextIndex, offsetBy: 2, limitedBy: input.endIndex) ?? input.endIndex
                    index = skip
                } else {
                    // 其他两字符 ESC 序列（如 ESC=, ESC>），跳过
                    index = input.index(nextIndex, offsetBy: 1, limitedBy: input.endIndex) ?? input.endIndex
                }
            } else if char == "\u{9C}" || char == "\u{90}" || char == "\u{9D}" || char == "\u{9E}" || char == "\u{9F}" {
                // C1 控制字符（8-bit），跳过到终止符
                index = input.index(after: index)
                while index < input.endIndex {
                    let c = input[index]
                    if c == "\u{9C}" || c == "\u{07}" || c == "\u{1B}" { break }
                    index = input.index(after: index)
                }
                if index < input.endIndex { index = input.index(after: index) }
            } else if char.asciiValue.map({ $0 < 0x20 && $0 != 0x0A && $0 != 0x0D && $0 != 0x09 }) == true {
                // 跳过其他控制字符（保留换行、回车、制表符）
                index = input.index(after: index)
            } else {
                // 普通字符
                var segment = AttributedString(String(char))
                applyStyle(currentStyle, to: &segment)
                result.append(segment)
                index = input.index(after: index)
            }
        }

        return result
    }

    // MARK: - 私有实现

    /// 解析并应用 SGR 参数到样式
    private static func applySGR(params: String, to style: ANSIStyle) -> ANSIStyle {
        let parts = params.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }

        // 空参数等同于重置
        if parts.isEmpty || (parts.count == 1 && parts[0] == 0) {
            return ANSIStyle()
        }

        var newStyle = style
        var i = 0

        while i < parts.count {
            let code = parts[i]

            switch code {
            case 0:
                // 重置所有属性
                newStyle = ANSIStyle()

            case 1:
                // 粗体
                newStyle = ANSIStyle(
                    bold: true,
                    italic: newStyle.italic,
                    underline: newStyle.underline,
                    foreground: newStyle.foreground,
                    background: newStyle.background
                )

            case 3:
                // 斜体
                newStyle = ANSIStyle(
                    bold: newStyle.bold,
                    italic: true,
                    underline: newStyle.underline,
                    foreground: newStyle.foreground,
                    background: newStyle.background
                )

            case 4:
                // 下划线
                newStyle = ANSIStyle(
                    bold: newStyle.bold,
                    italic: newStyle.italic,
                    underline: true,
                    foreground: newStyle.foreground,
                    background: newStyle.background
                )

            case 30...37:
                // 标准前景色（0-7）
                newStyle = ANSIStyle(
                    bold: newStyle.bold,
                    italic: newStyle.italic,
                    underline: newStyle.underline,
                    foreground: standardColor(code - 30),
                    background: newStyle.background
                )

            case 38:
                // 扩展前景色
                if i + 1 < parts.count {
                    let mode = parts[i + 1]
                    if mode == 5, i + 2 < parts.count {
                        // 256 色模式: 38;5;N
                        let colorIndex = parts[i + 2]
                        newStyle = ANSIStyle(
                            bold: newStyle.bold,
                            italic: newStyle.italic,
                            underline: newStyle.underline,
                            foreground: color256(colorIndex),
                            background: newStyle.background
                        )
                        i += 2
                    } else if mode == 2, i + 4 < parts.count {
                        // 真彩色模式: 38;2;R;G;B
                        let r = parts[i + 2]
                        let g = parts[i + 3]
                        let b = parts[i + 4]
                        newStyle = ANSIStyle(
                            bold: newStyle.bold,
                            italic: newStyle.italic,
                            underline: newStyle.underline,
                            foreground: Color(
                                red: Double(r) / 255.0,
                                green: Double(g) / 255.0,
                                blue: Double(b) / 255.0
                            ),
                            background: newStyle.background
                        )
                        i += 4
                    }
                }

            case 39:
                // 默认前景色
                newStyle = ANSIStyle(
                    bold: newStyle.bold,
                    italic: newStyle.italic,
                    underline: newStyle.underline,
                    foreground: nil,
                    background: newStyle.background
                )

            case 40...47:
                // 标准背景色（0-7）
                newStyle = ANSIStyle(
                    bold: newStyle.bold,
                    italic: newStyle.italic,
                    underline: newStyle.underline,
                    foreground: newStyle.foreground,
                    background: standardColor(code - 40)
                )

            case 48:
                // 扩展背景色
                if i + 1 < parts.count {
                    let mode = parts[i + 1]
                    if mode == 5, i + 2 < parts.count {
                        // 256 色模式: 48;5;N
                        let colorIndex = parts[i + 2]
                        newStyle = ANSIStyle(
                            bold: newStyle.bold,
                            italic: newStyle.italic,
                            underline: newStyle.underline,
                            foreground: newStyle.foreground,
                            background: color256(colorIndex)
                        )
                        i += 2
                    }
                }

            case 49:
                // 默认背景色
                newStyle = ANSIStyle(
                    bold: newStyle.bold,
                    italic: newStyle.italic,
                    underline: newStyle.underline,
                    foreground: newStyle.foreground,
                    background: nil
                )

            case 90...97:
                // 亮色前景色（0-7）
                newStyle = ANSIStyle(
                    bold: newStyle.bold,
                    italic: newStyle.italic,
                    underline: newStyle.underline,
                    foreground: brightColor(code - 90),
                    background: newStyle.background
                )

            case 100...107:
                // 亮色背景色（0-7）
                newStyle = ANSIStyle(
                    bold: newStyle.bold,
                    italic: newStyle.italic,
                    underline: newStyle.underline,
                    foreground: newStyle.foreground,
                    background: brightColor(code - 100)
                )

            default:
                break
            }

            i += 1
        }

        return newStyle
    }

    /// 将样式应用到 AttributedString 片段
    private static func applyStyle(_ style: ANSIStyle, to segment: inout AttributedString) {
        var container = AttributeContainer()

        if style.bold {
            container.font = .custom("MesloLGSNerdFontMono-Bold", size: 11)
        }

        if let fg = style.foreground {
            container.foregroundColor = fg
        }

        if let bg = style.background {
            container.backgroundColor = bg
        }

        // 注意：SwiftUI AttributedString 的下划线支持需要 Foundation 属性
        if style.underline {
            container.underlineStyle = .single
        }

        segment.mergeAttributes(container)
    }

    // MARK: - 颜色查找表

    /// 标准 8 色（ANSI 30-37 / 40-47）
    private static func standardColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color(red: 0, green: 0, blue: 0)         // 黑
        case 1: return Color(red: 0.8, green: 0, blue: 0)       // 红
        case 2: return Color(red: 0, green: 0.8, blue: 0)       // 绿
        case 3: return Color(red: 0.8, green: 0.8, blue: 0)     // 黄
        case 4: return Color(red: 0, green: 0, blue: 0.8)       // 蓝
        case 5: return Color(red: 0.8, green: 0, blue: 0.8)     // 洋红
        case 6: return Color(red: 0, green: 0.8, blue: 0.8)     // 青
        case 7: return Color(red: 0.8, green: 0.8, blue: 0.8)   // 白
        default: return Color.primary
        }
    }

    /// 亮色 8 色（ANSI 90-97 / 100-107）
    private static func brightColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color(red: 0.5, green: 0.5, blue: 0.5)   // 亮黑（灰）
        case 1: return Color(red: 1, green: 0, blue: 0)         // 亮红
        case 2: return Color(red: 0, green: 1, blue: 0)         // 亮绿
        case 3: return Color(red: 1, green: 1, blue: 0)         // 亮黄
        case 4: return Color(red: 0, green: 0, blue: 1)         // 亮蓝
        case 5: return Color(red: 1, green: 0, blue: 1)         // 亮洋红
        case 6: return Color(red: 0, green: 1, blue: 1)         // 亮青
        case 7: return Color(red: 1, green: 1, blue: 1)         // 亮白
        default: return Color.primary
        }
    }

    /// 256 色调色板
    private static func color256(_ index: Int) -> Color {
        let i = max(0, min(255, index))

        // 前 16 色：标准色 + 亮色
        if i < 8 {
            return standardColor(i)
        } else if i < 16 {
            return brightColor(i - 8)
        }

        // 16-231：6x6x6 颜色立方体
        if i < 232 {
            let cube = i - 16
            let b = cube % 6
            let g = (cube / 6) % 6
            let r = cube / 36
            return Color(
                red: r == 0 ? 0 : (Double(r) * 40 + 55) / 255.0,
                green: g == 0 ? 0 : (Double(g) * 40 + 55) / 255.0,
                blue: b == 0 ? 0 : (Double(b) * 40 + 55) / 255.0
            )
        }

        // 232-255：24 阶灰度
        let gray = Double(i - 232) * 10 + 8
        return Color(red: gray / 255.0, green: gray / 255.0, blue: gray / 255.0)
    }
}

// MARK: - 内部数据结构

/// 当前文字渲染样式（不可变）
private struct ANSIStyle {
    let bold: Bool
    let italic: Bool
    let underline: Bool
    let foreground: Color?
    let background: Color?

    init(
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        foreground: Color? = nil,
        background: Color? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.foreground = foreground
        self.background = background
    }
}
