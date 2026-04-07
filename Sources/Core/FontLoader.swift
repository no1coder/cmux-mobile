import CoreGraphics
import CoreText
import Foundation

/// 运行时字体加载工具
/// 如果 Info.plist 的 UIAppFonts 路径不匹配，通过代码注册字体
enum FontLoader {

    /// 注册 bundle 中的 Nerd Font（在 App 启动时调用）
    static func registerFonts() {
        registerFont(named: "MesloLGSNerdFontMono-Regular", extension: "ttf")
        registerFont(named: "MesloLGSNerdFontMono-Bold", extension: "ttf")
    }

    private static func registerFont(named name: String, extension ext: String) {
        // 在多个可能的位置搜索字体文件
        let searchPaths = [
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources"),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fonts"),
        ]

        guard let url = searchPaths.compactMap({ $0 }).first else {
            print("[FontLoader] 字体文件未找到: \(name).\(ext)")
            return
        }

        guard let fontDataProvider = CGDataProvider(url: url as CFURL),
              let font = CGFont(fontDataProvider) else {
            print("[FontLoader] 字体加载失败: \(name)")
            return
        }

        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterGraphicsFont(font, &error) {
            // 已注册过不是错误
            let desc = error?.takeRetainedValue().localizedDescription ?? ""
            if !desc.contains("already registered") {
                print("[FontLoader] 字体注册失败: \(name) - \(desc)")
            }
        } else {
            print("[FontLoader] 字体注册成功: \(name)")
        }
    }
}
