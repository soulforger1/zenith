import Foundation

/// Port of the `views` table — saved, named Table/Board/Roadmap views per
/// space (GitHub Projects style), each remembering its own visible
/// fields/filters/sort/group-by in `config`. Exactly one view per space
/// should have `isDefault: true` — enforced in `ViewActions`, not a DB
/// constraint.
public struct ZView: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let spaceId: UUID
    public var name: String
    public var type: ViewType
    public var position: Double
    public var isDefault: Bool
    public var config: ViewConfig
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID, spaceId: UUID, name: String, type: ViewType, position: Double,
        isDefault: Bool, config: ViewConfig, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.spaceId = spaceId
        self.name = name
        self.type = type
        self.position = position
        self.isDefault = isDefault
        self.config = config
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, spaceId, name, type, position, isDefault, config, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        spaceId = try container.decode(UUID.self, forKey: .spaceId)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(ViewType.self, forKey: .type)
        position = try container.decode(Double.self, forKey: .position)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let configData = try container.decode(Data.self, forKey: .config)
        config = try ViewConfig.decode(jsonData: configData, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(spaceId, forKey: .spaceId)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(position, forKey: .position)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(config.encoded(), forKey: .config)
    }
}
