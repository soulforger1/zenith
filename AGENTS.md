# Zenith — contributor & agent guide

Zenith is a **native macOS app** (SwiftUI, Swift 6, macOS 14.4+) that is
**local-first**: the single source of truth is a SQLite database (GRDB) on
disk, and the app opens straight into it with no setup step. Sync to a
remote Postgres database is optional, off by default, periodic, and
configured in Settings → Sync (⌘,) — see `Packages/ZenithSync/` and
`docs/sync.md`. A synced-folder (iCloud Drive) target is planned but not
built yet. No backend server, no web frontend. It began as an Electron +
Next.js app, then a direct-Postgres native rewrite; both the old shell/web
code and the direct-Postgres connection have since been removed.

## Layout

- `project.yml` — **XcodeGen spec, the source of truth for the Xcode
  project.** `Zenith.xcodeproj` is generated from it; don't hand-edit the
  project settings.
- `Zenith/` — the app target (SwiftUI views, view models, app state,
  first-run Postgres-import sheet, `Sync/` = `SyncCoordinator` +
  `DataChangeBroadcaster`, `UI/AppSettings/` = the Settings → Sync pane).
- `Packages/ZenithData/` — local-first data + business logic, **GRDB only**
  (no networking dependency): `Models/`, `Database/` (the GRDB store +
  `Database/Schema/Migrations.swift`, the local schema's source of truth),
  `Queries/` (raw SQL via GRDB), `Actions/` (validated mutations),
  `Import/` (bulk upsert used by the Postgres importer), `Sync/` (schema-
  agnostic sync primitives — `SyncTable`, `SyncRow`/`SyncDelta`,
  `LocalSyncStore` — used by `ZenithSync`, never by the app directly),
  `Support/`, `Config/` (`AppConfig` = `config.json`, `KeychainStore` =
  GitHub token + Postgres sync connection string).
- `Packages/ZenithSync/` — everything that talks to a *remote* store, kept
  separate so `ZenithData` never needs PostgresNIO/SwiftNIO. `Postgres/`
  (a short-lived Postgres connection, `PostgresGateway`, plus the generic
  Postgres ⇄ `SyncValue` column mapping), `Import/` (`PostgresImporter` —
  one-time copy of an existing Postgres database into the local store),
  `Engine/` (`SyncTarget` protocol, `SyncReconciler` — the bidirectional
  last-write-wins round), `Targets/` (`PostgresSyncTarget`; an iCloud-
  folder target is planned but not built). See `docs/sync.md` for the
  model.
- `Packages/ZenithAI/` — Claude CLI integration + GitHub client. Spawns the
  local `claude` CLI over the stream-json protocol (see `ClaudeCLIClient`).
  Depends only on `ZenithData`.
- `db/` — **dev-only** schema-authoring tooling for the *Postgres sync
  target's* schema: `db/schema.ts`, `db/drizzle.config.ts`,
  `db/migrations/`, `db/package.json` (see below). Never shipped; not the
  local app schema (see "Changing the database schema" below).
- `Scripts/`, `branding/` — app-icon generator + rasterized assets.
- `docs/` — build/packaging guide, and the sync model (`docs/sync.md`).

## Working on the app

```sh
xcodegen generate      # after adding/removing/moving files under Zenith/
open Zenith.xcodeproj   # ⌘R to run

# or headless:
xcodebuild -project Zenith.xcodeproj -scheme Zenith -configuration Debug \
  -destination 'platform=macOS' build
```

- **New Swift files in the app target** (`Zenith/`) are picked up by
  re-running `xcodegen generate` (its `sources` globs are recursive). If
  you must add one without regenerating, `project.pbxproj` is a classic
  explicit-file-list project — see the four hand-edit spots in the
  `macos-xcodeproj-manual-file-add` note (its paths are relative to the
  repo root now, no `macos/` prefix). New files in the SwiftPM packages
  are picked up automatically.
- Signing is ad-hoc only (no Apple Developer account) — details and the
  Gatekeeper implications are in `docs/build-and-package.md`. This is also
  why the (future) iCloud sync target is a plain synced folder rather than
  CloudKit: CloudKit needs App Sandbox + iCloud entitlements + a paid
  Developer Program membership, none of which this project has.

### Tests

```sh
cd Packages/ZenithData && swift test   # no external services needed — in-memory GRDB
cd Packages/ZenithSync && swift test
cd Packages/ZenithAI   && swift test
```

`ZenithData`'s tests run fully offline now (an in-memory SQLite store per
test via `ZenithDatabase.inMemory()`), including the sync engine's
last-write-wins/tombstone/resurrection edge cases (`LocalSyncStoreTests`)
and a full bidirectional round against an in-memory `MockSyncTarget`
(`ZenithSync`'s `SyncReconcilerTests`) — no real Postgres needed for any of
that. Live-service tests are still opt-in via env vars:
`ZENITH_LIVE_DB_TESTS=1` + `ZENITH_TEST_DATABASE_URL` gates `ZenithSync`'s
`PostgresImporterLiveTests` and `PostgresSyncTargetLiveTests` (a real
Postgres database, migrated per "Changing the Postgres sync target's
schema" below), `ZENITH_LIVE_AI_TESTS=1` gates `ZenithAI`'s live Claude CLI
test. The default run skips all of these.

## Changing the local (SQLite) schema

The app owns and migrates its own local schema now — there's no "tables
must already exist" assumption. To change it:

1. Edit `Packages/ZenithData/Sources/ZenithData/Database/Schema/Migrations.swift`,
   adding a new `migrator.registerMigration("vN") { db in ... }` (never
   edit a migration that's already shipped — SQL changes are additive
   migrations, same as any other GRDB/Core Data/Rails-style migrator).
2. Update the corresponding Swift `Models/` / `Queries/` in `ZenithData` to
   match.
3. Add/update a test in `Packages/ZenithData/Tests/ZenithDataTests/QueriesTests/`.

## Changing the Postgres sync target's schema

This matters for `ZenithSync`'s `PostgresImporter` (reads an existing
pre-local-first database) and `PostgresSyncTarget` (the live sync target).
The Drizzle tooling in `db/` exists to author that remote schema's
migration SQL — it is **not** consulted by the app itself. Run it from
`db/`:

1. Edit `db/schema.ts`.
2. `cd db`, then `bun install` (first time) and `bun run db:generate` —
   writes a new `db/migrations/NNNN_*.sql` + snapshot. This only diffs
   against the local snapshot files, no database connection needed.
3. Review the SQL and apply it by hand: `psql "$DIRECT_URL" -f migrations/NNNN_*.sql`
   (`DIRECT_URL` = a session-mode, non-pooled connection string; copy
   `db/.env.example` to `db/.env.local`). `bun run db:migrate` /
   `db:push` / `db:studio` also work if you prefer.
4. Update the Swift side to match — same column set, both directions:
   - `Packages/ZenithData/Sources/ZenithData/Database/Schema/Migrations.swift`
     and `Packages/ZenithData/Sources/ZenithData/Sync/SyncTable.swift`
     (add the local mirror of any new/changed column or table).
   - `Packages/ZenithSync/Sources/ZenithSync/Postgres/PostgresRowMapping.swift`
     (the Phase-1 importer's typed mapping) and `PostgresSyncTarget.swift`'s
     `selectColumns` (the sync target's SELECT column lists — both need the
     same `::text` cast on any `date` column, same as `due_date`/
     `start_date`).
   - `Packages/ZenithSync/Sources/ZenithSync/Postgres/PostgresColumnCatalog.swift`
     — add the new column name to the right `PostgresColumnKind` case (this
     one catalog drives both the sync target's pull-side decode and
     push-side bind/cast for every table, so it's usually the only change
     needed beyond the column showing up in `SELECT *`/`INSERT`).
