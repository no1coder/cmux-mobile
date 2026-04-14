import Foundation

public struct Surface: Identifiable, Codable, Equatable {
    public let id: String
    public let ref: String
    public let index: Int
    public let type: SurfaceType
    public let title: String
    public let focused: Bool
    public let paneID: String?
    public let paneRef: String?
    /// 终端当前工作目录（不受进程标题覆盖影响）
    public let cwd: String?
    /// 所属 workspace ID
    public let workspaceID: String?
    /// 所属 workspace 名称
    public let workspaceName: String?

    public enum SurfaceType: String, Codable {
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

    public init(
        id: String,
        ref: String,
        index: Int,
        type: SurfaceType,
        title: String,
        focused: Bool,
        paneID: String? = nil,
        paneRef: String? = nil,
        cwd: String? = nil,
        workspaceID: String? = nil,
        workspaceName: String? = nil
    ) {
        self.id = id
        self.ref = ref
        self.index = index
        self.type = type
        self.title = title
        self.focused = focused
        self.paneID = paneID
        self.paneRef = paneRef
        self.cwd = cwd
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
    }
}
