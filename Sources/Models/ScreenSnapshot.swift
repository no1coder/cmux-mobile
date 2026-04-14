import Foundation

struct ScreenSnapshot: Equatable {
    let surfaceID: String
    let lines: [String]
    let dimensions: Dimensions
    let timestamp: Date

    /// 单个 snapshot 内保留的最大行数，防止异常数据导致内存膨胀
    static let maxLines = 500

    struct Dimensions: Codable, Equatable {
        let rows: Int
        let cols: Int
    }

    init(surfaceID: String, lines: [String], dimensions: Dimensions, timestamp: Date) {
        self.surfaceID = surfaceID
        // 硬性上限：超过 maxLines 时只保留末尾（对终端而言最新即最下方）
        if lines.count > Self.maxLines {
            self.lines = Array(lines.suffix(Self.maxLines))
        } else {
            self.lines = lines
        }
        self.dimensions = dimensions
        self.timestamp = timestamp
    }
}
