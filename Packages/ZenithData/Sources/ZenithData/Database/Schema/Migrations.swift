import Foundation
import GRDB

/// The local SQLite schema. This app runs its own migrations now (unlike
/// the former direct-Postgres setup, which assumed the tables already
/// existed) — add a `registerMigration("vN")` for every schema change.
///
/// Column translation from the Postgres schema (`db/schema.ts`):
/// `uuid` → `TEXT` (lowercased), `timestamptz` → `TEXT` (GRDB's canonical
/// `yyyy-MM-dd HH:mm:ss.SSS` UTC form), `date` → `TEXT` "YYYY-MM-DD",
/// `jsonb`/`text[]` → `TEXT` JSON, `boolean` → `INTEGER`, `double precision`
/// → `REAL`. No `gen_random_uuid()` / `now()` defaults — the app supplies
/// ids and timestamps on write.
let zenithMigrator: DatabaseMigrator = {
    var migrator = DatabaseMigrator()
    #if DEBUG
    // During development, wipe + rebuild if a registered migration's body
    // changes. Safe here: the local DB is a cache of the sync targets (or
    // re-importable from Postgres) until Phase 2/3 make it authoritative.
    migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1") { db in
        try db.execute(sql: """
            CREATE TABLE spaces (
              id TEXT PRIMARY KEY NOT NULL,
              name TEXT NOT NULL,
              slug TEXT NOT NULL UNIQUE,
              description TEXT,
              context TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE space_images (
              id TEXT PRIMARY KEY NOT NULL,
              space_id TEXT NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
              data_url TEXT NOT NULL,
              label TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE INDEX space_images_space_id_idx ON space_images(space_id);

            CREATE TABLE milestones (
              id TEXT PRIMARY KEY NOT NULL,
              space_id TEXT NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
              title TEXT NOT NULL,
              description TEXT,
              due_date TEXT,
              status TEXT NOT NULL DEFAULT 'open',
              closed_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE INDEX milestones_space_id_idx ON milestones(space_id);

            CREATE TABLE repos (
              id TEXT PRIMARY KEY NOT NULL,
              space_id TEXT NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
              name TEXT NOT NULL,
              url TEXT NOT NULL,
              cached_context TEXT,
              cached_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE INDEX repos_space_id_idx ON repos(space_id);

            CREATE TABLE custom_fields (
              id TEXT PRIMARY KEY NOT NULL,
              space_id TEXT NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
              key TEXT NOT NULL,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              options TEXT NOT NULL DEFAULT '[]',
              position REAL NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE INDEX custom_fields_space_id_idx ON custom_fields(space_id);

            CREATE TABLE views (
              id TEXT PRIMARY KEY NOT NULL,
              space_id TEXT NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              position REAL NOT NULL DEFAULT 0,
              is_default INTEGER NOT NULL DEFAULT 0,
              config TEXT NOT NULL DEFAULT '{}',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE INDEX views_space_id_idx ON views(space_id);

            CREATE TABLE issues (
              id TEXT PRIMARY KEY NOT NULL,
              space_id TEXT NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
              milestone_id TEXT REFERENCES milestones(id) ON DELETE SET NULL,
              parent_id TEXT REFERENCES issues(id) ON DELETE SET NULL,
              title TEXT NOT NULL,
              description TEXT,
              status TEXT NOT NULL DEFAULT 'backlog',
              is_closed INTEGER NOT NULL DEFAULT 0,
              priority TEXT NOT NULL DEFAULT 'medium',
              tags TEXT NOT NULL DEFAULT '[]',
              branch TEXT,
              estimate TEXT,
              due_date TEXT,
              start_date TEXT,
              custom_field_values TEXT NOT NULL DEFAULT '{}',
              position REAL NOT NULL DEFAULT 0,
              closed_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE INDEX issues_space_id_status_idx ON issues(space_id, status);
            CREATE INDEX issues_milestone_id_idx ON issues(milestone_id);
            CREATE INDEX issues_parent_id_idx ON issues(parent_id);

            CREATE TABLE issue_repos (
              id TEXT PRIMARY KEY NOT NULL,
              issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
              repo_id TEXT NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
              updated_at TEXT NOT NULL
            );
            CREATE UNIQUE INDEX issue_repos_issue_repo_idx ON issue_repos(issue_id, repo_id);
            CREATE INDEX issue_repos_repo_id_idx ON issue_repos(repo_id);

            -- Sync scaffolding: created now so Phase 2 needs no migration.
            -- Inert until a sync target is enabled.
            CREATE TABLE sync_tombstones (
              table_name TEXT NOT NULL,
              row_id TEXT NOT NULL,
              deleted_at TEXT NOT NULL,
              space_id TEXT,
              PRIMARY KEY (table_name, row_id)
            );
            CREATE INDEX sync_tombstones_deleted_at_idx ON sync_tombstones(deleted_at);

            CREATE TABLE sync_state (
              target TEXT PRIMARY KEY NOT NULL,
              last_pulled_at TEXT,
              last_pushed_at TEXT,
              last_success_at TEXT,
              last_error TEXT,
              cursor TEXT
            );
            """)

        // AFTER DELETE triggers so cascade deletes (a space taking its
        // issues/views/... with it) also leave tombstones for the sync
        // layer. `strftime('%Y-%m-%d %H:%M:%f','now')` is UTC and matches
        // GRDB's `Date` text format, so tombstone timestamps compare
        // directly against a row's `updated_at`.
        for table in ["spaces", "space_images", "milestones", "repos", "custom_fields", "views", "issues", "issue_repos"] {
            try db.execute(sql: """
                CREATE TRIGGER trg_\(table)_tombstone AFTER DELETE ON \(table) BEGIN
                  INSERT OR REPLACE INTO sync_tombstones(table_name, row_id, deleted_at)
                  VALUES ('\(table)', OLD.id, strftime('%Y-%m-%d %H:%M:%f','now'));
                END;
                """)
        }
    }

    return migrator
}()
