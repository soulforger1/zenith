import type { IssuePriority, IssueStatus, issues } from "@/lib/db/schema";

export type SubtaskCount = { total: number; done: number };

/** The subset of an issue's fields the UI (list rows, kanban cards, the
 * task detail drawer) actually needs — narrows Drizzle's `text` columns
 * (plain `string`) down to their real union types. */
export type IssueRecord = {
  id: string;
  title: string;
  description: string | null;
  status: IssueStatus;
  priority: IssuePriority;
  tags: string[];
  branch: string | null;
  estimate: string | null;
  parentId: string | null;
  subtaskCount: SubtaskCount;
  dueDate: string | null;
  startDate: string | null;
  milestoneId: string | null;
  repoIds: string[];
  customFieldValues: Record<string, unknown>;
};

type IssueRow = typeof issues.$inferSelect;

/** `repoIds` isn't a column on the issue row anymore (many-to-many via
 * issue_repos) and `subtaskCount` isn't a column at all (derived from child
 * rows) — the caller must fetch these separately (see getRepoIdsByIssueIds
 * and getSubtaskCountsByParentIds) and pass them in here. */
export function toIssueRecord(row: IssueRow, repoIds: string[] = [], subtaskCount: SubtaskCount = { total: 0, done: 0 }): IssueRecord {
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    status: row.status as IssueStatus,
    priority: row.priority as IssuePriority,
    tags: row.tags,
    branch: row.branch,
    estimate: row.estimate,
    parentId: row.parentId,
    subtaskCount,
    dueDate: row.dueDate,
    startDate: row.startDate,
    milestoneId: row.milestoneId,
    repoIds,
    customFieldValues: row.customFieldValues,
  };
}

export function toIssueRecords(
  rows: IssueRow[],
  repoIdsByIssue: Map<string, string[]> = new Map(),
  subtaskCountByIssue: Map<string, SubtaskCount> = new Map(),
): IssueRecord[] {
  return rows.map((row) =>
    toIssueRecord(row, repoIdsByIssue.get(row.id) ?? [], subtaskCountByIssue.get(row.id) ?? { total: 0, done: 0 }),
  );
}
