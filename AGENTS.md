# Zenith — contributor & agent guide

Zenith is a **native macOS app** (SwiftUI, Swift 6, macOS 14.4+) that
connects **directly to a Postgres database** via PostgresNIO. No backend
server, no web frontend — the Electron + Next.js codebase this replaced
was removed after the native rewrite reached parity
(`docs/native-rewrite-audit.md`, `docs/parity-checklist.md`).

## Layout

- `macos/` — the app.
  - `macos/project.yml` — **XcodeGen spec, the source of truth for the
    Xcode project.** `macos/Zenith.xcodeproj` is generated from it; don't
    hand-edit the project settings.
  - `macos/Zenith/` — the app target (SwiftUI views, view models, app
    state, setup flow).
  - `macos/Packages/ZenithData/` — data + business logic. Direct
    replacement for the old `lib/db/` (Drizzle) and `lib/actions/`
    (zod-validated Server Actions): `Models/`, `Queries/` (raw SQL via
    PostgresNIO), `Actions/` (validated mutations), `Support/`,
    `Config/` (`AppConfig` = `config.json`, `KeychainStore` = GitHub
    token).
  - `macos/Packages/ZenithAI/` — Claude CLI integration + GitHub client.
    Replaces `lib/ai/*` and `lib/github/client.ts`. Spawns the local
    `claude` CLI over the stream-json protocol (see `ClaudeCLIClient`).
- `db/schema.ts`, `drizzle/`, `drizzle.config.ts`, root `package.json` —
  **dev-only** schema-migration tooling (see below). Never shipped.
- `docs/` — build/packaging guide + rewrite history.

## Working on the app

```sh
cd macos
xcodegen generate      # after adding/removing/moving files under macos/Zenith/
open Zenith.xcodeproj   # ⌘R to run

# or headless:
xcodebuild -project Zenith.xcodeproj -scheme Zenith -configuration Debug \
  -destination 'platform=macOS' build
```

- **New Swift files in the app target** (`macos/Zenith/`) are picked up by
  re-running `xcodegen generate` (its `sources` globs are recursive). If
  you must add one without regenerating, `project.pbxproj` is a classic
  explicit-file-list project — see the four hand-edit spots in the
  `macos-xcodeproj-manual-file-add` note. New files in the SwiftPM
  packages are picked up automatically.
- Signing is ad-hoc only (no Apple Developer account) — details and the
  Gatekeeper implications are in `docs/build-and-package.md`.

### Tests

```sh
cd macos/Packages/ZenithData && swift test
cd macos/Packages/ZenithAI   && swift test
```

Live database / AI tests are opt-in via env vars (`ZENITH_LIVE_DB_TESTS=1`
+ `ZENITH_TEST_DATABASE_URL`, `ZENITH_LIVE_AI_TESTS=1`); the default run
skips them.

## Changing the database schema

The app itself runs **no** migrations — it assumes the tables already
exist in whatever database it's pointed at. The Drizzle tooling here
exists only to author migration SQL:

1. Edit `db/schema.ts`.
2. `bun install` (first time), then `bun run db:generate` — writes a new
   `drizzle/migrations/NNNN_*.sql` + snapshot.
3. Review the SQL and apply it by hand: `psql "$DIRECT_URL" -f drizzle/migrations/NNNN_*.sql`
   (`DIRECT_URL` = a session-mode, non-pooled connection string; copy
   `.env.example` to `.env.local`). `bun run db:migrate` / `db:push` /
   `db:studio` also work if you prefer.
4. Update the corresponding Swift `Models/` / `Queries/` in `ZenithData`
   to match.
