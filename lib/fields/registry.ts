// The single abstraction every view (Table/Board/Roadmap), the filter bar,
// and the view-settings popover build on — treats built-in issue columns
// (status, priority, tags, milestone, repo, due date, start date) and
// user-defined custom fields identically, so nothing else in the app needs
// to special-case "is this a built-in or a custom field?".
import {
  issuePriorityValues,
  issueStatusValues,
  type CustomFieldType,
  type FieldOption,
  type IterationOption,
} from "@/lib/db/schema";
import { PRIORITY_LABEL } from "@/lib/priority";
import type { IssueRecord } from "@/lib/issue-types";

export type FieldType = CustomFieldType; // "text" | "number" | "date" | "single_select" | "multi_select" | "iteration"

/** Options normalized to one shape regardless of whether they came from a
 * FieldOption (select types) or IterationOption (iteration type) row —
 * `startDate`/`durationDays` are only populated for iteration options. */
export type NormalizedOption = {
  id: string;
  label: string;
  color?: string;
  startDate?: string;
  durationDays?: number;
};

export type FieldDef = {
  id: string;
  name: string;
  type: FieldType;
  isBuiltIn: boolean;
  options: NormalizedOption[];
  getValue: (issue: IssueRecord) => unknown;
};

export type CustomFieldRow = {
  id: string;
  key: string;
  name: string;
  type: string;
  options: FieldOption[] | IterationOption[];
};

const STATUS_LABEL: Record<string, string> = {
  backlog: "Backlog",
  todo: "Todo",
  in_progress: "In Progress",
  done: "Done",
};
const STATUS_COLOR: Record<string, string> = {
  backlog: "gray",
  todo: "blue",
  in_progress: "yellow",
  done: "green",
};
const PRIORITY_COLOR: Record<string, string> = { low: "blue", medium: "yellow", high: "red" };

export function normalizeOptions(options: FieldOption[] | IterationOption[]): NormalizedOption[] {
  return options.map((opt) =>
    "title" in opt
      ? { id: opt.id, label: opt.title, color: "purple", startDate: opt.startDate, durationDays: opt.durationDays }
      : { id: opt.id, label: opt.name, color: opt.color },
  );
}

/** Builds the full field list for a space: the 7 built-in columns plus one
 * FieldDef per custom field. `milestones`/`repos` are needed to give the
 * milestone/repo built-ins their option lists (they aren't custom fields,
 * but behave like a single_select for filtering/grouping/display purposes). */
export function buildFieldRegistry(
  customFieldRows: CustomFieldRow[],
  context: { milestones: { id: string; title: string }[]; repos: { id: string; name: string }[] },
): FieldDef[] {
  const builtIns: FieldDef[] = [
    {
      id: "status",
      name: "Status",
      type: "single_select",
      isBuiltIn: true,
      options: issueStatusValues.map((s) => ({ id: s, label: STATUS_LABEL[s], color: STATUS_COLOR[s] })),
      getValue: (issue) => issue.status,
    },
    {
      id: "priority",
      name: "Priority",
      type: "single_select",
      isBuiltIn: true,
      options: issuePriorityValues.map((p) => ({ id: p, label: PRIORITY_LABEL[p], color: PRIORITY_COLOR[p] })),
      getValue: (issue) => issue.priority,
    },
    {
      id: "tags",
      name: "Tags",
      type: "multi_select",
      isBuiltIn: true,
      options: [],
      getValue: (issue) => issue.tags,
    },
    {
      // id matches IssueRecord's `milestoneId` (not just "milestone") so
      // `buildFieldPatch` below can key straight into IssueFieldPatch without
      // a separate id->property lookup table.
      id: "milestoneId",
      name: "Milestone",
      type: "single_select",
      isBuiltIn: true,
      options: context.milestones.map((m) => ({ id: m.id, label: m.title, color: "gray" })),
      getValue: (issue) => issue.milestoneId,
    },
    {
      id: "repoIds",
      name: "Repo",
      type: "multi_select",
      isBuiltIn: true,
      options: context.repos.map((r) => ({ id: r.id, label: r.name, color: "gray" })),
      getValue: (issue) => issue.repoIds,
    },
    { id: "dueDate", name: "Due date", type: "date", isBuiltIn: true, options: [], getValue: (issue) => issue.dueDate },
    {
      id: "startDate",
      name: "Start date",
      type: "date",
      isBuiltIn: true,
      options: [],
      getValue: (issue) => issue.startDate,
    },
    { id: "branch", name: "Branch", type: "text", isBuiltIn: true, options: [], getValue: (issue) => issue.branch },
    {
      id: "estimate",
      name: "Estimate",
      type: "text",
      isBuiltIn: true,
      options: [],
      getValue: (issue) => issue.estimate,
    },
  ];

  const custom: FieldDef[] = customFieldRows.map((field) => ({
    id: field.id,
    name: field.name,
    type: field.type as CustomFieldType,
    isBuiltIn: false,
    options: normalizeOptions(field.options),
    getValue: (issue) => issue.customFieldValues[field.id],
  }));

  return [...builtIns, ...custom];
}

export function getFieldDef(registry: FieldDef[], fieldId: string): FieldDef | undefined {
  return registry.find((f) => f.id === fieldId);
}

/** Builds an `updateIssueFieldsAction` patch for setting `value` on `field` —
 * built-in fields patch their own column directly, custom fields patch
 * through the `customFieldValues` merge-patch key. */
export function buildFieldPatch(field: FieldDef, value: unknown): Record<string, unknown> {
  if (field.isBuiltIn) return { [field.id]: value };
  return { customFieldValues: { [field.id]: value } };
}
