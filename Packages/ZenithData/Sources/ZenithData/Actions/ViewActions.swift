import Foundation

/// Port of `lib/actions/views.ts`.
public enum ViewActions {
    /// Creates a view with a sensible default config for its type — used by
    /// the "+" new-view control in the tab bar.
    public static func createView(_ db: ZenithDatabase, spaceId: UUID, name: String, type: ViewType) async throws -> ZView {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError(field: "name", message: "Name is required") }
        guard trimmed.count <= 60 else { throw ValidationError(field: "name", message: "Name is too long") }
        return try await ViewQueries.createView(db, spaceId: spaceId, name: trimmed, type: type, config: .defaultConfig(for: type))
    }

    public static func renameView(_ db: ZenithDatabase, id: UUID, name: String) async throws -> ZView? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError(field: "name", message: "Name is required") }
        return try await ViewQueries.renameView(db, id: id, name: trimmed)
    }

    /// Autosave from the filter bar / view-settings popover.
    public static func updateConfig(_ db: ZenithDatabase, id: UUID, config: ViewConfig) async throws -> ZView? {
        try await ViewQueries.updateConfig(db, id: id, config: config)
    }

    /// "Duplicate" from a view tab's "..." menu — copies name/type/config as
    /// a new, non-default view.
    public static func duplicateView(_ db: ZenithDatabase, id: UUID) async throws -> ZView {
        guard let source = try await ViewQueries.getViewById(db, id: id) else {
            throw ValidationError(field: "view", message: "View not found.")
        }
        return try await ViewQueries.createView(db, spaceId: source.spaceId, name: "\(source.name) copy", type: source.type, config: source.config)
    }

    public static func setDefaultView(_ db: ZenithDatabase, id: UUID) async throws -> ZView? {
        try await ViewQueries.setDefault(db, id: id)
    }

    public static func deleteView(_ db: ZenithDatabase, id: UUID) async throws -> ValidationError? {
        try await ViewQueries.deleteView(db, id: id)
    }
}
