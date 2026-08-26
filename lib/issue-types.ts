import type { IssuePriority, IssueStatus, Subtask, issues } from "@/lib/db/schema";

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
  subtasks: Subtask[];
  dueDate: string | null;
  startDate: string | null;
  milestoneId: string | null;
  repoIds: string[];
  customFieldValues: Record<string, unknown>;
};

type IssueRow = typeof issues.$inferSelect;

/** `repoIds` isn't a column on the issue row anymore (many-to-many via
 * issue_repos) — the caller must fetch it separately (see
 * getRepoIdsByIssueIds) and pass it in here. */
export function toIssueRecord(row: IssueRow, repoIds: string[] = []): IssueRecord {
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    status: row.status as IssueStatus,
    priority: row.priority as IssuePriority,
    tags: row.tags,
    branch: row.branch,
    estimate: row.estimate,
    subtasks: row.subtasks,
    dueDate: row.dueDate,
    startDate: row.startDate,
    milestoneId: row.milestoneId,
    repoIds,
    customFieldValues: row.customFieldValues,
  };
}

export function toIssueRecords(rows: IssueRow[], repoIdsByIssue: Map<string, string[]> = new Map()): IssueRecord[] {
  return rows.map((row) => toIssueRecord(row, repoIdsByIssue.get(row.id) ?? []));
}
