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
    /// 终端当前工作目录（不受进程标题覆盖影响）
    let cwd: String?
    /// 所属 workspace ID
    let workspaceID: String?
    /// 所属 workspace 名称
    let workspaceName: String?

    enum SurfaceType: String, Codable {
        case terminal
        case browser
    }

    enum CodingKeys: String, CodingKey {
        case id, ref, index, type, title, focused, cwd
        case paneID = "pane_id"
        case paneRef = "pane_ref"
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
    }
}
