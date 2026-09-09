import Foundation

/// Port of `lib/actions/milestones.ts`.
public enum MilestoneActions {
    public struct MilestoneInput: Sendable {
        public var title: String
        public var description: String?
        public var dueDate: String?

        public init(title: String, description: String?, dueDate: String?) {
            self.title = title
            self.description = description
            self.dueDate = dueDate
        }

        func validate() throws -> (title: String, description: String?, dueDate: String?) {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { throw ValidationError(field: "title", message: "Title is required") }
            guard trimmedTitle.count <= 150 else { throw ValidationError(field: "title", message: "Title is too long") }

            var trimmedDescription: String?
            if let description {
                let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    guard trimmed.count <= 2000 else { throw ValidationError(field: "description", message: "Description is too long") }
                    trimmedDescription = trimmed
                }
            }
            return (trimmedTitle, trimmedDescription, dueDate)
        }
    }

    public static func createMilestone(_ db: ZenithDatabase, spaceId: UUID, _ input: MilestoneInput) async throws -> Milestone {
        let (title, description, dueDate) = try input.validate()
        return try await MilestoneQueries.createMilestone(db, spaceId: spaceId, title: title, description: description, dueDate: dueDate)
    }

    public static func updateMilestone(_ db: ZenithDatabase, id: UUID, _ input: MilestoneInput) async throws -> Milestone? {
        let (title, description, dueDate) = try input.validate()
        return try await MilestoneQueries.updateMilestone(db, id: id, title: title, description: description, dueDate: dueDate)
    }

    public static func toggleClosed(_ db: ZenithDatabase, id: UUID, isClosed: Bool) async throws -> Milestone? {
        try await MilestoneQueries.setClosed(db, id: id, isClosed: isClosed)
    }

    public static func deleteMilestone(_ db: ZenithDatabase, id: UUID) async throws {
        try await MilestoneQueries.deleteMilestone(db, id: id)
    }
}
