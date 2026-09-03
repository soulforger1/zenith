# Subtask 7 — parity + performance verification

Checklist derived from `docs/native-rewrite-audit.md`, walked against the
native app (`macos/`) with the still-installed Electron build
(`/Applications/Zenith.app`) kept as the reference until this signs off.
Legend: **OK** (verified working/matching), **FIXED** (a real gap found
during this pass and closed before this doc was written), **DEFERRED** (a
known, deliberate gap — documented below, not silently dropped), **N/A**
(doesn't apply to a single-user native app).

## Routes / screens

| Web route | Native equivalent | Status |
|---|---|---|
| `/spaces` (dashboard + upcoming) | `SpacesDashboardView` | OK |
| `/spaces/new` | `NewSpaceView` | OK |
| `/spaces/[slug]` (redirect to default view) | `SpaceLandingView` | OK |
| `/spaces/[slug]/views/[viewId]` (table) | `IssueTableView` | OK, see Table view notes below |
| `/spaces/[slug]/views/[viewId]` (board) | `KanbanBoardView` | OK |
| `/spaces/[slug]/views/[viewId]` (roadmap) | `RoadmapView` | OK |
| `/spaces/[slug]/milestones` | `MilestonesListView` | OK |
| `/spaces/[slug]/milestones/[id]` | `MilestoneDetailView` | OK |
| `/spaces/[slug]/settings` | `SettingsView` | OK, minus the standalone "Spaces" quick-list and static keyboard-shortcuts table (DEFERRED — the sidebar already covers space-switching; no shortcuts sheet exists yet to document) |
| Task detail drawer | `TaskDetailView` (`.inspector`) | OK — found missing entirely during live testing (never wired up across any of subtask 4's slices), built and fixed before this pass |
| AI paste-task modal | `PasteTaskModal` | OK, see AI notes below |
| Command palette (⌘K) | — | **DEFERRED** — never built. Not blocking (sidebar + menu commands cover the same actions), but a real gap: `⌘K`/`isCommandPalettePresented` exist as plumbing in `AppShellModel` with nothing behind them. Worth a follow-up if global search across spaces/tasks becomes something you reach for. |
| Shortcuts dialog (`?`) | — | **DEFERRED** — same as above, plumbing exists, no UI. |

## Table view — dynamic columns / bulk actions / filter bar

Found during this pass: `FieldRegistry.build` only ever emitted 5 built-in
fields (status/priority/milestone/dueDate/startDate) — the actual
`buildFieldRegistry` on the web side emits **9** (also tags, repoIds,
branch, estimate). The Board/Roadmap-driven port from subtask 4 had
silently narrowed the registry to just what those two views needed;
nothing forced a correction until the Table view actually needed the full
set. **Fixed**: added the missing 4 built-ins, plus a new
`FieldDef.displayValue(for:)` (port of `FieldBadge`'s render-dispatch) and
`FieldDisplayValueView` so any field — built-in or custom, any type — can
be shown in a table cell without the view needing its own copy of that
dispatch logic. 45 `ZenithData` tests now (8 added for this).

`IssueTableView` now drives its columns from the view's own
`TableViewConfig.visibleFieldIds` (defaulting to `["status", "priority"]`,
matching `getOrCreateDefaultViewsForSpace`'s seed on both sides) instead
of always showing a hardcoded Status/Priority/Due set — a real
correctness fix, not just an enhancement: the old version showed a Due
column even though `dueDate` was never in the default `visibleFieldIds`
on the web side either. Status/priority stay interactively editable
in-cell (an intentional native enhancement beyond the web build, which
only lets you change them via the task detail drawer). Bulk selection
toolbar (set status/set priority/delete across a multi-selection) added,
wired to `IssueActions.bulkUpdateStatus/bulkUpdatePriority/bulkDeleteIssues`
— all three already existed from subtask 3, just never called from a view.

**DEFERRED, explicitly**: the keyword/field filter bar
(`ViewFilterBar`/`applyKeyword`/`applyFilters`), per-column sort/hide via
a column menu, table row grouping (`groupIssuesBy`), and the
view-settings popover that lets you edit `visibleFieldIds`/sort/filters
in the first place. None of `lib/fields/filter.ts` has been ported to
Swift at all — this is real, non-trivial business logic (not view
boilerplate), and closing it properly means a dedicated pass with its own
tests, the same rigor subtask 3 gave `lib/position.ts`/`lib/fields/
registry.ts`. Given personal single-user scale, it's being called a
deliberate scope cut for this rewrite rather than something to rush —
flagging it here so it's a decision, not a surprise.

## Board / Roadmap

- Drag-drop position math (`Position.atEnd`/`Position.between`): unit
  tested (`PositionTests`), and re-verified by reading `lib/position.ts`
  side by side with `Support/Position.swift` again during this pass — the
  `GAP = 1000`/midpoint/half-gap formulas match exactly.
- Same-column reordering (per-card `.dropDestination`) and cross-column
  moves: fixed and confirmed by the user during the subtask-4 UI pass.
- Roadmap's `resolveRange` (including the same-field-iteration special
  case): unit tested (`FieldRegistryTests`).
- **DEFERRED** (unchanged from subtask 4's own notes): Milestone detail's
  linked-task chips scroll horizontally instead of true flex-wrap — a
  polish item, not a functional gap.

## Data/business logic

- **jsonb merge-patch**: `IssueActions`/`IssueQueries.updateIssueFields`
  issues the same `custom_field_values = custom_field_values || $1::jsonb`
  Postgres merge the TS side uses — re-confirmed by reading both this
  pass. A concurrent update can't clobber the other's custom field writes
  on either side.
- **`isClosed`/`closedAt` derivation**: still the only place either
  changes, tied to a `status` patch, matching `lib/actions/issues.ts`.
- **Cycle detection** (`wouldCreateCycle`): ported with the same 50-hop
  ancestor walk; exercised live via the task detail drawer's "Link
  existing…" / subtask promotion flows.
- **Milestone progress**: confirmed computed on read in both
  `MilestonesListView` and `MilestoneDetailView` (`model.issues.filter
  { $0.milestoneId == ... }`, counted fresh every render) — never stored,
  matching the "computed on read" rule.
- **AI error taxonomy**: re-read `lib/ai/claude.ts`'s
  `describeAssistantError`/ENOENT-detection/code-fence-stripping against
  `ClaudeCLIClient.swift` line by line this pass — identical user-facing
  strings for `authentication_failed`, the generic assistant-error
  fallback, the "CLI not found" message, and the code-fence JSON fallback.
- **Date columns**: `::text` casts confirmed still in place in
  `IssueQueries`/`MilestoneQueries` (the fix from the UI pass) —
  regression-tested by the live `dateColumnsDecodeCorrectly` test.

## Keyboard shortcuts

| Web (`app-shell.tsx`) | Native | Status |
|---|---|---|
| `Escape` closes all overlays | `AppShellModel.closeAll()` exists | **DEFERRED** — nothing currently calls it on an Escape key press; the sheets/inspector can still be dismissed via their own close buttons or the standard sheet-dismiss gesture, just not a global Escape. Small, worth a follow-up. |
| `⌘K` command palette | — | DEFERRED, see above |
| bare `c` opens paste-task modal | **Not ported** — replaced with ⌘⇧V + global double-tap-Option | Deliberate divergence, see subtask 5 notes: the web guard ("only when not typing") has no SwiftUI equivalent, so the bare-key version would eat the letter "c" out of every text field. |
| `?` opens shortcuts dialog | — | DEFERRED, no dialog exists yet |
| `1`/`2` jump to Milestones/Settings while in a space | — | **DEFERRED** — not ported; the segmented picker in the toolbar covers the same navigation with a click. |

## OS integrations (subtask 5, re-confirmed here)

- Global double-tap-Option hotkey: built, Accessibility-gated, not yet
  live-tested by the user (still outstanding from subtask 5 — worth doing
  before considering this fully signed off).
- `NSOpenPanel`-equivalent (`.fileImporter`) for image picking: working
  (Settings gallery, AI modal screenshot attach).
- `NSPasteboard`: working (screenshot paste in the AI modal, "Copy
  prompt" in task detail).
- Explicitly out of scope, confirmed against the audit: OS notifications,
  deep links, auto-update — none exist in the Electron build, none
  requested.

## Performance

Attempted a side-by-side cold-launch/memory measurement against
`/Applications/Zenith.app` (the Electron build) on this Mac.

**Native app** — measured directly, reliably reproducible:
- Window visible ≈ **0.6s** after launch.
- RSS after a few seconds settled ≈ **128 MB**.

**Electron app** — inconclusive, reported honestly rather than guessed:
during this session's launch attempts, the Electron build's main process
started (visible in `ps`, ~130 MB RSS, no crash) but never actually
produced a window (`System Events` reported 0 windows after 90+ seconds),
and no Next.js server child process ever appeared under it — consistent
with `startAppServerAndOpenWindow`'s spawn-then-poll-health sequence
never completing, for a reason this session couldn't pin down (possibly
environment-specific to this launch, not necessarily a standing bug).
Rather than report a fabricated or misleading number, the honest
conclusion is: **the automated comparison is unverified this round** — a
manual side-by-side (just watching the dock icon bounce/window appear for
both apps) is worth doing directly rather than trusting this doc's
numbers for the Electron side.

What *is* a safe, qualitative claim regardless of the exact Electron
number: the native app has no Chromium/Node runtime to boot at all (no
renderer/GPU/network helper processes, confirmed via `ps` — just the one
process), and 128 MB is well below what any Electron app's baseline
Chromium footprint alone typically costs before a single line of app
code runs. The architectural win this rewrite was for is real regardless
of the exact head-to-head number.

## Open items before calling subtask 7 fully signed off

1. User to live-test the double-tap-Option global hotkey (grant
   Accessibility permission, confirm it works both focused and
   unfocused) — outstanding since subtask 5.
2. User to do a quick manual cold-launch feel-check against the Electron
   build, since the automated one here was inconclusive.
3. Decide whether the DEFERRED items above (command palette, shortcuts
   dialog, Escape-closes-all, `1`/`2` shortcuts, Table filter bar/sort/
   view-settings popover) are worth a follow-up pass or are acceptable
   permanent simplifications for a personal single-user app — this is a
   product decision, not something to resolve unilaterally here.
