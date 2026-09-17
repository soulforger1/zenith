# Zenith

A personal, single-user macOS task / issue tracker: spaces, issues with
custom fields, table / Kanban / roadmap views, milestones, GitHub repo
context, and AI task parsing via the local `claude` CLI.

Zenith is a **native macOS app** (SwiftUI, Swift 6) that is **local-first**:
it stores everything in a SQLite database on disk and opens straight into
it, no setup step required. Sync to a remote Postgres database is
optional, off by default, and periodic — turn it on in Settings → Sync
(⌘,). A synced-folder (iCloud Drive) target is planned but not built yet.
It started as an Electron-wrapped Next.js app, was rewritten natively
against a direct Postgres connection, and has since moved to this
local-first model.

## Repository layout

| Path | What |
|---|---|
| `Zenith/` | The app target — SwiftUI views, view models, app state, first-run Postgres-import sheet, the Settings → Sync pane. |
| `Packages/` | Three local SwiftPM packages: `ZenithData` (local-first store — models, raw-SQL GRDB queries, validated mutations, schema-agnostic sync primitives), `ZenithSync` (everything that talks to a remote store — the Postgres importer and the bidirectional Postgres sync target; an iCloud-folder target lands in a later phase), and `ZenithAI` (Claude CLI + GitHub client). |
| `project.yml` | XcodeGen spec — the source of truth for `Zenith.xcodeproj` (generated, don't hand-edit). |
| `Scripts/`, `branding/` | App-icon generator and rasterized icon assets. |
| `db/` | **Dev-only** Drizzle tooling for authoring the *Postgres sync target's* schema migrations (`db/schema.ts`, `db/migrations/`) — not the local app schema (see `AGENTS.md`). Not part of the shipped app. |
| `docs/` | Build & packaging guide, and the sync model (`docs/sync.md`). |
| `AGENTS.md` | Contributor & agent conventions — read this first. |

## Build & run

Prerequisites: Xcode (26.5+), and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
xcodegen generate
open Zenith.xcodeproj   # then ⌘R, or use xcodebuild
```

On first launch the app opens straight into its local database — no setup
screen. If it finds a connection string from a pre-local-first install, it
offers a one-time import of that data. Sync is off by default; turn it on
in Settings → Sync (see [`docs/sync.md`](docs/sync.md)). Full build,
packaging, signing, and first-launch details are in
**[`docs/build-and-package.md`](docs/build-and-package.md)**.

## Database schema

The app owns and migrates its local SQLite schema itself (see
`Packages/ZenithData/Sources/ZenithData/Database/Schema/Migrations.swift`).
The Drizzle tooling in `db/` is separate, dev-only tooling for the schema
of the *optional Postgres sync target*; see `AGENTS.md`.
