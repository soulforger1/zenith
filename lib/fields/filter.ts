import type { IssueRecord } from "@/lib/issue-types";
import { getFieldDef, type FieldDef } from "@/lib/fields/registry";
import type { FilterRule, SortRule } from "@/lib/views/types";

function isEmptyValue(value: unknown): boolean {
  return value === null || value === undefined || value === "" || (Array.isArray(value) && value.length === 0);
}

function matchesRule(issue: IssueRecord, rule: FilterRule, registry: FieldDef[]): boolean {
  const field = getFieldDef(registry, rule.fieldId);
  if (!field) return true;
  const value = field.getValue(issue);

  switch (rule.operator) {
    case "is_empty":
      return isEmptyValue(value);
    case "is_not_empty":
      return !isEmptyValue(value);
    case "is":
      return Array.isArray(value) ? value.includes(rule.value) : value === rule.value;
    case "is_not":
      return Array.isArray(value) ? !value.includes(rule.value) : value !== rule.value;
    case "contains": {
      const needle = String(rule.value ?? "").toLowerCase();
      if (!needle) return true;
      if (Array.isArray(value)) return value.some((v) => String(v).toLowerCase().includes(needle));
      return String(value ?? "").toLowerCase().includes(needle);
    }
    case "before":
      return typeof value === "string" && typeof rule.value === "string" && value < rule.value;
    case "after":
      return typeof value === "string" && typeof rule.value === "string" && value > rule.value;
    default:
      return true;
  }
}

// Generic over T (rather than fixed to IssueRecord) so callers that pass a
// narrower subtype — e.g. the Kanban board's KanbanIssue = IssueRecord &
// { position } — get that subtype back out, not a widened IssueRecord[].
export function applyFilters<T extends IssueRecord>(issues: T[], filters: FilterRule[], registry: FieldDef[]): T[] {
  if (filters.length === 0) return issues;
  return issues.filter((issue) => filters.every((rule) => matchesRule(issue, rule, registry)));
}

/** Free-text keyword search across the title plus any text-type fields —
 * the simplified stand-in for GitHub's typed filter-query syntax. */
export function applyKeyword<T extends IssueRecord>(issues: T[], keyword: string, registry: FieldDef[]): T[] {
  const needle = keyword.trim().toLowerCase();
  if (!needle) return issues;
  const textFields = registry.filter((f) => f.type === "text");
  return issues.filter((issue) => {
    if (issue.title.toLowerCase().includes(needle)) return true;
    return textFields.some((field) => String(field.getValue(issue) ?? "").toLowerCase().includes(needle));
  });
}

/** Single-level sort (the field/direction pair set via the view-settings
 * popover) — multiple simultaneous sort keys aren't supported yet. */
export function applySort<T extends IssueRecord>(issues: T[], sort: SortRule[], registry: FieldDef[]): T[] {
  const rule = sort[0];
  if (!rule) return issues;
  const field = getFieldDef(registry, rule.fieldId);
  if (!field) return issues;

  const sorted = [...issues].sort((a, b) => {
    const av = field.getValue(a);
    const bv = field.getValue(b);
    if (isEmptyValue(av) && isEmptyValue(bv)) return 0;
    if (isEmptyValue(av)) return 1;
    if (isEmptyValue(bv)) return -1;
    if (typeof av === "number" && typeof bv === "number") return av - bv;
    return String(av).localeCompare(String(bv));
  });
  return rule.direction === "desc" ? sorted.reverse() : sorted;
}

export type IssueGroup = { key: string; label: string; color?: string; issues: IssueRecord[] };

/** Buckets issues by a field's option values (built for Board columns and
 * Table/Roadmap grouping alike). Buckets are seeded from the field's defined
 * options first — so empty columns still render — then a trailing "No
 * <field>" bucket catches anything with no value or an unmatched value.
 * Multi-value fields (tags, multi_select) place an issue into every bucket
 * it matches, same as GitHub Projects grouping by a multi-select field. */
export function groupIssuesBy(issues: IssueRecord[], fieldId: string | null, registry: FieldDef[]): IssueGroup[] {
  if (!fieldId) return [{ key: "all", label: "All", issues }];
  const field = getFieldDef(registry, fieldId);
  if (!field) return [{ key: "all", label: "All", issues }];

  const buckets = new Map<string, IssueGroup>();
  for (const opt of field.options) buckets.set(opt.id, { key: opt.id, label: opt.label, color: opt.color, issues: [] });
  const noValue: IssueGroup = { key: "__none__", label: `No ${field.name}`, issues: [] };

  for (const issue of issues) {
    const raw = field.getValue(issue);
    const ids = Array.isArray(raw) ? raw : [raw];
    let placed = false;
    for (const id of ids) {
      const bucket = id ? buckets.get(String(id)) : undefined;
      if (bucket) {
        bucket.issues.push(issue);
        placed = true;
      }
    }
    if (!placed) noValue.issues.push(issue);
  }

  const result = Array.from(buckets.values());
  if (noValue.issues.length > 0 || result.length === 0) result.push(noValue);
  return result;
}
