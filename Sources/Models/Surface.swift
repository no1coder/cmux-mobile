import Foundation

struct Surface: Identifiable, Codable, Equatable {
    let id: String
    let ref: String
    let index: Int
    let type: SurfaceType
    let title: String
    let focused: Bool
    let paneID: String?
    let paneRef: String?

    enum SurfaceType: String, Codable {
        case terminal
        case browser
    }

    enum CodingKeys: String, CodingKey {
        case id, ref, index, type, title, focused
        case paneID = "pane_id"
        case paneRef = "pane_ref"
    }
}
