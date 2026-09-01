"use client";

import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { CornerDownRight } from "lucide-react";

import { cn } from "@/lib/utils";
import { PRIORITY_DOT_CLASS } from "@/lib/priority";
import type { FieldDef } from "@/lib/fields/registry";
import { FieldBadge } from "@/components/fields/field-badge";
import { useAppShell } from "@/components/layout/app-shell-context";
import type { KanbanIssue } from "@/components/board/kanban-board";

export function KanbanCard({
  issue,
  spaceSlug,
  registry,
  visibleFieldIds,
  milestones,
  repos,
  overlay,
}: {
  issue: KanbanIssue;
  spaceSlug: string;
  registry: FieldDef[];
  visibleFieldIds: string[];
  milestones: { id: string; title: string }[];
  repos: { id: string; name: string }[];
  overlay?: boolean;
}) {
  const { openTask } = useAppShell();
  const visibleFields = visibleFieldIds
    .map((id) => registry.find((f) => f.id === id))
    .filter((f): f is FieldDef => Boolean(f));

  return (
    <div
      onClick={() => !overlay && openTask(issue, { spaceSlug, milestones, repos, registry })}
      className={cn(
        "cursor-pointer space-y-2 rounded-[9px] border bg-card p-3 text-sm shadow-sm transition-colors hover:border-ring/40",
        overlay && "shadow-lg",
      )}
    >
      <div className="flex items-start gap-1.5">
        <span className={cn("mt-1.5 size-1.5 shrink-0 rounded-full", PRIORITY_DOT_CLASS[issue.priority])} />
        {issue.parentId ? (
          <CornerDownRight className="mt-0.5 size-3 shrink-0 text-muted-foreground" aria-label="Subtask" />
        ) : null}
        <span className="text-[13.5px] leading-snug font-medium">{issue.title}</span>
      </div>

      {issue.tags.length > 0 ? (
        <div className="flex flex-wrap gap-1">
          {issue.tags.map((tag) => (
            <span
              key={tag}
              className="rounded-[5px] bg-muted px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground"
            >
              {tag}
            </span>
          ))}
        </div>
      ) : null}

      {issue.subtaskCount.total > 0 ? (
        <div className="flex items-center gap-1.5">
          <div className="h-1 flex-1 overflow-hidden rounded-full bg-muted">
            <div
              className="h-full bg-primary"
              style={{ width: `${Math.round((issue.subtaskCount.done / issue.subtaskCount.total) * 100)}%` }}
            />
          </div>
          <span className="font-mono text-[10.5px] text-muted-foreground">
            {issue.subtaskCount.done}/{issue.subtaskCount.total}
          </span>
        </div>
      ) : null}

      {visibleFields.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2">
          {visibleFields.map((field) => (
            <FieldBadge key={field.id} field={field} value={field.getValue(issue)} />
          ))}
        </div>
      ) : null}
    </div>
  );
}

export function SortableKanbanCard({
  issue,
  spaceSlug,
  registry,
  visibleFieldIds,
  milestones,
  repos,
}: {
  issue: KanbanIssue;
  spaceSlug: string;
  registry: FieldDef[];
  visibleFieldIds: string[];
  milestones: { id: string; title: string }[];
  repos: { id: string; name: string }[];
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: issue.id,
  });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
  };

  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <KanbanCard
        issue={issue}
        spaceSlug={spaceSlug}
        registry={registry}
        visibleFieldIds={visibleFieldIds}
        milestones={milestones}
        repos={repos}
      />
    </div>
  );
}
