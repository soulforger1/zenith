# Sync

Zenith is local-first: the SQLite database at
`~/Library/Application Support/Zenith/zenith.sqlite` is the single source
of truth, and the app is fully usable offline. Sync to a remote Postgres
database is optional, off by default, and periodic — turn it on in
**Settings → Sync** (⌘,). A synced-folder (iCloud Drive) target is planned
but not implemented yet; only Postgres exists today.

## Model

- **Conflict resolution is last-write-wins by `updated_at`.** No CRDTs, no
  merge UI. If the same field is edited on two Macs before they sync with
  each other, whichever edit has the later `updated_at` wins outright — the
  other edit is silently discarded. Acceptable for a personal, single-user,
  small-number-of-devices app; not appropriate for anything with real
  concurrent multi-user editing.
- **Deletes are tracked with tombstones**, not a `deleted_at` column on
  each table — see `sync_tombstones` in
  `Packages/ZenithData/Sources/ZenithData/Database/Schema/Migrations.swift`
  (local) and `db/schema.ts` (remote). A plain `DELETE` leaves no trace for
  another device to notice on its next pull; the tombstone is what
  propagates the delete. Every local delete gets one automatically via an
  `AFTER DELETE` trigger on every synced table (including cascaded
  deletes — deleting a space tombstones its issues, views, etc. too).
- **No dirty flag.** Every mutation already stamps `updated_at` (see
  `Packages/ZenithData/Sources/ZenithData/Queries/*.swift`), so `updated_at
  > <cursor>` *is* the change log. This is an invariant the sync layer
  depends on — any new mutation added to `Queries/` must keep bumping
  `updated_at`, including a patch that only touches a join-table
  relationship (e.g. `IssueQueries.updateIssueFields` with only `repoIds`
  set still bumps the issue's `updated_at`).
- **Per-target cursors**, not one global cursor — the local `sync_state`
  table has one row per target (`target = "postgres"`, eventually
  `"icloud"`), each with its own `last_pulled_at` / `last_pushed_at`. Two
  targets sync independently; disabling one doesn't affect the other's
  cursor.

## One round of sync (`ZenithSync.SyncReconciler.runRound`)

1. **Pull**: fetch every row/tombstone the target has newer than
   `sync_state.last_pulled_at`, then apply each locally
   (`ZenithData.LocalSyncStore.applyUpsert`/`applyDelete`) — an upsert only
   overwrites the local row if the incoming `updated_at` is strictly newer
   (enforced by a conditional `ON CONFLICT ... WHERE excluded.updated_at >
   ...`, so this can never error, only no-op), and never resurrects a row
   that was deleted locally *after* the incoming row's `updated_at`.
2. **Push**: read every local row/tombstone changed since
   `sync_state.last_pushed_at` (`LocalSyncStore.localDelta`) and send it to
   the target. `PostgresSyncTarget` applies the same guard server-side (a
   conditional `ON CONFLICT` there too, plus a tombstone check before every
   upsert), so pushing from two Macs at once still converges.
3. **Advance cursors** to the round's start time (not completion time) —
   anything written during the round is simply re-processed, harmlessly,
   next round.

A round that throws (network down, bad credentials) records the error in
`sync_state.last_error` and does **not** advance the cursors, so the next
successful round picks up from where the last successful one left off —
nothing is skipped.

`SyncCoordinator` (`Zenith/Sync/SyncCoordinator.swift`) drives this on an
interval (Settings → Sync's picker, default 15 minutes), on app foreground
(debounced to once a minute), and on a manual "Sync Now". After a round
that pulled anything, it bumps `DataChangeBroadcaster.revision`, which
`ContentView` observes to reload the currently-open spaces — the same
"reload after a change" idiom the rest of the app already uses for local
edits, not a fully reactive per-row pipeline.

## Postgres target

Requires the `sync_tombstones` table and `issue_repos`/`space_images`
`updated_at` columns, which the app's own tables don't need but the remote
schema does (added in `db/migrations/0007_lyrical_proemial_gods.sql`).
**Apply this migration by hand before turning Postgres sync on** — the app
doesn't run it for you:

```sh
psql "$DIRECT_URL" -f db/migrations/0007_lyrical_proemial_gods.sql
```

Type conversion between SQLite's TEXT/INTEGER/REAL and Postgres's typed
columns (`uuid`, `boolean`, `date`, `timestamptz`, `jsonb`, `text[]`) is
handled generically by column name in
`Packages/ZenithSync/Sources/ZenithSync/Postgres/PostgresColumnCatalog.swift`
— every column name is unique across all 8 tables, so one lookup covers the
whole schema. Adding a synced column means adding it to that catalog (and
to `ZenithData.SyncTable`/the local migration/`db/schema.ts`) — nothing
else needs to change.

**A manual `psql DELETE` does not propagate.** Deleting a row directly in
Postgres (outside the app) doesn't write a tombstone, so other devices
never learn about it — they'll just re-push their copy back on the next
sync. Delete through the app (any device) if you want the delete to sync.

## Clock skew

Last-write-wins compares `updated_at` timestamps from whichever Mac made
each edit — there's no server-assigned "true" timestamp. Two Macs with
clocks more than a few seconds apart can resolve a genuinely-concurrent
edit "backwards" (the earlier edit, by wall-clock, wins even though a user
made it second). This is inherent to the LWW model and not something the
sync layer tries to compensate for — keep your Macs' clocks in sync
(automatic date & time is on by default) rather than expecting the app to
work around a wrong one.

## Resetting a target

To force a full resync (e.g. after manually fixing up data on one side),
delete that target's cursor row so the next round treats it as if it's
never synced before — a full pull, plus a full push of everything with
`updated_at` after the epoch:

```sh
sqlite3 ~/Library/Application\ Support/Zenith/zenith.sqlite \
  "DELETE FROM sync_state WHERE target = 'postgres';"
```

This doesn't delete any data, local or remote — it only resets the
bookkeeping, so the next round re-evaluates every row's last-write-wins
comparison from scratch (a no-op for rows that already agree).

## What's not built yet

- **iCloud / synced-folder target** — planned as a synced folder (default:
  iCloud Drive) holding one JSON file per row + tombstone markers, LWW by
  file content, no CloudKit/entitlements/Developer-account requirement.
  Not implemented; `Settings → Sync` has no iCloud toggle yet.
- **Settings validation UX polish** — e.g. warning before importing into a
  non-empty local store, disabling the interval picker while syncing.
