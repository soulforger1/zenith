import Foundation

/// Port of `lib/views/types.ts` — shapes stored in `views.config`, a jsonb
/// blob whose structure depends on `views.type`.

public enum FilterOperator: String, Codable, Sendable, Equatable {
    case isEqual = "is"
    case isNot = "is_not"
    case contains
    case isEmpty = "is_empty"
    case isNotEmpty = "is_not_empty"
    case before
    case after
}

/// `value` is untyped in the original (`unknown`) since it depends on the
/// referenced field's type — kept as raw JSON here, decoded/encoded lazily
/// by whichever filter-evaluation code (subtask 4) knows the field's type.
public struct FilterRule: Codable, Sendable, Equatable {
    public var fieldId: String
    public var operatorType: FilterOperator
    public var valueJSON: Data?

    enum CodingKeys: String, CodingKey {
        case fieldId
        case operatorType = "operator"
        case value
    }

    public init(fieldId: String, operatorType: FilterOperator, valueJSON: Data?) {
        self.fieldId = fieldId
        self.operatorType = operatorType
        self.valueJSON = valueJSON
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fieldId = try container.decode(String.self, forKey: .fieldId)
        operatorType = try container.decode(FilterOperator.self, forKey: .operatorType)
        if let anyValue = try? container.decode(AnyCodableValue.self, forKey: .value) {
            valueJSON = try JSONEncoder().encode(anyValue)
        } else {
            valueJSON = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fieldId, forKey: .fieldId)
        try container.encode(operatorType, forKey: .operatorType)
        if let valueJSON, let decoded = try? JSONDecoder().decode(AnyCodableValue.self, from: valueJSON) {
            try container.encode(decoded, forKey: .value)
        }
    }
}

public struct SortRule: Codable, Sendable, Equatable {
    public enum Direction: String, Codable, Sendable { case asc, desc }

    public var fieldId: String
    public var direction: Direction

    public init(fieldId: String, direction: Direction) {
        self.fieldId = fieldId
        self.direction = direction
    }
}

public struct TableViewConfig: Codable, Sendable, Equatable {
    public var visibleFieldIds: [String]
    public var sort: [SortRule]
    public var groupByFieldId: String?
    public var filters: [FilterRule]

    public init(visibleFieldIds: [String], sort: [SortRule], groupByFieldId: String?, filters: [FilterRule]) {
        self.visibleFieldIds = visibleFieldIds
        self.sort = sort
        self.groupByFieldId = groupByFieldId
        self.filters = filters
    }
}

public struct BoardViewConfig: Codable, Sendable, Equatable {
    public var groupByFieldId: String
    public var visibleFieldIds: [String]
    public var filters: [FilterRule]

    public init(groupByFieldId: String, visibleFieldIds: [String], filters: [FilterRule]) {
        self.groupByFieldId = groupByFieldId
        self.visibleFieldIds = visibleFieldIds
        self.filters = filters
    }
}

public struct RoadmapViewConfig: Codable, Sendable, Equatable {
    public enum Zoom: String, Codable, Sendable { case week, month, quarter }

    public var startFieldId: String?
    public var endFieldId: String?
    public var groupByFieldId: String?
    public var filters: [FilterRule]
    public var zoom: Zoom

    public init(startFieldId: String?, endFieldId: String?, groupByFieldId: String?, filters: [FilterRule], zoom: Zoom) {
        self.startFieldId = startFieldId
        self.endFieldId = endFieldId
        self.groupByFieldId = groupByFieldId
        self.filters = filters
        self.zoom = zoom
    }
}

/// Which shape `views.config` decodes to depends on the sibling `views.type`
/// column — same pattern as `FieldOptions`, decoded explicitly rather than
/// auto-detected from shape.
public enum ViewConfig: Sendable, Equatable {
    case table(TableViewConfig)
    case board(BoardViewConfig)
    case roadmap(RoadmapViewConfig)

    public static func decode(jsonData: Data, type: ViewType) throws -> ViewConfig {
        let decoder = JSONDecoder()
        switch type {
        case .table: return .table(try decoder.decode(TableViewConfig.self, from: jsonData))
        case .board: return .board(try decoder.decode(BoardViewConfig.self, from: jsonData))
        case .roadmap: return .roadmap(try decoder.decode(RoadmapViewConfig.self, from: jsonData))
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        switch self {
        case .table(let config): return try encoder.encode(config)
        case .board(let config): return try encoder.encode(config)
        case .roadmap(let config): return try encoder.encode(config)
        }
    }

    public static func defaultConfig(for type: ViewType) -> ViewConfig {
        switch type {
        case .table:
            return .table(TableViewConfig(visibleFieldIds: ["status", "priority"], sort: [], groupByFieldId: nil, filters: []))
        case .board:
            return .board(BoardViewConfig(groupByFieldId: "status", visibleFieldIds: ["dueDate", "branch", "estimate"], filters: []))
        case .roadmap:
            return .roadmap(RoadmapViewConfig(startFieldId: nil, endFieldId: nil, groupByFieldId: nil, filters: [], zoom: .month))
        }
    }
}

/// Minimal `Codable` "any JSON value" box — just enough to round-trip a
/// `FilterRule.value` (string/number/bool/array/object/null) without a
/// third-party dependency.
public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
