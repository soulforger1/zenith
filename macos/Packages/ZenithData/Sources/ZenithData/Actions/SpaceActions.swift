import Foundation

/// Port of `lib/actions/spaces.ts`. `revalidatePath`/`redirect` have no
/// native equivalent — callers (subtask 4's view models) refresh their own
/// state from the returned value on success instead of the RSC
/// refresh-on-navigate model.
public enum SpaceActions {
    private static let maxImageBytes = 4 * 1024 * 1024 // 4MB — stored inline as base64, keep it reasonable

    public struct SpaceInput: Sendable {
        public var name: String
        public var description: String?

        public init(name: String, description: String?) {
            self.name = name
            self.description = description
        }

        func validate() throws -> (name: String, description: String?) {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { throw ValidationError(field: "name", message: "Name is required") }
            guard trimmedName.count <= 100 else { throw ValidationError(field: "name", message: "Name is too long") }

            var trimmedDescription: String?
            if let description {
                let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    guard trimmed.count <= 500 else { throw ValidationError(field: "description", message: "Description is too long") }
                    trimmedDescription = trimmed
                }
            }
            return (trimmedName, trimmedDescription)
        }
    }

    public static func createSpace(_ db: ZenithDatabase, _ input: SpaceInput) async throws -> Space {
        let (name, description) = try input.validate()
        return try await SpaceQueries.createSpace(db, name: name, description: description)
    }

    public static func updateSpace(_ db: ZenithDatabase, id: UUID, _ input: SpaceInput) async throws -> Space? {
        let (name, description) = try input.validate()
        return try await SpaceQueries.updateNameAndDescription(db, id: id, name: name, description: description)
    }

    public static func deleteSpace(_ db: ZenithDatabase, id: UUID) async throws {
        try await SpaceQueries.deleteSpace(db, id: id)
    }

    /// Autosave for the Settings "context" textarea.
    public static func updateContext(_ db: ZenithDatabase, id: UUID, context: String) async throws -> Space? {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await SpaceQueries.updateContext(db, id: id, context: trimmed.isEmpty ? nil : trimmed)
    }

    public static func addSpaceImage(_ db: ZenithDatabase, spaceId: UUID, imageData: Data, mimeType: String, label: String?) async throws -> SpaceImage {
        guard mimeType.hasPrefix("image/") else {
            throw ValidationError(field: "file", message: "Only image files are supported.")
        }
        guard imageData.count <= maxImageBytes else {
            throw ValidationError(field: "file", message: "Image is too large (max 4MB).")
        }
        let dataUrl = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        return try await SpaceImageQueries.addSpaceImage(db, spaceId: spaceId, dataUrl: dataUrl, label: label)
    }

    public static func deleteSpaceImage(_ db: ZenithDatabase, id: UUID) async throws {
        try await SpaceImageQueries.deleteSpaceImage(db, id: id)
    }
}
