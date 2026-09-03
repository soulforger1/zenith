# Native macOS Rewrite — Audit

Written as subtask 1 of the Electron→native macOS conversion (see the
project's plan history for the full roadmap). This is the frozen snapshot of
"what the Electron+Next.js app actually does" that later subtasks are ported
against — keep it around after subtask 8 deletes the source it describes.

## 1. Electron shell inventory

Source: `electron/main.js` (CommonJS, esbuild-bundled — see file header
comment), `electron/preload-main.js`, `electron/preload-setup.js`,
`electron/setup/{index.html,setup.js}`, `electron-builder.yml`.

**Not present at all**: native app menu, Tray, Dock customization, OS
`Notification`s, file-open/save dialogs (only `dialog.showErrorBox` for fatal
startup errors), custom URL scheme / deep links, Electron `clipboard` module
usage, `shell.openExternal`, auto-updater (`electron-updater`), window-state
persistence (size/position). `electron-builder.yml` targets macOS/DMG only,
is unsigned/unnotarized, `hardenedRuntime: false`, no entitlements file. No
`.github/workflows` — no CI/CD exists.

**What it actually does**, in `main()`'s order:
1. `fixPath()` — spawns `$SHELL -ilc 'echo -n MARKER; echo -n "$PATH"'`
   (`spawnSync`, 10s timeout) to recover the user's real login-shell `PATH`,
   since GUI-launched macOS apps get a minimal one
   (`/usr/bin:/bin:/usr/sbin:/sbin`). Required so the `claude` CLI (installed
   via nvm/homebrew, only on the shell's PATH) is resolvable by the spawned
   Next server's child process. No-op on Windows.
2. `app.whenReady()`, then read `userData/config.json`
   (`{ databaseUrl, githubToken }`) via plain `fs.readFileSync`/`writeFileSync`
   — no `electron-store`.
3. If no config exists (first run, packaged only — dev always uses
   `.env.local` instead): open a small (480×420, non-resizable, no menu bar)
   **setup window** loading `electron/setup/index.html`, bridged via
   `preload-setup.js`'s `window.setupAPI.submit(...)` →
   `ipcRenderer.invoke("setup:submit", ...)`. The one-shot
   `ipcMain.handle("setup:submit", ...)` handler validates the DB URL with a
   real `select 1` probe (`postgres` client, 8s connect timeout), writes
   `config.json`, removes itself, closes the window, resolves the promise
   `main()` is awaiting.
4. Spawn the Next.js **standalone server** as a child process
   (`process.execPath` + `ELECTRON_RUN_AS_NODE=1`, env carries the
   fixed `PATH` plus `DATABASE_URL`/`GITHUB_TOKEN`/`PORT`/`HOSTNAME`), `cwd`
   set to the server's own directory (its `server.js` resolves `.next/`/
   `public/` relative to `cwd`, not `__dirname`). Poll `GET /api/health`
   every 250ms up to 30s (`waitForServerReady`).
5. Open the **main window**: 1280×860, `titleBarStyle: "hidden"` with
   `trafficLightPosition: {x:16,y:16}` (custom traffic-light placement over
   the sidebar — coordinated with a matching drag-region spacer in
   `components/layout/app-sidebar.tsx`), `backgroundColor: "#0a0b0e"`
   (matches the CSS dark `--background`, avoids a white flash during
   live-resize repaint lag), preload `preload-main.js`
   (`contextIsolation: true`, `nodeIntegration: false`).
6. Start the **global double-tap-Option hotkey** listener (darwin-only).

**IPC surface — exactly 2 channels, nothing else**:
- `setup:submit` (renderer→main, `invoke`/`handle`, one-shot) — described above.
- `open-paste-task-modal` (main→renderer, `send`/`on`) — fired from
  `onOptionDoubleTap()`, consumed in
  `components/layout/app-shell.tsx:97` via
  `window.zenithDesktop?.onOpenPasteTaskModal(() => setAiModalOpen(true))`.

**Global hotkey state machine** (`startOptionDoubleTapListener`, darwin only):
uses `uiohook-napi` (native global keyboard hook, ships an unbundled `.node`
binary via `asarUnpack`) because Electron's own `globalShortcut` can only
match full accelerator combos, not a bare modifier tapped twice. Requires
macOS Accessibility permission
(`systemPreferences.isTrustedAccessibilityClient(false)`, prompts via
`(true)` if not yet granted — fails silently/permanently-off if refused).
Constants: `DOUBLE_TAP_WINDOW_MS = 400`, `MAX_TAP_HOLD_MS = 350` (a hold
longer than this is "Option as a modifier for something else," not a tap).
Tracks `optionDownAt`, `optionHeldCleanly` (cleared by any other key while
Option is down), `lastCleanTapAt`; two clean taps within the window trigger
`onOptionDoubleTap()`, which un-minimizes/shows the window, force-focuses the
app (`app.focus({steal:true})`), and sends the IPC event.

**Quit/lifecycle**: `window-all-closed` → kill server + `app.quit()`;
`before-quit`/`will-quit` also kill the server (SIGTERM, SIGKILL after 5s
grace) and stop the uiohook listener. Fatal errors (server spawn/setup
failure) → `dialog.showErrorBox` + `app.quit()`. **No
`requestSingleInstanceLock()`** — multiple instances are not prevented.

## 2. Next.js app inventory

Next.js 16, App Router only (no `pages/`), React 19 RSC + Server Actions,
Tailwind v4, shadcn/ui on `@base-ui/react` primitives (not Radix). **No
auth/session system** — removed in a prior commit (`a50ffff`, "drop web
auth"); single local user, single DB, nothing to port here beyond the
Electron setup flow already described.

**Routes** (`app/(app)/...`):
- `/spaces` — dashboard: grid of space cards (open/total issue counts) +
  "Upcoming" widget (issues due in the next 7 days, across all spaces).
- `/spaces/new` — new space form.
- `/spaces/[slug]/layout.tsx` — per-space chrome: header with dynamic
  **view tabs** (user-created/renamed/duplicated/deleted) + fixed
  Milestones/Settings tabs, search trigger.
- `/spaces/[slug]` — redirects to the space's default (or first) view.
- `/spaces/[slug]/views/[viewId]` — the core screen. One of 3 renderers by
  `views.type`:
  - **table** — sortable/filterable/groupable, bulk select + bulk
    status/priority/delete, inline quick-add.
  - **board** — Kanban via `@dnd-kit`, columns grouped by *any*
    single-select/iteration custom field (not hardcoded to `status`).
  - **roadmap** — Gantt-style timeline from `issues.startDate`/`dueDate`.
  Each view persists its own jsonb `config` (visible fields, filters, sort,
  group-by) — shapes documented in `lib/views/types.ts`.
- `/spaces/[slug]/milestones` — cards with progress (computed on read from
  linked issues, not stored), create dialog.
- `/spaces/[slug]/milestones/[id]` — progress bar, close/reopen, edit,
  flat linked-issue list.
- `/spaces/[slug]/settings` — AI context textarea, custom-field manager,
  GitHub repo manager (link/sync), reference-image gallery (upload/delete),
  all-spaces list, static keyboard-shortcuts reference.
- `app/api/health/route.ts` — trivial health check, polled by Electron.
- `app/api/ai/{parse-task,parse-tasks,generate-subtasks}/route.ts` — AI
  endpoints (see §4).

**Cross-cutting UI** (`components/layout/`):
- `app-shell.tsx` — root client component owning task detail drawer, AI
  paste-task modal, command palette, shortcuts dialog state via
  `AppShellContext` (`app-shell-context.tsx`), exposing
  `openTask`/`openAiModal`/`openCommandPalette` to any descendant.
- `app-sidebar.tsx` — logo, "Paste task" trigger, space list (active state
  via `usePathname()`), collapse toggle persisted to **the one and only
  `localStorage` key**, `zenith:sidebar-collapsed`, search trigger, theme
  toggle.
- `command-palette.tsx` — ⌘K: navigate to space/Milestones/Settings, open AI
  modal, show shortcuts.
- Global keyboard shortcuts (wired in `app-shell.tsx`): `⌘/Ctrl+K` palette,
  `C` paste-task modal, `?` shortcuts dialog, `Escape` close-all, `1`/`2`
  jump to Milestones/Settings within a space.
- Theme: `next-themes`, light/dark/system (its own localStorage key).

## 3. Data layer (`lib/db/schema.ts`, Drizzle + Postgres)

All tables use `uuid` PKs (`defaultRandom()`) and `timestamp with time zone`
audit columns unless noted.

- **`spaces`**: `name`, `slug` (unique), `description`, `context` (free text
  prepended to every AI paste-task prompt for that space).
- **`space_images`**: `spaceId` FK cascade, `dataUrl` (base64, stored inline
  — no object storage), `label`. Sent as multimodal AI context.
- **`milestones`**: `spaceId` FK cascade, `title`, `description`, `dueDate`
  (date), `status` (default `"open"`, unused by UI), `closedAt`. Progress is
  always computed on read from linked issues — never stored.
- **`repos`**: `spaceId` FK cascade, `name` (AI-matched against pasted task
  text), `url`, `cachedContext` (AI-generated summary), `cachedAt` (only
  refreshed by explicit manual sync, never on every parse).
- **`custom_fields`**: `spaceId` FK cascade, `key` (slug, AI-matched by
  name), `name`, `type` ∈ `text|number|date|single_select|multi_select|
  iteration`, `options` jsonb (`FieldOption{id,name,color}[]` for
  select types, `IterationOption{id,title,startDate,durationDays}[]` for
  iteration), `position` (float, fractional ordering).
- **`views`**: `spaceId` FK cascade, `name`, `type` ∈ `table|board|roadmap`,
  `position` (float), `isDefault` (exactly one per space by convention, not
  a DB constraint), `config` jsonb (shape depends on `type`).
- **`issues`**: `spaceId` FK cascade, `milestoneId` FK set-null, `parentId`
  self-FK set-null (**subtasks are just issues with a parent** — deleting a
  parent unlinks, not deletes, its subtasks), `title`, `description`,
  `status` ∈ `backlog|todo|in_progress|done` (default `backlog`), `isClosed`
  bool + `closedAt` (kept in sync with status flipping to/from `done`, but
  the UI is status-driven only — `isClosed` is for future reporting),
  `priority` ∈ `low|medium|high`, `tags` text[], `branch`, `estimate`,
  `dueDate`/`startDate` (date, first-class so Roadmap has a range without a
  custom field), `customFieldValues` jsonb (keyed by `custom_fields.id`;
  value shape depends on the field's `type` — string/number/option-id/
  option-id-array/iteration-id), `position` (float, fractional drag
  ordering within a status column).
- **`issue_repos`**: `issueId`/`repoId` FK cascade both ways, unique
  `(issueId, repoId)` — many-to-many.

**Business logic** — `lib/actions/*.ts` (zod-validated Server Actions,
call `revalidatePath` after mutating) → `lib/db/queries/*.ts` (Drizzle query
functions). Line counts (proxy for port effort):

| File | Actions | Queries |
|---|---|---|
| issues | 299 | 396 |
| views | 82 | 168 |
| spaces | 93 | 58 |
| milestones | 75 | 66 |
| custom-fields | 78 | 66 |
| repos | 71 | 47 |
| space-images | — (folded into spaces actions) | 26 |

`lib/actions/issues.ts` + `lib/db/queries/issues.ts` (695 lines combined) is
the largest and highest-risk surface: create/update, bulk status/priority/
delete, subtask create/link/unlink/search, and **drag-drop reorder position
math** (`updateIssueGroupAction`, fractional position recompute) — this last
piece is the easiest thing to subtly get wrong in a straight port and should
get dedicated unit tests during subtask 3.

**Migrations**: `drizzle.config.ts` runs against `DIRECT_URL` (session-mode
Postgres connection — Supavisor's transaction-pooling mode used at runtime
via `DATABASE_URL` doesn't support the session-level ops `drizzle-kit`
needs for DDL). Both vars live in `.env.local`. Migration SQL already lives
in `drizzle/migrations/0000`–`0006` as plain `.sql` — no Swift migration
engine needed; see decision in §5.

## 4. AI + GitHub integration (hard runtime dependency — must be preserved)

`lib/ai/claude.ts`: every AI feature goes through `runClaudeQuery()`, which
calls `@anthropic-ai/claude-agent-sdk`'s `query()`. That SDK function itself
spawns the **locally-installed `claude` CLI** and speaks a stream-json
protocol to it — **not** a simple flag-based invocation, so subtask 3 must
verify the actual wire protocol directly (`claude --help`, and observing a
live SDK-driven invocation via `ps`/`lsof`) rather than assume one.

**CLI wire protocol, verified live** (subtask 3): `claude -p --input-format
stream-json --output-format stream-json --verbose --tools "" --permission-mode
bypassPermissions --allow-dangerously-skip-permissions [--json-schema
<schema>]`, with a newline-delimited `SDKUserMessage`-shaped JSON message
written to stdin (`{"type":"user","message":{"role":"user","content":[...]},
"parent_tool_use_id":null}`) and newline-delimited JSON messages read from
stdout, terminated by a `type:"result"` message carrying `subtype`,
`result` (text), `structured_output` (when a schema was given), and
`errors`. **`--verbose` is mandatory whenever `--output-format stream-json`
is combined with `-p`** — the CLI errors immediately without it
(`"When using --print, --output-format=stream-json requires --verbose"`);
this isn't a debug-logging opt-in in this mode, easy to miss since it's not
implied by the SDK's own option names. Confirmed matches the SDK's actual
behavior exactly (image content blocks, `structured_output` field, etc.) —
see `macos/Packages/ZenithAI/Sources/ZenithAI/ClaudeCLIClient.swift`.

Key contract details to replicate exactly:
- `BASE_OPTIONS`: `tools: []` (the real safety boundary — no filesystem/
  network access from the model), `maxTurns: 3`, `permissionMode:
  "bypassPermissions"`.
- Structured output via `outputFormat: { type: "json_schema", schema }`
  (root schema must be `type: "object"` — arrays/strings get wrapped under
  an `unwrapKey` and unwrapped after). Response is re-validated against a
  zod schema regardless of the CLI's own schema adherence; falls back to
  `JSON.parse` of the plain `result` text (after stripping ``` code fences)
  if `structured_output` is absent (e.g. an older CLI).
- Timeout via `AbortController` + `setTimeout`, mapped to a
  `"timed out after Nms"` error.
- Error taxonomy (`ClaudeCliError`, all user-facing messages):
  `assistant` message with `.error === "authentication_failed"` → "run
  `claude login`"; any other `result` subtype ≠ `"success"` → include
  `message.errors`; `ENOENT`/`command not found` in a thrown `Error` → "CLI
  not found, install it and run `claude login`"; empty/unparseable/
  schema-mismatched output → distinct messages for each.
- Three flows, all going through `runClaudeJSON`/`runClaudeText`: parse one
  pasted task (text + optional base64 image, media type restricted to
  `image/{jpeg,png,gif,webp}` — validated before sending), parse a pasted
  list into multiple task drafts, generate subtask title suggestions.

`lib/github/client.ts`: plain `fetch` against `api.github.com` (repo
README/tree/package.json) to build `repos.cachedContext`, optional
`GITHUB_TOKEN` bearer header — trivial `URLSession` port, no protocol
subtlety.

## 5. File/clipboard features (native-dialog-relevant)

- **Space reference images**: `<input type=file accept=image/*>` →
  client-side base64 → `addSpaceImageAction` → stored inline in Postgres.
  Maps to `NSOpenPanel` + `Image(nsImage:)`.
- **AI paste-task screenshot attach**: hidden file input *or* direct
  clipboard-image-paste into a textarea (`ClipboardEvent`) → base64 → POST.
  Maps to `NSOpenPanel` + `NSPasteboard.general` image reading.
- **"Copy prompt" button** (`task-detail-drawer.tsx`): builds a work-prompt
  string (`lib/claude-prompt.ts`, pure function — ports verbatim) and writes
  it via `navigator.clipboard.writeText`. Maps to
  `NSPasteboard.general.setString`.
- Toasts (`sonner`) are in-app UI only, not OS notifications — no native
  equivalent needed/expected.

## 6. Architecture decisions for the rewrite

These were made during planning (with the user) and should be treated as
settled unless something in implementation proves them wrong — if so, update
this doc with the reason.

1. **Postgres access**: **PostgresNIO**, used directly from the native app
   (one app-lifetime actor, `ZenithDatabase`) — no local backend process, no
   SQLite migration. Mirrors today's topology (Drizzle → Postgres directly).
   `lib/db/schema.ts` + `drizzle-kit` + `drizzle/migrations/*.sql` are kept
   alive as a small, **unshipped, dev-only tooling folder** purely to
   generate future migration SQL (applied by hand via `psql`) — the one
   deliberate exception to "remove all web tooling" in subtask 8.
2. **Server Actions → Swift**: 1:1 file mapping, `lib/actions/*.ts` →
   `Actions/*.swift`, `lib/db/queries/*.ts` → `Queries/*.swift`, zod schemas
   → Swift structs with a throwing `validate()`. Business rules ported
   line-by-line from the existing TypeScript (not reinvented from observed
   UI behavior) — `issues.ts`'s position-recompute math gets dedicated
   tests. `revalidatePath`/`router.refresh()` → `@Observable` view models
   updating in-memory state directly on action success.
3. **AI CLI integration**: `Foundation.Process` + `Pipe` to spawn `claude`,
   after verifying the SDK's actual stream-json protocol (not assumed).
   Port `fixPath()` verbatim in spirit (spawn `$SHELL -ilc 'echo $PATH'`,
   reuse the result for every `claude` invocation — an OS-level minimal-PATH
   problem, not Electron-specific). Preserve the 3 flows and the exact error
   taxonomy above. `GitHubClient` is a trivial `URLSession` port.
4. **Global hotkey**: double-tap-Option is a bare-modifier gesture that
   Carbon `RegisterEventHotKey` cannot express (the same reason Electron
   reached for `uiohook-napi` instead of `globalShortcut`). Use
   `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` +
   `AXIsProcessTrusted()` (native equivalent of
   `isTrustedAccessibilityClient`) — same Accessibility-permission
   requirement as today, an OS constraint not a gap. Port the state machine
   (`DOUBLE_TAP_WINDOW_MS = 400`, `MAX_TAP_HOLD_MS = 350`, clean-hold
   tracking) near-verbatim from `main.js`.
5. **Deployment target**: macOS 14 (Sonoma) minimum, confirmed against the
   user's actual running OS during subtask 2 — unlocks `@Observable`,
   modern `Table`/`.draggable`/`.inspector`; no back-compat matrix needed
   for a personal single-Mac app.
6. **SwiftUI-first, no AppKit interop expected**: `Table` for the table
   view, `.draggable`/`.dropDestination` for the Kanban board, a custom
   `Canvas` for the roadmap/Gantt view. `NSViewRepresentable`/`NSTableView`
   kept in mind only as a contingency for the table view if `Table`'s
   per-cell customization (inline edit, colored badges) proves too limited.
7. **Setup/secrets**: one-time setup flow as a SwiftUI sheet;
   `databaseUrl` in `~/Library/Application Support/Zenith/config.json`
   (needed plaintext at startup anyway, same as today), `githubToken`
   promoted to **macOS Keychain** — a real security upgrade over today's
   plaintext file, trivial to do natively.
8. **Signing/distribution**: user has no Apple Developer Program membership
   and doesn't want one — personal use on their own Mac only. Ad-hoc
   signing ("Sign to Run Locally"), no notarization, no CI/CD, App Sandbox
   left off (matches today's unsigned/unhardened posture).

## 7. What's explicitly out of scope

Nothing here exists today and nothing in the request asks for it — don't add
it as incidental scope creep during the rewrite: OS notifications, deep
links/custom URL scheme, auto-update/Sparkle, multi-window support, single-
instance locking, App Store distribution, code signing beyond ad-hoc.
