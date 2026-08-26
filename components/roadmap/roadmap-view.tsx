"use client";

import { useMemo, useState, useTransition } from "react";
import { toast } from "sonner";

import { addDaysISO, daysBetweenISO, todayISO } from "@/lib/date";
import { cn } from "@/lib/utils";
import { updateViewConfigAction } from "@/lib/actions/views";
import { applyFilters, applyKeyword, groupIssuesBy } from "@/lib/fields/filter";
import { buildFieldRegistry, getFieldDef, type CustomFieldRow, type FieldDef } from "@/lib/fields/registry";
import type { RoadmapViewConfig } from "@/lib/views/types";
import type { IssueRecord } from "@/lib/issue-types";
import { useAppShell } from "@/components/layout/app-shell-context";
import { FieldFormDialog } from "@/components/fields/field-form-dialog";
import { ViewFilterBar } from "@/components/views/view-filter-bar";
import { ViewSettingsPopover } from "@/components/views/view-settings-popover";
import { PRIORITY_DOT_CLASS } from "@/lib/priority";

const ROW_HEIGHT = 36;
const DAY_WIDTH: Record<RoadmapViewConfig["zoom"], number> = { week: 32, month: 12, quarter: 5 };
const PAD_DAYS = 4;

function resolveDate(field: FieldDef, issue: IssueRecord): string | null {
  const raw = field.getValue(issue);
  if (field.type === "date") return typeof raw === "string" ? raw : null;
  if (field.type === "iteration") {
    const opt = field.options.find((o) => o.id === raw);
    return opt?.startDate ?? null;
  }
  return null;
}

function resolveRange(startField: FieldDef, endField: FieldDef, issue: IssueRecord): [string, string] | null {
  if (startField.id === endField.id && startField.type === "iteration") {
    const raw = startField.getValue(issue);
    const opt = startField.options.find((o) => o.id === raw);
    if (!opt?.startDate || opt.durationDays == null) return null;
    return [opt.startDate, addDaysISO(opt.startDate, opt.durationDays)];
  }
  const start = resolveDate(startField, issue);
  const end = resolveDate(endField, issue);
  if (!start && !end) return null;
  const s = start ?? end!;
  const e = end ?? start!;
  return s <= e ? [s, e] : [e, s];
}

export function RoadmapView({
  view,
  issues,
  spaceId,
  spaceSlug,
  customFields,
  milestones,
  repos,
}: {
  view: { id: string; config: RoadmapViewConfig };
  issues: IssueRecord[];
  spaceId: string;
  spaceSlug: string;
  customFields: CustomFieldRow[];
  milestones: { id: string; title: string }[];
  repos: { id: string; name: string }[];
}) {
  const { openTask } = useAppShell();
  // Built client-side — FieldDef.getValue is a function, which can't cross
  // the RSC serialization boundary from the server component page.
  const registry = useMemo(() => buildFieldRegistry(customFields, { milestones, repos }), [customFields, milestones, repos]);
  const [config, setConfig] = useState(view.config);
  const [keyword, setKeyword] = useState("");
  const [, startTransition] = useTransition();

  function persistConfig(next: RoadmapViewConfig) {
    setConfig(next);
    startTransition(() => {
      updateViewConfigAction(view.id, spaceSlug, next).catch(() => toast.error("Couldn't save view settings."));
    });
  }

  const hasDateOrIterationField = registry.some((f) => f.type === "date" || f.type === "iteration");
  const startField = config.startFieldId ? getFieldDef(registry, config.startFieldId) : undefined;
  const endField = config.endFieldId ? getFieldDef(registry, config.endFieldId) : undefined;

  const filtered = useMemo(() => {
    let result = applyKeyword(issues, keyword, registry);
    result = applyFilters(result, config.filters, registry);
    return result;
  }, [issues, keyword, config.filters, registry]);

  const ranged = useMemo(() => {
    if (!startField || !endField) return [];
    return filtered
      .map((issue) => {
        const range = resolveRange(startField, endField, issue);
        return range ? { issue, start: range[0], end: range[1] } : null;
      })
      .filter((r): r is { issue: IssueRecord; start: string; end: string } => r !== null);
  }, [filtered, startField, endField]);

  const groups = useMemo(() => {
    const rangedIssues = ranged.map((r) => r.issue);
    return groupIssuesBy(rangedIssues, config.groupByFieldId, registry).map((g) => ({
      ...g,
      rows: g.issues.map((issue) => ranged.find((r) => r.issue.id === issue.id)!),
    }));
  }, [ranged, config.groupByFieldId, registry]);

  const dayWidth = DAY_WIDTH[config.zoom];

  const { rangeStart, rangeEnd, months } = useMemo(() => {
    if (ranged.length === 0) {
      const today = todayISO();
      return { rangeStart: addDaysISO(today, -PAD_DAYS), rangeEnd: addDaysISO(today, 30), months: [] as { label: string; days: number }[] };
    }
    let min = ranged[0].start;
    let max = ranged[0].end;
    for (const r of ranged) {
      if (r.start < min) min = r.start;
      if (r.end > max) max = r.end;
    }
    const start = addDaysISO(min, -PAD_DAYS);
    const end = addDaysISO(max, PAD_DAYS);
    const totalDays = daysBetweenISO(start, end);

    const monthBuckets: { label: string; days: number }[] = [];
    let cursor = start;
    let remaining = totalDays;
    while (remaining > 0) {
      const date = new Date(cursor);
      const label = date.toLocaleDateString("en-US", { month: "short", year: "numeric" });
      const daysLeftInMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate() - date.getDate() + 1;
      const daysHere = Math.min(daysLeftInMonth, remaining);
      monthBuckets.push({ label, days: daysHere });
      cursor = addDaysISO(cursor, daysHere);
      remaining -= daysHere;
    }
    return { rangeStart: start, rangeEnd: end, months: monthBuckets };
  }, [ranged]);

  const timelineWidth = daysBetweenISO(rangeStart, rangeEnd) * dayWidth;
  const todayOffset = daysBetweenISO(rangeStart, todayISO()) * dayWidth;

  if (!hasDateOrIterationField) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed p-16 text-center">
        <p className="text-base font-semibold">Welcome to Roadmap!</p>
        <p className="max-w-sm text-sm text-muted-foreground">
          Your space needs at least one date or iteration field to get started.
        </p>
        <FieldFormDialog spaceId={spaceId} spaceSlug={spaceSlug} mode="create" />
      </div>
    );
  }

  if (!startField || !endField) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed p-16 text-center">
        <p className="text-base font-semibold">Pick date fields for this view</p>
        <p className="max-w-sm text-sm text-muted-foreground">
          Choose a start and end field (date or iteration) in View settings to start plotting tasks.
        </p>
        <ViewSettingsPopover viewType="roadmap" registry={registry} config={config} onChange={(c) => persistConfig(c as RoadmapViewConfig)} />
      </div>
    );
  }

  return (
    <div className="space-y-2.5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <ViewFilterBar
          registry={registry}
          filters={config.filters}
          onFiltersChange={(filters) => persistConfig({ ...config, filters })}
          keyword={keyword}
          onKeywordChange={setKeyword}
        />
        <ViewSettingsPopover
          viewType="roadmap"
          registry={registry}
          config={config}
          onChange={(c) => persistConfig(c as RoadmapViewConfig)}
        />
      </div>

      {ranged.length === 0 ? (
        <p className="rounded-lg border border-dashed p-10 text-center text-sm text-muted-foreground">
          No tasks have both a {startField.name} and {endField.name} set yet.
        </p>
      ) : (
        <div className="flex overflow-hidden rounded-lg border">
          <div className="w-[220px] shrink-0 border-r">
            <div className="border-b bg-muted/60 px-3 font-mono text-[11px] font-semibold text-muted-foreground" style={{ height: ROW_HEIGHT * 2 }} />
            {groups.map((group) => (
              <div key={group.key}>
                {config.groupByFieldId ? (
                  <div
                    className="flex items-center border-b bg-muted/30 px-3 text-[11px] font-semibold text-muted-foreground"
                    style={{ height: ROW_HEIGHT }}
                  >
                    {group.label}
                  </div>
                ) : null}
                {group.rows.map(({ issue }) => (
                  <div
                    key={issue.id}
                    onClick={() => openTask(issue, { spaceSlug, milestones, repos, registry })}
                    className="flex cursor-pointer items-center gap-1.5 truncate border-b px-3 text-[12.5px] hover:bg-accent/40"
                    style={{ height: ROW_HEIGHT }}
                  >
                    <span className={cn("size-1.5 shrink-0 rounded-full", PRIORITY_DOT_CLASS[issue.priority])} />
                    <span className="truncate">{issue.title}</span>
                  </div>
                ))}
              </div>
            ))}
          </div>

          <div className="flex-1 overflow-x-auto">
            <div style={{ width: timelineWidth }} className="relative">
              <div className="flex border-b bg-muted/60" style={{ height: ROW_HEIGHT }}>
                {months.map((m, i) => (
                  <div
                    key={i}
                    className="shrink-0 truncate border-r px-2 text-[11px] font-semibold text-muted-foreground"
                    style={{ width: m.days * dayWidth, lineHeight: `${ROW_HEIGHT}px` }}
                  >
                    {m.label}
                  </div>
                ))}
              </div>
              <div className="relative border-b" style={{ height: ROW_HEIGHT }}>
                {todayOffset >= 0 && todayOffset <= timelineWidth ? (
                  <div className="absolute inset-y-0 z-10 w-px bg-destructive" style={{ left: todayOffset }} />
                ) : null}
              </div>

              {groups.map((group) => (
                <div key={group.key}>
                  {config.groupByFieldId ? <div className="border-b" style={{ height: ROW_HEIGHT }} /> : null}
                  {group.rows.map(({ issue, start, end }) => {
                    const left = daysBetweenISO(rangeStart, start) * dayWidth;
                    const width = Math.max(dayWidth, daysBetweenISO(start, end) * dayWidth);
                    return (
                      <div key={issue.id} className="relative border-b" style={{ height: ROW_HEIGHT }}>
                        {todayOffset >= 0 && todayOffset <= timelineWidth ? (
                          <div className="absolute inset-y-0 w-px bg-destructive/30" style={{ left: todayOffset }} />
                        ) : null}
                        <button
                          type="button"
                          onClick={() => openTask(issue, { spaceSlug, milestones, repos, registry })}
                          className={cn(
                            "absolute top-1/2 h-5 -translate-y-1/2 truncate rounded-[5px] bg-primary/70 px-1.5 text-left text-[10.5px] font-medium text-primary-foreground hover:bg-primary",
                          )}
                          style={{ left, width }}
                        >
                          {issue.title}
                        </button>
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
