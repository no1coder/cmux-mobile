import SwiftUI

#if os(iOS)
@main
struct cmuxMobileApp: App {
    var body: some Scene {
        WindowGroup {
            Text("cmux mobile")
        }
    }
}
#else
/// macOS 构建占位入口（仅供 Swift PM 满足链接需求）
@main
enum cmuxMobileApp {
    static func main() {}
}
#endif
