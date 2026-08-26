"use client";

import { useMemo, useState, useTransition } from "react";
import { MoreHorizontal } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { bulkDeleteIssuesAction, bulkUpdateIssuesPriorityAction, bulkUpdateIssuesStatusAction } from "@/lib/actions/issues";
import { updateViewConfigAction } from "@/lib/actions/views";
import { issuePriorityValues, issueStatusValues, type IssueStatus } from "@/lib/db/schema";
import { PRIORITY_LABEL } from "@/lib/priority";
import { buildFieldRegistry, type CustomFieldRow, type FieldDef } from "@/lib/fields/registry";
import { applyFilters, applyKeyword, applySort, groupIssuesBy } from "@/lib/fields/filter";
import type { TableViewConfig } from "@/lib/views/types";
import type { IssueRecord } from "@/lib/issue-types";
import { useAppShell } from "@/components/layout/app-shell-context";
import { FieldBadge } from "@/components/fields/field-badge";
import { FieldFormDialog } from "@/components/fields/field-form-dialog";
import { ViewFilterBar } from "@/components/views/view-filter-bar";
import { ViewSettingsPopover } from "@/components/views/view-settings-popover";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const STATUS_LABEL: Record<IssueStatus, string> = {
  backlog: "Backlog",
  todo: "Todo",
  in_progress: "In Progress",
  done: "Done",
};

export function TableView({
  view,
  issues,
  spaceId,
  spaceSlug,
  customFields,
  milestones,
  repos,
}: {
  view: { id: string; config: TableViewConfig };
  issues: IssueRecord[];
  spaceId: string;
  spaceSlug: string;
  customFields: CustomFieldRow[];
  milestones: { id: string; title: string }[];
  repos: { id: string; name: string }[];
}) {
  const { openTask } = useAppShell();
  // Built client-side, not passed down as a prop from the server component —
  // FieldDef.getValue is a function, which can't cross the RSC serialization
  // boundary. Only the plain `customFields` rows are server-fetched props.
  const registry = useMemo(() => buildFieldRegistry(customFields, { milestones, repos }), [customFields, milestones, repos]);
  const [config, setConfig] = useState(view.config);
  const [keyword, setKeyword] = useState("");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [pending, setPending] = useState(false);
  const [, startTransition] = useTransition();

  function persistConfig(next: TableViewConfig) {
    setConfig(next);
    startTransition(() => {
      updateViewConfigAction(view.id, spaceSlug, next).catch(() => toast.error("Couldn't save view settings."));
    });
  }

  const visibleFields = useMemo(
    () =>
      config.visibleFieldIds
        .map((id) => registry.find((f) => f.id === id))
        .filter((f): f is FieldDef => Boolean(f)),
    [config.visibleFieldIds, registry],
  );

  const visible = useMemo(() => {
    let result = applyKeyword(issues, keyword, registry);
    result = applyFilters(result, config.filters, registry);
    result = applySort(result, config.sort, registry);
    return result;
  }, [issues, keyword, config.filters, config.sort, registry]);

  const groups = useMemo(
    () => groupIssuesBy(visible, config.groupByFieldId, registry),
    [visible, config.groupByFieldId, registry],
  );

  const gridTemplate = `28px 1.4fr ${visibleFields.map(() => "120px").join(" ")} 90px`;

  function toggleSelect(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }
  function toggleSelectAll() {
    setSelected((prev) => (prev.size === visible.length ? new Set() : new Set(visible.map((i) => i.id))));
  }
  function clearSelection() {
    setSelected(new Set());
  }

  async function handleBulkStatus(status: string) {
    if (!status || selected.size === 0) return;
    setPending(true);
    try {
      await bulkUpdateIssuesStatusAction(Array.from(selected), spaceSlug, status);
      clearSelection();
    } catch {
      toast.error("Couldn't update status.");
    } finally {
      setPending(false);
    }
  }
  async function handleBulkPriority(priority: string) {
    if (!priority || selected.size === 0) return;
    setPending(true);
    try {
      await bulkUpdateIssuesPriorityAction(Array.from(selected), spaceSlug, priority);
      clearSelection();
    } catch {
      toast.error("Couldn't update priority.");
    } finally {
      setPending(false);
    }
  }
  async function handleBulkDelete() {
    if (selected.size === 0) return;
    if (!window.confirm(`Delete ${selected.size} task${selected.size === 1 ? "" : "s"}?`)) return;
    setPending(true);
    try {
      await bulkDeleteIssuesAction(Array.from(selected), spaceSlug);
      clearSelection();
    } catch {
      toast.error("Couldn't delete those tasks.");
    } finally {
      setPending(false);
    }
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
          viewType="table"
          registry={registry}
          config={config}
          onChange={(c) => persistConfig(c as TableViewConfig)}
        />
      </div>

      {selected.size > 0 ? (
        <div className="flex flex-wrap items-center gap-2 rounded-lg border bg-accent/40 px-3 py-2">
          <span className="text-xs font-medium">{selected.size} selected</span>
          <Select value="" onValueChange={(v) => v && handleBulkStatus(v)}>
            <SelectTrigger className="w-[130px] text-xs" disabled={pending}>
              <SelectValue placeholder="Set status" />
            </SelectTrigger>
            <SelectContent>
              {issueStatusValues.map((s) => (
                <SelectItem key={s} value={s}>
                  {STATUS_LABEL[s]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value="" onValueChange={(v) => v && handleBulkPriority(v)}>
            <SelectTrigger className="w-[130px] text-xs" disabled={pending}>
              <SelectValue placeholder="Set priority" />
            </SelectTrigger>
            <SelectContent>
              {issuePriorityValues.map((p) => (
                <SelectItem key={p} value={p}>
                  {PRIORITY_LABEL[p]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button variant="destructive" size="sm" disabled={pending} onClick={handleBulkDelete}>
            Delete
          </Button>
          <button
            type="button"
            onClick={clearSelection}
            className="ml-auto text-xs text-muted-foreground hover:text-foreground"
          >
            Clear
          </button>
        </div>
      ) : null}

      <div className="overflow-hidden rounded-lg border">
        <div
          className="grid items-center bg-muted/60 px-4 py-2.5 font-mono text-[11px] font-semibold tracking-wide text-muted-foreground"
          style={{ gridTemplateColumns: gridTemplate }}
        >
          <Checkbox
            checked={visible.length > 0 && selected.size === visible.length}
            onCheckedChange={toggleSelectAll}
          />
          <div>TASK</div>
          {visibleFields.map((field) => (
            <div key={field.id} className="flex items-center justify-between gap-1">
              <span className="truncate">{field.name.toUpperCase()}</span>
              <ColumnMenu field={field} config={config} onChange={persistConfig} />
            </div>
          ))}
          <div className="flex items-center justify-end">
            <FieldFormDialog spaceId={spaceId} spaceSlug={spaceSlug} mode="create" />
          </div>
        </div>

        {groups.map((group) =>
          group.issues.length === 0 && config.groupByFieldId === null ? null : (
            <div key={group.key}>
              {config.groupByFieldId ? (
                <div className="border-t bg-muted/30 px-4 py-1.5 text-[11px] font-semibold text-muted-foreground first:border-t-0">
                  {group.label} · {group.issues.length}
                </div>
              ) : null}
              {group.issues.map((issue) => (
                <div
                  key={issue.id}
                  onClick={() => openTask(issue, { spaceSlug, milestones, repos, registry })}
                  className="grid cursor-pointer items-center border-t px-4 py-2.5 text-[13px] transition-colors first:border-t-0 hover:bg-accent/40"
                  style={{ gridTemplateColumns: gridTemplate }}
                >
                  <Checkbox
                    checked={selected.has(issue.id)}
                    onClick={(e) => e.stopPropagation()}
                    onCheckedChange={() => toggleSelect(issue.id)}
                  />
                  <span className={cn("truncate", issue.status === "done" && "text-muted-foreground line-through")}>
                    {issue.title}
                  </span>
                  {visibleFields.map((field) => (
                    <div key={field.id} className="min-w-0 truncate">
                      <FieldBadge field={field} value={field.getValue(issue)} />
                    </div>
                  ))}
                  <div />
                </div>
              ))}
            </div>
          ),
        )}
        {visible.length === 0 ? (
          <p className="p-6 text-center text-sm text-muted-foreground">
            {issues.length === 0 ? "No tasks yet." : "No tasks match these filters."}
          </p>
        ) : null}
      </div>
    </div>
  );
}

function ColumnMenu({
  field,
  config,
  onChange,
}: {
  field: FieldDef;
  config: TableViewConfig;
  onChange: (config: TableViewConfig) => void;
}) {
  function hide() {
    onChange({ ...config, visibleFieldIds: config.visibleFieldIds.filter((id) => id !== field.id) });
  }
  function sortAsc() {
    onChange({ ...config, sort: [{ fieldId: field.id, direction: "asc" }] });
  }
  function sortDesc() {
    onChange({ ...config, sort: [{ fieldId: field.id, direction: "desc" }] });
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<button type="button" className="text-muted-foreground hover:text-foreground" />}>
        <MoreHorizontal className="size-3" />
        <span className="sr-only">{field.name} options</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent>
        <DropdownMenuItem onClick={sortAsc}>Sort ascending</DropdownMenuItem>
        <DropdownMenuItem onClick={sortDesc}>Sort descending</DropdownMenuItem>
        <DropdownMenuItem onClick={hide}>Hide field</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
