# Zenith — contributor & agent guide

Zenith is a **native macOS app** (SwiftUI, Swift 6, macOS 14.4+) that
connects **directly to a Postgres database** via PostgresNIO. No backend
server, no web frontend. It began as an Electron + Next.js app that was
rewritten natively; the old shell and web code have been removed and the
Swift app is now the whole repo.

## Layout

- `project.yml` — **XcodeGen spec, the source of truth for the Xcode
  project.** `Zenith.xcodeproj` is generated from it; don't hand-edit the
  project settings.
- `Zenith/` — the app target (SwiftUI views, view models, app state,
  setup flow).
- `Packages/ZenithData/` — data + business logic. Direct replacement for
  the old `lib/db/` (Drizzle) and `lib/actions/` (zod-validated Server
  Actions): `Models/`, `Queries/` (raw SQL via PostgresNIO), `Actions/`
  (validated mutations), `Support/`, `Config/` (`AppConfig` =
  `config.json`, `KeychainStore` = GitHub token).
- `Packages/ZenithAI/` — Claude CLI integration + GitHub client. Replaces
  `lib/ai/*` and `lib/github/client.ts`. Spawns the local `claude` CLI
  over the stream-json protocol (see `ClaudeCLIClient`).
- `db/` — **dev-only** schema-migration tooling: `db/schema.ts`,
  `db/drizzle.config.ts`, `db/migrations/`, `db/package.json` (see
  below). Never shipped.
- `Scripts/`, `branding/` — app-icon generator + rasterized assets.
- `docs/` — build/packaging guide.

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
  Gatekeeper implications are in `docs/build-and-package.md`.

### Tests

```sh
cd Packages/ZenithData && swift test
cd Packages/ZenithAI   && swift test
```

Live database / AI tests are opt-in via env vars (`ZENITH_LIVE_DB_TESTS=1`
+ `ZENITH_TEST_DATABASE_URL`, `ZENITH_LIVE_AI_TESTS=1`); the default run
skips them.

## Changing the database schema

The app itself runs **no** migrations — it assumes the tables already
exist in whatever database it's pointed at. The Drizzle tooling in `db/`
exists only to author migration SQL. Run it from `db/`:

1. Edit `db/schema.ts`.
2. `cd db`, then `bun install` (first time) and `bun run db:generate` —
   writes a new `db/migrations/NNNN_*.sql` + snapshot.
3. Review the SQL and apply it by hand: `psql "$DIRECT_URL" -f migrations/NNNN_*.sql`
   (`DIRECT_URL` = a session-mode, non-pooled connection string; copy
   `db/.env.example` to `db/.env.local`). `bun run db:migrate` /
   `db:push` / `db:studio` also work if you prefer.
4. Update the corresponding Swift `Models/` / `Queries/` in `ZenithData`
   to match.
