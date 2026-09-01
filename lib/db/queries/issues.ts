import "server-only";

import { connection } from "next/server";
import { and, asc, desc, eq, ilike, inArray, isNotNull, isNull, lte, max, ne, notInArray, sql } from "drizzle-orm";

import { db } from "@/lib/db";
import { type IssuePriority, type IssueStatus, issueRepos, issues, spaces } from "@/lib/db/schema";
import type { SubtaskCount } from "@/lib/issue-types";
import { positionAtEnd } from "@/lib/position";

/** Repo ids linked to each of `issueIds`, batched into one query — mirrors
 * this file's existing flat-select-plus-Map style (see
 * getMilestoneProgressForSpace) rather than a SQL-side array_agg. */
export async function getRepoIdsByIssueIds(issueIds: string[]): Promise<Map<string, string[]>> {
  const map = new Map<string, string[]>();
  if (issueIds.length === 0) return map;
  const rows = await db
    .select({ issueId: issueRepos.issueId, repoId: issueRepos.repoId })
    .from(issueRepos)
    .where(inArray(issueRepos.issueId, issueIds));
  for (const row of rows) {
    const existing = map.get(row.issueId);
    if (existing) existing.push(row.repoId);
    else map.set(row.issueId, [row.repoId]);
  }
  return map;
}

export async function getIssuesForSpace(spaceId: string) {
  return db
    .select()
    .from(issues)
    .where(eq(issues.spaceId, spaceId))
    .orderBy(asc(issues.status), asc(issues.position), desc(issues.createdAt));
}

export async function getIssuesForMilestone(milestoneId: string) {
  return db
    .select()
    .from(issues)
    .where(eq(issues.milestoneId, milestoneId))
    .orderBy(asc(issues.status), asc(issues.position));
}

export async function getIssueById(id: string) {
  const [issue] = await db.select().from(issues).where(eq(issues.id, id)).limit(1);
  return issue ?? null;
}

export async function createIssue(input: {
  spaceId: string;
  title: string;
  description?: string | null;
  status?: IssueStatus;
  priority?: IssuePriority;
  tags?: string[];
  branch?: string | null;
  estimate?: string | null;
  parentId?: string | null;
  milestoneId?: string | null;
  repoIds?: string[];
  dueDate?: string | null;
  startDate?: string | null;
  customFieldValues?: Record<string, unknown>;
}) {
  const status = input.status ?? "backlog";
  const [{ value: maxPosition }] = await db
    .select({ value: max(issues.position) })
    .from(issues)
    .where(and(eq(issues.spaceId, input.spaceId), eq(issues.status, status)));

  const [issue] = await db
    .insert(issues)
    .values({
      spaceId: input.spaceId,
      title: input.title,
      description: input.description ?? null,
      status,
      isClosed: status === "done",
      closedAt: status === "done" ? new Date() : null,
      priority: input.priority ?? "medium",
      tags: input.tags ?? [],
      branch: input.branch ?? null,
      estimate: input.estimate ?? null,
      parentId: input.parentId ?? null,
      milestoneId: input.milestoneId ?? null,
      dueDate: input.dueDate ?? null,
      startDate: input.startDate ?? null,
      customFieldValues: input.customFieldValues ?? {},
      position: positionAtEnd(maxPosition ?? null),
    })
    .returning();

  if (input.repoIds && input.repoIds.length > 0) {
    await db.insert(issueRepos).values(input.repoIds.map((repoId) => ({ issueId: issue.id, repoId })));
  }
  return issue;
}

/** Bulk "paste a list" flow: creates many backlog issues in a single insert.
 * Positions are assigned sequentially so the list lands in the order it was
 * reviewed in, appended after whatever's already at the end of the backlog. */
export async function createIssues(
  spaceId: string,
  drafts: Array<{
    title: string;
    description?: string | null;
    priority?: IssuePriority;
    tags?: string[];
    branch?: string | null;
    estimate?: string | null;
    parentId?: string | null;
    dueDate?: string | null;
    repoIds?: string[];
    milestoneId?: string | null;
    customFieldValues?: Record<string, unknown>;
  }>,
) {
  if (drafts.length === 0) return [];

  const [{ value: maxPosition }] = await db
    .select({ value: max(issues.position) })
    .from(issues)
    .where(and(eq(issues.spaceId, spaceId), eq(issues.status, "backlog")));

  let position = maxPosition ?? null;
  const rows = drafts.map((draft) => {
    position = positionAtEnd(position);
    return {
      spaceId,
      title: draft.title,
      description: draft.description ?? null,
      status: "backlog" as const,
      isClosed: false,
      priority: draft.priority ?? "medium",
      tags: draft.tags ?? [],
      branch: draft.branch ?? null,
      estimate: draft.estimate ?? null,
      parentId: draft.parentId ?? null,
      dueDate: draft.dueDate ?? null,
      milestoneId: draft.milestoneId ?? null,
      customFieldValues: draft.customFieldValues ?? {},
      position,
    };
  });

  const created = await db.insert(issues).values(rows).returning();

  const repoLinks = created.flatMap((issue, i) =>
    (drafts[i].repoIds ?? []).map((repoId) => ({ issueId: issue.id, repoId })),
  );
  if (repoLinks.length > 0) {
    await db.insert(issueRepos).values(repoLinks);
  }

  return created;
}

export type IssueFieldPatch = Partial<{
  title: string;
  description: string | null;
  status: IssueStatus;
  priority: IssuePriority;
  tags: string[];
  branch: string | null;
  estimate: string | null;
  parentId: string | null;
  milestoneId: string | null;
  repoIds: string[];
  dueDate: string | null;
  startDate: string | null;
  // Only ever set together with a group-field patch, from the Kanban board's
  // onDragEnd (any grouping, not just status) — see updateIssueGroupAction.
  position: number;
  // A *partial* map of custom field id -> value — merged into the existing
  // customFieldValues jsonb (not a full overwrite), since the drawer/table
  // save one custom field at a time.
  customFieldValues: Record<string, unknown>;
}>;

/** Generic per-field autosave used by the task detail drawer. Keeps
 * `isClosed`/`closedAt` in sync whenever `status` is part of the patch —
 * there's no separate close/reopen action, "done" status is the source of
 * truth. `customFieldValues`, if present, is merged into the existing jsonb
 * via Postgres's `||` object-concat operator rather than overwriting it. */
export async function updateIssueFields(id: string, patch: IssueFieldPatch) {
  const { customFieldValues, repoIds, ...rest } = patch;
  const derived =
    patch.status !== undefined
      ? { isClosed: patch.status === "done", closedAt: patch.status === "done" ? new Date() : null }
      : {};

  return db.transaction(async (tx) => {
    const [issue] = await tx
      .update(issues)
      .set({
        ...rest,
        ...derived,
        ...(customFieldValues !== undefined
          ? { customFieldValues: sql`${issues.customFieldValues} || ${JSON.stringify(customFieldValues)}::jsonb` }
          : {}),
        updatedAt: new Date(),
      })
      .where(eq(issues.id, id))
      .returning();

    // Full replace, same spirit as tags/multi_select custom fields — the
    // drawer/board always send the complete desired set, not a diff.
    if (repoIds !== undefined) {
      await tx.delete(issueRepos).where(eq(issueRepos.issueId, id));
      if (repoIds.length > 0) {
        await tx.insert(issueRepos).values(repoIds.map((repoId) => ({ issueId: id, repoId })));
      }
    }

    return issue ?? null;
  });
}

export async function deleteIssue(id: string) {
  await db.delete(issues).where(eq(issues.id, id));
}

/** {total, done} per parent, for every id in `parentIds`, in one query —
 * same batched-flat-select-plus-Map style as getRepoIdsByIssueIds, using
 * `isClosed` for "done" like getMilestoneProgressForSpace does. */
export async function getSubtaskCountsByParentIds(parentIds: string[]): Promise<Map<string, SubtaskCount>> {
  const map = new Map<string, SubtaskCount>();
  if (parentIds.length === 0) return map;
  const rows = await db
    .select({ parentId: issues.parentId, isClosed: issues.isClosed })
    .from(issues)
    .where(inArray(issues.parentId, parentIds));
  for (const row of rows) {
    if (!row.parentId) continue;
    const entry = map.get(row.parentId) ?? { total: 0, done: 0 };
    entry.total += 1;
    if (row.isClosed) entry.done += 1;
    map.set(row.parentId, entry);
  }
  return map;
}

/** A task's immediate children, for rendering the drawer's subtask list. */
export async function getChildIssues(parentId: string) {
  return db
    .select()
    .from(issues)
    .where(eq(issues.parentId, parentId))
    .orderBy(asc(issues.position), asc(issues.createdAt));
}

/** True if setting `candidateParentId` as `taskId`'s parent would create a
 * cycle — i.e. `candidateParentId` is `taskId` itself, or already descends
 * from it. Walks candidateParentId's ancestor chain looking for taskId,
 * capped so a data bug can't spin this into an infinite loop. */
export async function wouldCreateCycle(taskId: string, candidateParentId: string): Promise<boolean> {
  let current: string | null = candidateParentId;
  for (let hops = 0; current !== null && hops < 50; hops++) {
    if (current === taskId) return true;
    const issue = await getIssueById(current);
    current = issue?.parentId ?? null;
  }
  return false;
}

/** Title search within a space, for the "link existing task as subtask"
 * picker — excludes `excludeIds` (the task itself and anything already
 * ruled out by the caller) and caps results for a fast-typing autocomplete. */
export async function searchIssuesForSpace(spaceId: string, query: string, excludeIds: string[] = []) {
  const trimmed = query.trim();
  if (!trimmed) return [];
  return db
    .select({ id: issues.id, title: issues.title })
    .from(issues)
    .where(
      and(
        eq(issues.spaceId, spaceId),
        ilike(issues.title, `%${trimmed}%`),
        excludeIds.length > 0 ? notInArray(issues.id, excludeIds) : undefined,
      ),
    )
    .orderBy(asc(issues.title))
    .limit(20);
}

/** Bulk actions from the list view's selection toolbar — same `isClosed`
 * derivation as the single-row `updateIssueFields`, position left untouched
 * (mirrors how the drawer's own status dropdown behaves; only drag-and-drop
 * repositions). */
export async function bulkUpdateStatus(ids: string[], status: IssueStatus) {
  if (ids.length === 0) return;
  await db
    .update(issues)
    .set({
      status,
      isClosed: status === "done",
      closedAt: status === "done" ? new Date() : null,
      updatedAt: new Date(),
    })
    .where(inArray(issues.id, ids));
}

export async function bulkUpdatePriority(ids: string[], priority: IssuePriority) {
  if (ids.length === 0) return;
  await db.update(issues).set({ priority, updatedAt: new Date() }).where(inArray(issues.id, ids));
}

export async function bulkDeleteIssues(ids: string[]) {
  if (ids.length === 0) return;
  await db.delete(issues).where(inArray(issues.id, ids));
}

/** Highest `position` per status column in a space (used when creating issues). */
export async function getMaxPositionsForSpace(spaceId: string) {
  const rows = await db
    .select({ status: issues.status, value: max(issues.position) })
    .from(issues)
    .where(eq(issues.spaceId, spaceId))
    .groupBy(issues.status);
  const map = new Map<string, number | null>();
  for (const row of rows) map.set(row.status, row.value ?? null);
  return map;
}

/** Progress counts for every milestone in a space, in one query. */
export async function getMilestoneProgressForSpace(spaceId: string) {
  const rows = await db
    .select({
      milestoneId: issues.milestoneId,
      isClosed: issues.isClosed,
    })
    .from(issues)
    .where(and(eq(issues.spaceId, spaceId)));

  const progress = new Map<string, { total: number; closed: number }>();
  for (const row of rows) {
    if (!row.milestoneId) continue;
    const entry = progress.get(row.milestoneId) ?? { total: 0, closed: 0 };
    entry.total += 1;
    if (row.isClosed) entry.closed += 1;
    progress.set(row.milestoneId, entry);
  }
  return progress;
}

/** Open/total issue counts for every space, in one query (for the spaces list). */
export async function getIssueCountsBySpace() {
  const rows = await db.select({ spaceId: issues.spaceId, isClosed: issues.isClosed }).from(issues);
  const counts = new Map<string, { total: number; open: number }>();
  for (const row of rows) {
    const entry = counts.get(row.spaceId) ?? { total: 0, open: 0 };
    entry.total += 1;
    if (!row.isClosed) entry.open += 1;
    counts.set(row.spaceId, entry);
  }
  return counts;
}

export async function getUnassignedIssueCount(spaceId: string) {
  const rows = await db
    .select({ id: issues.id })
    .from(issues)
    .where(and(eq(issues.spaceId, spaceId), isNull(issues.milestoneId)));
  return rows.length;
}

/** Cross-space "due soon" feed for the /spaces home page's "This week"
 * widget — overdue tasks and tasks due within `daysAhead`, done tasks
 * excluded. Not a scheduled digest (no email/cron infra in this app), just
 * computed fresh on page load. */
export async function getUpcomingIssues(daysAhead: number) {
  // "Today" changes on every request, so this can't be prerendered/cached —
  // connection() marks the render as request-time-only rather than letting
  // Cache Components error on the unstable `new Date()` value.
  await connection();
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() + daysAhead);
  const cutoffDate = cutoff.toISOString().slice(0, 10);

  return db
    .select({
      id: issues.id,
      title: issues.title,
      priority: issues.priority,
      status: issues.status,
      dueDate: issues.dueDate,
      spaceName: spaces.name,
      spaceSlug: spaces.slug,
    })
    .from(issues)
    .innerJoin(spaces, eq(issues.spaceId, spaces.id))
    .where(and(isNotNull(issues.dueDate), lte(issues.dueDate, cutoffDate), ne(issues.status, "done")))
    .orderBy(asc(issues.dueDate))
    .limit(20);
}
