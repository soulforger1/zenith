"use client";

import { useTransition } from "react";
import { format } from "date-fns";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { isOverdue } from "@/lib/date";
import { updateIssueGroupAction } from "@/lib/actions/issues";
import { issueStatusValues, type IssuePriority, type IssueStatus } from "@/lib/db/schema";
import { PRIORITY_LABEL, PRIORITY_TEXT_CLASS, PRIORITY_DOT_CLASS } from "@/lib/priority";
import { useAppShell } from "@/components/layout/app-shell-context";
import type { DrawerTask } from "@/components/layout/app-shell-context";
import { Checkbox } from "@/components/ui/checkbox";

const STATUS_LABEL: Record<IssueStatus, string> = {
  backlog: "Backlog",
  todo: "Todo",
  in_progress: "In Prog.",
  done: "Done",
};

export type IssueRowData = DrawerTask;

export function IssueRow({
  issue,
  spaceSlug,
  milestones,
  repos,
  selected,
  onToggleSelect,
}: {
  issue: IssueRowData;
  spaceSlug: string;
  milestones: { id: string; title: string }[];
  repos: { id: string; name: string }[];
  selected: boolean;
  onToggleSelect: () => void;
}) {
  const { openTask } = useAppShell();
  const [, startTransition] = useTransition();

  return (
    <div
      onClick={() => openTask(issue, { spaceSlug, milestones, repos })}
      className="grid cursor-pointer grid-cols-[28px_1.2fr_100px_140px_130px_90px_80px_90px] items-center border-t px-4 py-2.5 text-[13px] transition-colors first:border-t-0 hover:bg-accent/40"
    >
      <Checkbox
        checked={selected}
        onClick={(e) => e.stopPropagation()}
        onCheckedChange={onToggleSelect}
      />
      <div className="flex min-w-0 items-center gap-2 overflow-hidden">
        <span className={cn("size-1.5 shrink-0 rounded-full", PRIORITY_DOT_CLASS[issue.priority as IssuePriority])} />
        <span
          className={cn(
            "truncate",
            issue.status === "done" && "text-muted-foreground line-through",
          )}
        >
          {issue.title}
        </span>
      </div>
      <div className={cn("min-w-0 text-xs capitalize", PRIORITY_TEXT_CLASS[issue.priority as IssuePriority])}>
        {PRIORITY_LABEL[issue.priority as IssuePriority]}
      </div>
      <div className="min-w-0 truncate text-[11.5px] text-muted-foreground">
        {issue.tags.length ? issue.tags.join(", ") : "—"}
      </div>
      <div className="min-w-0 truncate font-mono text-[11px] text-branch">{issue.branch || "—"}</div>
      <div className="min-w-0 truncate font-mono text-[11.5px] text-muted-foreground">{issue.estimate || "—"}</div>
      <div
        className={cn(
          "min-w-0 truncate font-mono text-[11.5px]",
          issue.dueDate && isOverdue(issue.dueDate, issue.status as IssueStatus)
            ? "font-semibold text-destructive"
            : "text-muted-foreground",
        )}
      >
        {issue.dueDate ? format(new Date(issue.dueDate), "MMM d") : "—"}
      </div>
      <select
        value={issue.status}
        onClick={(e) => e.stopPropagation()}
        onChange={(e) => {
          const status = e.target.value as IssueStatus;
          startTransition(() => {
            updateIssueGroupAction(issue.id, spaceSlug, { status }, Date.now()).catch(() =>
              toast.error("Couldn't update status."),
            );
          });
        }}
        className="rounded-md border border-input bg-accent px-1.5 py-1 text-[11px] text-foreground"
      >
        {issueStatusValues.map((s) => (
          <option key={s} value={s}>
            {STATUS_LABEL[s]}
          </option>
        ))}
      </select>
    </div>
  );
}
