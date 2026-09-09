import Foundation
import ZenithData

/// Port of `lib/ai/schemas.ts` — shapes returned by the AI parse flows,
/// validated after decoding since the CLI's structured output isn't a 100%
/// guarantee (same reasoning as the TS side re-validating with zod even
/// though the request already asked for JSON-schema-constrained output).

public struct AttachedImage: Codable, Sendable, Equatable {
    public var mimeType: String
    /// Raw base64, no `data:...;base64,` prefix.
    public var data: String

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}

/// A detected value for one of the space's existing custom fields, keyed by
/// the field's `key` (not id) — `AIOrchestration` resolves key -> id.
public struct AIFieldValue: Codable, Sendable, Equatable {
    public var fieldKey: String
    public var value: String
}

/// A field the AI thinks should exist but doesn't yet.
public struct AINewField: Codable, Sendable, Equatable {
    public var key: String
    public var name: String
    public var type: CustomFieldType
    public var options: [String]?
}

public struct ParsedTask: Codable, Sendable, Equatable {
    public var title: String
    public var description: String?
    public var priority: IssuePriority
    public var tags: [String]
    public var branch: String?
    public var estimate: String?
    /// ISO date (YYYY-MM-DD), if Claude could resolve one.
    public var dueDate: String?
    /// Repo names (not ids) — resolved to repoIds by `AIOrchestration`.
    public var repos: [String]?
    /// Milestone title (not id) — resolved to milestoneId by `AIOrchestration`.
    public var milestone: String?
    public var fieldValues: [AIFieldValue]?
    public var newFields: [AINewField]?

    enum CodingKeys: String, CodingKey {
        case title, description, priority, tags, branch, estimate, dueDate, repos, milestone, fieldValues, newFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        priority = try container.decode(IssuePriority.self, forKey: .priority)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        estimate = try container.decodeIfPresent(String.self, forKey: .estimate)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        repos = try container.decodeIfPresent([String].self, forKey: .repos)
        milestone = try container.decodeIfPresent(String.self, forKey: .milestone)
        fieldValues = try container.decodeIfPresent([AIFieldValue].self, forKey: .fieldValues)
        newFields = try container.decodeIfPresent([AINewField].self, forKey: .newFields)
    }

    public init(
        title: String, description: String? = nil, priority: IssuePriority, tags: [String] = [],
        branch: String? = nil, estimate: String? = nil, dueDate: String? = nil, repos: [String]? = nil,
        milestone: String? = nil, fieldValues: [AIFieldValue]? = nil, newFields: [AINewField]? = nil
    ) {
        self.title = title
        self.description = description
        self.priority = priority
        self.tags = tags
        self.branch = branch
        self.estimate = estimate
        self.dueDate = dueDate
        self.repos = repos
        self.milestone = milestone
        self.fieldValues = fieldValues
        self.newFields = newFields
    }

    /// Re-validates the decoded shape against the same bounds
    /// `parsedTaskSchema` enforces — a schema-constrained CLI response can
    /// still violate these (e.g. an over-long title), so this is a real
    /// check, not a formality.
    public func validate() throws -> ParsedTask {
        guard (1...200).contains(title.count) else {
            throw AISchemaError.invalid("title must be 1-200 characters")
        }
        if let description, description.count > 2000 {
            throw AISchemaError.invalid("description must be at most 2000 characters")
        }
        guard tags.count <= 8, tags.allSatisfy({ (1...30).contains($0.count) }) else {
            throw AISchemaError.invalid("tags must be at most 8 items of 1-30 characters each")
        }
        if let branch, branch.count > 100 { throw AISchemaError.invalid("branch too long") }
        if let estimate, estimate.count > 20 { throw AISchemaError.invalid("estimate too long") }
        if let repos, repos.count > 5 { throw AISchemaError.invalid("at most 5 repos") }
        if let milestone, milestone.count > 150 { throw AISchemaError.invalid("milestone title too long") }
        if let fieldValues, fieldValues.count > 10 { throw AISchemaError.invalid("at most 10 field values") }
        if let newFields, newFields.count > 3 { throw AISchemaError.invalid("at most 3 new fields") }
        return self
    }
}

public enum AISchemaError: Error, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): return "Claude's response didn't match the expected format: \(message)."
        }
    }
}

public enum ParsedTasksValidator {
    public static func validate(_ tasks: [ParsedTask]) throws -> [ParsedTask] {
        guard (1...50).contains(tasks.count) else {
            throw AISchemaError.invalid("expected 1-50 tasks")
        }
        return try tasks.map { try $0.validate() }
    }
}

public enum GeneratedSubtasksValidator {
    public static func validate(_ subtasks: [String]) throws -> [String] {
        guard (1...10).contains(subtasks.count), subtasks.allSatisfy({ (1...200).contains($0.count) }) else {
            throw AISchemaError.invalid("expected 1-10 subtasks of 1-200 characters each")
        }
        return subtasks
    }
}
