import Foundation

/// Port of `FieldOption`/`IterationOption` from `lib/db/schema.ts` — the two
/// shapes `custom_fields.options` can hold, depending on `type`.
public struct FieldOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var color: String

    public init(id: String, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct IterationOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var startDate: String
    public var durationDays: Int

    public init(id: String, title: String, startDate: String, durationDays: Int) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.durationDays = durationDays
    }
}

/// A custom field's `options` column can hold either shape depending on the
/// sibling `type` column — modeled as an enum rather than `Either` for
/// cleaner pattern-matching at call sites (mirrors the TS union type).
///
/// Deliberately **not** `Codable` on its own: which shape a raw jsonb array
/// decodes to depends on `type`, not on anything in the array itself (an
/// empty `[]` is valid — and ambiguous — for either shape), so decoding
/// always goes through `decode(jsonData:type:)`, called by the `Queries`
/// layer once it already has both columns in hand.
public enum FieldOptions: Sendable, Equatable {
    case fields([FieldOption])
    case iterations([IterationOption])

    public var fieldOptions: [FieldOption] {
        if case .fields(let options) = self { return options }
        return []
    }

    public var iterationOptions: [IterationOption] {
        if case .iterations(let options) = self { return options }
        return []
    }

    public var isEmpty: Bool {
        switch self {
        case .fields(let options): return options.isEmpty
        case .iterations(let options): return options.isEmpty
        }
    }

    /// `type` is the sibling `custom_fields.type` column — `.iteration`
    /// decodes as `[IterationOption]`, everything else (including
    /// non-select types, which always store `[]`) decodes as `[FieldOption]`.
    public static func decode(jsonData: Data, type: CustomFieldType) throws -> FieldOptions {
        let decoder = JSONDecoder()
        switch type {
        case .iteration:
            return .iterations(try decoder.decode([IterationOption].self, from: jsonData))
        default:
            return .fields(try decoder.decode([FieldOption].self, from: jsonData))
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        switch self {
        case .fields(let options): return try encoder.encode(options)
        case .iterations(let options): return try encoder.encode(options)
        }
    }
}

/// Port of the `custom_fields` table — per-space, user-defined fields
/// (Size, Assignees, Sprint, ...). `key` is a slug the AI resolver matches
/// by name across parse requests without depending on its uuid.
public struct CustomField: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let spaceId: UUID
    public var key: String
    public var name: String
    public var type: CustomFieldType
    public var options: FieldOptions
    public var position: Double
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID, spaceId: UUID, key: String, name: String, type: CustomFieldType,
        options: FieldOptions, position: Double, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.spaceId = spaceId
        self.key = key
        self.name = name
        self.type = type
        self.options = options
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, spaceId, key, name, type, options, position, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        spaceId = try container.decode(UUID.self, forKey: .spaceId)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(CustomFieldType.self, forKey: .type)
        position = try container.decode(Double.self, forKey: .position)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let optionsData = try container.decode(Data.self, forKey: .options)
        options = try FieldOptions.decode(jsonData: optionsData, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(spaceId, forKey: .spaceId)
        try container.encode(key, forKey: .key)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(position, forKey: .position)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(options.encoded(), forKey: .options)
    }
}
