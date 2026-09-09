# Zenith

A personal, single-user macOS task / issue tracker: spaces, issues with
custom fields, table / Kanban / roadmap views, milestones, GitHub repo
context, and AI task parsing via the local `claude` CLI.

Zenith is a **native macOS app** (SwiftUI, Swift 6) that talks **directly
to a Postgres database** with [PostgresNIO](https://github.com/vapor/postgres-nio) —
there is no backend server. It started as an Electron-wrapped Next.js app;
that codebase was rewritten natively and removed.

## Repository layout

| Path | What |
|---|---|
| `Zenith/` | The app target — SwiftUI views, view models, app state, setup flow. |
| `Packages/` | Two local SwiftPM packages: `ZenithData` (models, raw-SQL queries, validated mutations) and `ZenithAI` (Claude CLI + GitHub client). |
| `project.yml` | XcodeGen spec — the source of truth for `Zenith.xcodeproj` (generated, don't hand-edit). |
| `Scripts/`, `branding/` | App-icon generator and rasterized icon assets. |
| `db/` | **Dev-only** Drizzle tooling for authoring Postgres schema migrations (`db/schema.ts`, `db/migrations/`). Not part of the shipped app. |
| `docs/` | Build & packaging guide. |
| `AGENTS.md` | Contributor & agent conventions — read this first. |

## Build & run

Prerequisites: Xcode (26.5+), and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
xcodegen generate
open Zenith.xcodeproj   # then ⌘R, or use xcodebuild
```

On first launch the app asks for a Postgres connection string (and an
optional GitHub token). Full build, packaging, signing, and first-launch
details are in **[`docs/build-and-package.md`](docs/build-and-package.md)**.

## Database schema changes

The app runs no migrations. To change the schema: edit `db/schema.ts`,
then from `db/` run `bun run db:generate` and apply the new
`db/migrations/*.sql` by hand with `psql`. See `AGENTS.md`.
