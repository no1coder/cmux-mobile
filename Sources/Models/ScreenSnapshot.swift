import Foundation

struct ScreenSnapshot: Equatable {
    let surfaceID: String
    let lines: [String]
    let dimensions: Dimensions
    let timestamp: Date

    struct Dimensions: Codable, Equatable {
        let rows: Int
        let cols: Int
    }
}
