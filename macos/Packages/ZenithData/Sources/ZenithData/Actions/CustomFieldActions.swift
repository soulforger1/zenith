import Foundation

/// Port of `lib/actions/custom-fields.ts`.
public enum CustomFieldActions {
    private static func validateOption(_ option: FieldOption) throws {
        let trimmedName = option.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 60 else {
            throw ValidationError(field: "options", message: "Option name must be 1-60 characters.")
        }
        guard !option.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, option.color.count <= 20 else {
            throw ValidationError(field: "options", message: "Invalid option color.")
        }
    }

    private static func validateIteration(_ option: IterationOption) throws {
        let trimmedTitle = option.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, trimmedTitle.count <= 60 else {
            throw ValidationError(field: "options", message: "Iteration title must be 1-60 characters.")
        }
        guard (1...365).contains(option.durationDays) else {
            throw ValidationError(field: "options", message: "Duration must be 1-365 days.")
        }
    }

    private static func validateName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError(field: "name", message: "Name is required") }
        guard trimmed.count <= 60 else { throw ValidationError(field: "name", message: "Name is too long") }
        return trimmed
    }

    private static func validateOptions(_ options: FieldOptions) throws {
        switch options {
        case .fields(let opts): for opt in opts { try validateOption(opt) }
        case .iterations(let opts): for opt in opts { try validateIteration(opt) }
        }
    }

    public static func createCustomField(
        _ db: ZenithDatabase, spaceId: UUID, name: String, type: CustomFieldType, options: FieldOptions
    ) async throws -> CustomField {
        let trimmedName = try validateName(name)
        try validateOptions(options)
        let key = Slug.slugify(trimmedName).isEmpty ? "field" : Slug.slugify(trimmedName)
        return try await CustomFieldQueries.createCustomField(db, spaceId: spaceId, key: key, name: trimmedName, type: type, options: options)
    }

    public static func updateCustomField(
        _ db: ZenithDatabase, id: UUID, name: String?, options: FieldOptions?
    ) async throws -> CustomField? {
        let validatedName = try name.map { try validateName($0) }
        if let options { try validateOptions(options) }
        return try await CustomFieldQueries.updateCustomField(db, id: id, name: validatedName, options: options, position: nil)
    }

    /// TS runs these concurrently (`Promise.all`); sequential here is
    /// equivalent for correctness (independent rows) and simpler — not
    /// worth the concurrency complexity at personal-app scale.
    public static func reorderCustomFields(_ db: ZenithDatabase, updates: [(id: UUID, position: Double)]) async throws {
        for update in updates {
            _ = try await CustomFieldQueries.updateCustomField(db, id: update.id, name: nil, options: nil, position: update.position)
        }
    }

    public static func deleteCustomField(_ db: ZenithDatabase, id: UUID) async throws {
        try await CustomFieldQueries.deleteCustomField(db, id: id)
    }
}
