"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import {
  bulkDeleteIssues,
  bulkUpdatePriority,
  bulkUpdateStatus,
  createIssue,
  createIssues,
  deleteIssue,
  getChildIssues,
  getIssueById,
  getRepoIdsByIssueIds,
  getSubtaskCountsByParentIds,
  searchIssuesForSpace,
  updateIssueFields,
  wouldCreateCycle,
  type IssueFieldPatch,
} from "@/lib/db/queries/issues";
import { issuePriorityValues, issueStatusValues, type IssuePriority, type IssueStatus } from "@/lib/db/schema";
import { toIssueRecord, toIssueRecords, type IssueRecord } from "@/lib/issue-types";

const customFieldValuesSchema = z.record(z.string(), z.unknown());

const draftSchema = z.object({
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(2000).optional(),
  priority: z.enum(issuePriorityValues),
  tags: z.array(z.string().trim().min(1).max(30)).max(8),
  branch: z.string().trim().max(100).optional(),
  estimate: z.string().trim().max(20).optional(),
  dueDate: z.string().optional(),
  startDate: z.string().optional(),
  repoIds: z.array(z.string().uuid()).max(20).optional(),
  milestoneId: z.string().uuid().optional(),
  customFieldValues: customFieldValuesSchema.optional(),
});
const draftsSchema = z.array(draftSchema).min(1).max(50);

const fieldPatchSchema = z
  .object({
    title: z.string().trim().min(1).max(200),
    description: z.string().trim().max(5000).nullable(),
    status: z.enum(issueStatusValues),
    priority: z.enum(issuePriorityValues),
    tags: z.array(z.string().trim().min(1).max(30)).max(8),
    branch: z.string().trim().max(100).nullable(),
    estimate: z.string().trim().max(20).nullable(),
    parentId: z.string().uuid().nullable(),
    milestoneId: z.string().uuid().nullable(),
    repoIds: z.array(z.string().uuid()).max(20),
    dueDate: z.string().nullable(),
    startDate: z.string().nullable(),
    position: z.number(),
    customFieldValues: customFieldValuesSchema,
  })
  .partial();

/** Quick-add: create a task with just a title in a given column. */
export async function createIssueAction(
  spaceId: string,
  spaceSlug: string,
  status: string,
  title: string,
): Promise<void> {
  const cleanTitle = title.trim();
  if (!cleanTitle) return;
  if (!(issueStatusValues as readonly string[]).includes(status)) {
    throw new Error(`Invalid issue status: ${status}`);
  }
  await createIssue({ spaceId, title: cleanTitle, status: status as IssueStatus });
  revalidatePath(`/spaces/${spaceSlug}`);
}

/** Full task creation (used by the AI paste-and-parse modal). */
export async function createIssueFromDraftAction(
  spaceId: string,
  spaceSlug: string,
  draft: {
    title: string;
    description?: string;
    priority: "low" | "medium" | "high";
    tags: string[];
    branch?: string;
    estimate?: string;
    dueDate?: string;
    startDate?: string;
    repoIds?: string[];
    milestoneId?: string;
    customFieldValues?: Record<string, unknown>;
  },
): Promise<void> {
  await createIssue({
    spaceId,
    title: draft.title,
    description: draft.description || null,
    priority: draft.priority,
    tags: draft.tags,
    branch: draft.branch || null,
    estimate: draft.estimate || null,
    dueDate: draft.dueDate || null,
    startDate: draft.startDate || null,
    repoIds: draft.repoIds ?? [],
    milestoneId: draft.milestoneId || null,
    customFieldValues: draft.customFieldValues,
    status: "backlog",
  });
  revalidatePath(`/spaces/${spaceSlug}`);
}

/** Bulk task creation (used by the AI paste-a-list modal). */
export async function createIssuesFromDraftsAction(
  spaceId: string,
  spaceSlug: string,
  drafts: Array<{
    title: string;
    description?: string;
    priority: "low" | "medium" | "high";
    tags: string[];
    branch?: string;
    estimate?: string;
    dueDate?: string;
    startDate?: string;
    repoIds?: string[];
    milestoneId?: string;
    customFieldValues?: Record<string, unknown>;
  }>,
): Promise<void> {
  const parsed = draftsSchema.parse(drafts);
  await createIssues(
    spaceId,
    parsed.map((draft) => ({
      title: draft.title,
      description: draft.description || null,
      priority: draft.priority,
      tags: draft.tags,
      branch: draft.branch || null,
      estimate: draft.estimate || null,
      dueDate: draft.dueDate || null,
      repoIds: draft.repoIds ?? [],
      milestoneId: draft.milestoneId || null,
      customFieldValues: draft.customFieldValues,
    })),
  );
  revalidatePath(`/spaces/${spaceSlug}`);
}

/** Per-field autosave from the task detail drawer — pass only what changed. */
export async function updateIssueFieldsAction(
  id: string,
  spaceSlug: string,
  patch: IssueFieldPatch,
): Promise<void> {
  const parsed = fieldPatchSchema.parse(patch);
  await updateIssueFields(id, parsed);
  revalidatePath(`/spaces/${spaceSlug}`);
}

export async function deleteIssueAction(id: string, spaceSlug: string): Promise<void> {
  await deleteIssue(id);
  revalidatePath(`/spaces/${spaceSlug}`);
}

/** Called directly (not via a <form>) from the Kanban board's onDragEnd —
 * `patch` is whatever field the board is currently grouped by (status,
 * priority, milestoneId, repoIds, or a customFieldValues entry), built by
 * lib/fields/registry.ts's buildFieldPatch, always paired with the dragged
 * card's new fractional position. */
export async function updateIssueGroupAction(
  id: string,
  spaceSlug: string,
  patch: Record<string, unknown>,
  position: number,
): Promise<void> {
  const parsed = fieldPatchSchema.parse({ ...patch, position });
  await updateIssueFields(id, parsed);
  revalidatePath(`/spaces/${spaceSlug}`);
}

/** Bulk actions from the list view's selection toolbar. */
export async function bulkUpdateIssuesStatusAction(
  ids: string[],
  spaceSlug: string,
  status: string,
): Promise<void> {
  if (!(issueStatusValues as readonly string[]).includes(status)) {
    throw new Error(`Invalid issue status: ${status}`);
  }
  await bulkUpdateStatus(ids, status as IssueStatus);
  revalidatePath(`/spaces/${spaceSlug}`);
}

export async function bulkUpdateIssuesPriorityAction(
  ids: string[],
  spaceSlug: string,
  priority: string,
): Promise<void> {
  if (!(issuePriorityValues as readonly string[]).includes(priority)) {
    throw new Error(`Invalid issue priority: ${priority}`);
  }
  await bulkUpdatePriority(ids, priority as IssuePriority);
  revalidatePath(`/spaces/${spaceSlug}`);
}

export async function bulkDeleteIssuesAction(ids: string[], spaceSlug: string): Promise<void> {
  await bulkDeleteIssues(ids);
  revalidatePath(`/spaces/${spaceSlug}`);
}

/** Builds a full IssueRecord for one issue — used wherever the drawer needs
 * a task it wasn't handed as a prop (a parent breadcrumb, a freshly-created
 * or freshly-linked child). */
async function buildIssueRecord(id: string): Promise<IssueRecord | null> {
  const issue = await getIssueById(id);
  if (!issue) return null;
  const [repoIdsByIssue, subtaskCountByIssue] = await Promise.all([
    getRepoIdsByIssueIds([id]),
    getSubtaskCountsByParentIds([id]),
  ]);
  return toIssueRecord(issue, repoIdsByIssue.get(id) ?? [], subtaskCountByIssue.get(id) ?? { total: 0, done: 0 });
}

/** Read wrappers the task detail drawer calls on open — kept off the initial
 * page load's query set (see views/[viewId]/page.tsx) since a task's parent
 * and children are only needed once its drawer is actually open. */
export async function getIssueRecordAction(id: string): Promise<IssueRecord | null> {
  return buildIssueRecord(id);
}

export async function getChildIssuesAction(parentId: string): Promise<IssueRecord[]> {
  const children = await getChildIssues(parentId);
  const [repoIdsByIssue, subtaskCountByIssue] = await Promise.all([
    getRepoIdsByIssueIds(children.map((c) => c.id)),
    getSubtaskCountsByParentIds(children.map((c) => c.id)),
  ]);
  return toIssueRecords(children, repoIdsByIssue, subtaskCountByIssue);
}

/** Quick-add a subtask from the drawer — looks up the parent to inherit its
 * `spaceId` so the drawer doesn't need to carry that around separately. */
export async function createSubtaskAction(
  parentId: string,
  spaceSlug: string,
  title: string,
): Promise<IssueRecord | null> {
  const cleanTitle = title.trim();
  if (!cleanTitle) return null;
  const parent = await getIssueById(parentId);
  if (!parent) throw new Error("Parent task not found.");
  const created = await createIssue({ spaceId: parent.spaceId, title: cleanTitle, parentId });
  revalidatePath(`/spaces/${spaceSlug}`);
  return toIssueRecord(created, [], { total: 0, done: 0 });
}

/** Bulk variant for the "Generate ✦" AI flow — same parent-id lookup as
 * createSubtaskAction, one insert for every generated title. */
export async function createSubtasksFromTitlesAction(
  parentId: string,
  spaceSlug: string,
  titles: string[],
): Promise<IssueRecord[]> {
  const cleanTitles = titles.map((t) => t.trim()).filter(Boolean);
  if (cleanTitles.length === 0) return [];
  const parent = await getIssueById(parentId);
  if (!parent) throw new Error("Parent task not found.");
  const created = await createIssues(
    parent.spaceId,
    cleanTitles.map((title) => ({ title, parentId })),
  );
  revalidatePath(`/spaces/${spaceSlug}`);
  return toIssueRecords(created);
}

/** Links/unlinks a task to a parent — `parentId: null` promotes it back to
 * a standalone task. Guarded against creating a cycle (a task can't become
 * an ancestor of its own ancestor). */
export async function setParentAction(id: string, spaceSlug: string, parentId: string | null): Promise<void> {
  if (parentId !== null) {
    if (parentId === id) throw new Error("A task can't be its own subtask.");
    if (await wouldCreateCycle(id, parentId)) {
      throw new Error("That would create a loop of subtasks.");
    }
  }
  await updateIssueFields(id, { parentId });
  revalidatePath(`/spaces/${spaceSlug}`);
}

/** Live search backing the drawer's "Link existing…" picker — derives
 * `spaceId` from the task being edited so callers only need to pass ids. */
export async function searchIssuesForSubtaskAction(
  taskId: string,
  query: string,
): Promise<{ id: string; title: string }[]> {
  const task = await getIssueById(taskId);
  if (!task) return [];
  return searchIssuesForSpace(task.spaceId, query, [taskId]);
}
