import Foundation
import PostgresNIO
import ZenithData

/// Row → model mapping for Postgres data, used by `PostgresImporter`
/// (Phase 1) and the Postgres sync target (Phase 2+). Ported from the
/// former `ZenithData` `*Queries` files' private `map(_ row:)` functions,
/// which decoded straight off `PostgresRow` before the local store moved to
/// SQLite/GRDB.
enum PostgresRowMapping {
    static func space(_ row: PostgresRow) throws -> Space {
        let r = row.makeRandomAccess()
        return Space(
            id: try r["id"].decode(UUID.self),
            name: try r["name"].decode(String.self),
            slug: try r["slug"].decode(String.self),
            description: try r["description"].decode(String?.self),
            context: try r["context"].decode(String?.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    static func spaceImage(_ row: PostgresRow) throws -> SpaceImage {
        let r = row.makeRandomAccess()
        return SpaceImage(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            dataUrl: try r["data_url"].decode(String.self),
            label: try r["label"].decode(String?.self),
            createdAt: try r["created_at"].decode(Date.self)
        )
    }

    /// Caller's SELECT must cast `due_date::text` — without it PostgresNIO
    /// decodes the column's raw binary `date` representation as garbage.
    static func milestone(_ row: PostgresRow) throws -> Milestone {
        let r = row.makeRandomAccess()
        return Milestone(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            title: try r["title"].decode(String.self),
            description: try r["description"].decode(String?.self),
            dueDate: try r["due_date"].decode(String?.self),
            status: try r["status"].decode(String.self),
            closedAt: try r["closed_at"].decode(Date?.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    static func repo(_ row: PostgresRow) throws -> Repo {
        let r = row.makeRandomAccess()
        return Repo(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            name: try r["name"].decode(String.self),
            url: try r["url"].decode(String.self),
            cachedContext: try r["cached_context"].decode(String?.self),
            cachedAt: try r["cached_at"].decode(Date?.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    static func customField(_ row: PostgresRow) throws -> CustomField {
        let r = row.makeRandomAccess()
        let type = try r["type"].decodeEnum(CustomFieldType.self)
        let optionsRaw = try r["options"].decode(AnyCodableValue.self)
        return CustomField(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            key: try r["key"].decode(String.self),
            name: try r["name"].decode(String.self),
            type: type,
            options: try FieldOptions.decode(jsonData: optionsRaw.asJSONData(), type: type),
            position: try r["position"].decode(Double.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    static func view(_ row: PostgresRow) throws -> ZView {
        let r = row.makeRandomAccess()
        let type = try r["type"].decodeEnum(ViewType.self)
        let configRaw = try r["config"].decode(AnyCodableValue.self)
        return ZView(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            name: try r["name"].decode(String.self),
            type: type,
            position: try r["position"].decode(Double.self),
            isDefault: try r["is_default"].decode(Bool.self),
            config: try ViewConfig.decode(jsonData: configRaw.asJSONData(), type: type),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    /// Caller's SELECT must cast `due_date::text`/`start_date::text` — see
    /// `milestone(_:)`.
    static func issue(_ row: PostgresRow) throws -> Issue {
        let r = row.makeRandomAccess()
        return Issue(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            milestoneId: try r["milestone_id"].decode(UUID?.self),
            parentId: try r["parent_id"].decode(UUID?.self),
            title: try r["title"].decode(String.self),
            description: try r["description"].decode(String?.self),
            status: try r["status"].decodeEnum(IssueStatus.self),
            isClosed: try r["is_closed"].decode(Bool.self),
            priority: try r["priority"].decodeEnum(IssuePriority.self),
            tags: try r["tags"].decode([String].self),
            branch: try r["branch"].decode(String?.self),
            estimate: try r["estimate"].decode(String?.self),
            dueDate: try r["due_date"].decode(String?.self),
            startDate: try r["start_date"].decode(String?.self),
            customFieldValues: try r["custom_field_values"].decode([String: AnyCodableValue].self),
            position: try r["position"].decode(Double.self),
            closedAt: try r["closed_at"].decode(Date?.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    static func issueRepoLink(_ row: PostgresRow) throws -> LocalImport.IssueRepoLink {
        let r = row.makeRandomAccess()
        return LocalImport.IssueRepoLink(
            id: try r["id"].decode(UUID.self),
            issueId: try r["issue_id"].decode(UUID.self),
            repoId: try r["repo_id"].decode(UUID.self)
        )
    }
}
