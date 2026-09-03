import Foundation

/// Port of the `space_images` table. Reference images stored inline as
/// base64 data URLs — sent as multimodal AI context alongside a space's
/// text context on every paste-task parse.
public struct SpaceImage: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let spaceId: UUID
    public var dataUrl: String
    public var label: String?
    public let createdAt: Date

    public init(id: UUID, spaceId: UUID, dataUrl: String, label: String?, createdAt: Date) {
        self.id = id
        self.spaceId = spaceId
        self.dataUrl = dataUrl
        self.label = label
        self.createdAt = createdAt
    }
}
