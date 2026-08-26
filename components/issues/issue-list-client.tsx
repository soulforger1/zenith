"use client";

import { useMemo, useState } from "react";
import { toast } from "sonner";

import {
  bulkDeleteIssuesAction,
  bulkUpdateIssuesPriorityAction,
  bulkUpdateIssuesStatusAction,
} from "@/lib/actions/issues";
import { issuePriorityValues, issueStatusValues, type IssuePriority, type IssueStatus } from "@/lib/db/schema";
import { PRIORITY_LABEL } from "@/lib/priority";
import { IssueRow, type IssueRowData } from "@/components/issues/issue-row";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const STATUS_LABEL: Record<IssueStatus, string> = {
  backlog: "Backlog",
  todo: "Todo",
  in_progress: "In Progress",
  done: "Done",
};

const PRIORITY_RANK: Record<IssuePriority, number> = { high: 0, medium: 1, low: 2 };

type SortKey = "" | "priority" | "dueDate" | "title";

export function IssueListClient({
  issues,
  spaceSlug,
  milestones,
  repos,
}: {
  issues: IssueRowData[];
  spaceSlug: string;
  milestones: { id: string; title: string }[];
  repos: { id: string; name: string }[];
}) {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [statusFilter, setStatusFilter] = useState("");
  const [priorityFilter, setPriorityFilter] = useState("");
  const [milestoneFilter, setMilestoneFilter] = useState("");
  const [repoFilter, setRepoFilter] = useState("");
  const [tagFilter, setTagFilter] = useState("");
  const [sortKey, setSortKey] = useState<SortKey>("");
  const [pending, setPending] = useState(false);

  const tagOptions = useMemo(() => {
    const set = new Set<string>();
    for (const issue of issues) for (const tag of issue.tags) set.add(tag);
    return Array.from(set).sort();
  }, [issues]);

  const hasFilters = Boolean(statusFilter || priorityFilter || milestoneFilter || repoFilter || tagFilter);

  const visible = useMemo(() => {
    const filtered = issues.filter((issue) => {
      if (statusFilter && issue.status !== statusFilter) return false;
      if (priorityFilter && issue.priority !== priorityFilter) return false;
      if (milestoneFilter && issue.milestoneId !== milestoneFilter) return false;
      if (repoFilter && !issue.repoIds.includes(repoFilter)) return false;
      if (tagFilter && !issue.tags.includes(tagFilter)) return false;
      return true;
    });
    if (sortKey === "priority") {
      return [...filtered].sort(
        (a, b) => PRIORITY_RANK[a.priority as IssuePriority] - PRIORITY_RANK[b.priority as IssuePriority],
      );
    }
    if (sortKey === "dueDate") {
      return [...filtered].sort((a, b) => {
        if (!a.dueDate && !b.dueDate) return 0;
        if (!a.dueDate) return 1;
        if (!b.dueDate) return -1;
        return a.dueDate.localeCompare(b.dueDate);
      });
    }
    if (sortKey === "title") {
      return [...filtered].sort((a, b) => a.title.localeCompare(b.title));
    }
    return filtered;
  }, [issues, statusFilter, priorityFilter, milestoneFilter, repoFilter, tagFilter, sortKey]);

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

  function clearFilters() {
    setStatusFilter("");
    setPriorityFilter("");
    setMilestoneFilter("");
    setRepoFilter("");
    setTagFilter("");
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
      <div className="flex flex-wrap items-center gap-2">
        <Select value={statusFilter} onValueChange={(v) => setStatusFilter(v ?? "")}>
          <SelectTrigger className="w-[130px] text-xs">
            <SelectValue placeholder="All statuses" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="">All statuses</SelectItem>
            {issueStatusValues.map((s) => (
              <SelectItem key={s} value={s}>
                {STATUS_LABEL[s]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={priorityFilter} onValueChange={(v) => setPriorityFilter(v ?? "")}>
          <SelectTrigger className="w-[130px] text-xs">
            <SelectValue placeholder="All priorities" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="">All priorities</SelectItem>
            {issuePriorityValues.map((p) => (
              <SelectItem key={p} value={p}>
                {PRIORITY_LABEL[p]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {milestones.length > 0 ? (
          <Select value={milestoneFilter} onValueChange={(v) => setMilestoneFilter(v ?? "")}>
            <SelectTrigger className="w-[150px] text-xs">
              <SelectValue placeholder="All milestones" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">All milestones</SelectItem>
              {milestones.map((m) => (
                <SelectItem key={m.id} value={m.id}>
                  {m.title}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        ) : null}
        {repos.length > 0 ? (
          <Select value={repoFilter} onValueChange={(v) => setRepoFilter(v ?? "")}>
            <SelectTrigger className="w-[130px] text-xs">
              <SelectValue placeholder="All repos" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">All repos</SelectItem>
              {repos.map((r) => (
                <SelectItem key={r.id} value={r.id}>
                  {r.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        ) : null}
        {tagOptions.length > 0 ? (
          <Select value={tagFilter} onValueChange={(v) => setTagFilter(v ?? "")}>
            <SelectTrigger className="w-[120px] text-xs">
              <SelectValue placeholder="All tags" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">All tags</SelectItem>
              {tagOptions.map((t) => (
                <SelectItem key={t} value={t}>
                  {t}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        ) : null}
        <Select value={sortKey} onValueChange={(v) => setSortKey((v ?? "") as SortKey)}>
          <SelectTrigger className="w-[140px] text-xs">
            <SelectValue placeholder="Sort: default" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="">Sort: default</SelectItem>
            <SelectItem value="priority">Priority</SelectItem>
            <SelectItem value="dueDate">Due date</SelectItem>
            <SelectItem value="title">Title</SelectItem>
          </SelectContent>
        </Select>
        {hasFilters ? (
          <button
            type="button"
            onClick={clearFilters}
            className="text-xs text-muted-foreground underline-offset-2 hover:text-foreground hover:underline"
          >
            Clear filters
          </button>
        ) : null}
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
        <div className="grid grid-cols-[28px_1.2fr_100px_140px_130px_90px_80px_90px] items-center bg-muted/60 px-4 py-2.5 font-mono text-[11px] font-semibold tracking-wide text-muted-foreground">
          <Checkbox
            checked={visible.length > 0 && selected.size === visible.length}
            onCheckedChange={toggleSelectAll}
          />
          <div>TASK</div>
          <div>PRIORITY</div>
          <div>TAGS</div>
          <div>BRANCH</div>
          <div>EST.</div>
          <div>DUE</div>
          <div>STATUS</div>
        </div>
        {visible.length === 0 ? (
          <p className="p-6 text-center text-sm text-muted-foreground">
            {issues.length === 0 ? "No tasks yet." : "No tasks match these filters."}
          </p>
        ) : (
          visible.map((issue) => (
            <IssueRow
              key={issue.id}
              issue={issue}
              spaceSlug={spaceSlug}
              milestones={milestones}
              repos={repos}
              selected={selected.has(issue.id)}
              onToggleSelect={() => toggleSelect(issue.id)}
            />
          ))
        )}
      </div>
    </div>
  );
}
