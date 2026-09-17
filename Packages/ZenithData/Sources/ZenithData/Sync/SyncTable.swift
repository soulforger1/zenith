/// Every table the sync layer reconciles, in FK-safe write order (a child
/// never appears before its parent). Matches `Database/Schema/Migrations.swift`
/// and `db/schema.ts` exactly — adding a synced table means adding it here
/// too, in the right position.
public enum SyncTable: String, CaseIterable, Sendable {
    case spaces
    case spaceImages = "space_images"
    case milestones
    case repos
    case customFields = "custom_fields"
    case views
    case issues
    case issueRepos = "issue_repos"

    /// FK-safe order for inserts/updates (parents before children).
    public static let dependencyOrder: [SyncTable] = [
        .spaces, .spaceImages, .milestones, .repos, .customFields, .views, .issues, .issueRepos,
    ]

    /// Position in `dependencyOrder` — deletes must run in the reverse of
    /// this order (children before parents) so a cascade-eligible delete
    /// never trips a still-referencing row.
    public var dependencyIndex: Int {
        Self.dependencyOrder.firstIndex(of: self) ?? Self.dependencyOrder.count
    }
}
