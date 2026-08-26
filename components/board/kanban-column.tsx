"use client";

import { useDroppable } from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";

import { cn } from "@/lib/utils";
import type { FieldDef } from "@/lib/fields/registry";
import { SortableKanbanCard } from "@/components/board/kanban-card";
import { QuickAddTask } from "@/components/issues/quick-add-task";
import type { IssueStatus } from "@/lib/db/schema";
import type { KanbanIssue } from "@/components/board/kanban-board";

export function KanbanColumn({
  id,
  title,
  issues,
  spaceId,
  spaceSlug,
  groupFieldIsStatus,
  registry,
  visibleFieldIds,
  milestones,
  repos,
}: {
  id: string;
  title: string;
  issues: KanbanIssue[];
  spaceId: string;
  spaceSlug: string;
  groupFieldIsStatus: boolean;
  registry: FieldDef[];
  visibleFieldIds: string[];
  milestones: { id: string; title: string }[];
  repos: { id: string; name: string }[];
}) {
  const { setNodeRef, isOver } = useDroppable({ id });

  return (
    <div
      ref={setNodeRef}
      className={cn(
        "flex w-[280px] shrink-0 flex-col gap-2.5 rounded-[10px] border bg-card/60 p-3.5",
        isOver && "ring-2 ring-ring",
      )}
    >
      <div className="flex items-center justify-between">
        <span className="font-mono text-[11px] font-semibold tracking-[0.06em] text-muted-foreground">
          {title}
        </span>
        <span className="rounded-[5px] bg-muted px-1.5 py-px font-mono text-[11px] text-muted-foreground">
          {issues.length}
        </span>
      </div>
      <SortableContext items={issues.map((issue) => issue.id)} strategy={verticalListSortingStrategy}>
        <div className="flex flex-col gap-2.5">
          {issues.map((issue) => (
            <SortableKanbanCard
              key={issue.id}
              issue={issue}
              spaceSlug={spaceSlug}
              registry={registry}
              visibleFieldIds={visibleFieldIds}
              milestones={milestones}
              repos={repos}
            />
          ))}
          {issues.length === 0 ? (
            <p className="px-0.5 py-1 text-xs text-muted-foreground">No tasks</p>
          ) : null}
        </div>
      </SortableContext>
      {/* Quick-add only makes sense when the column axis is Status — its
       * `status` prop is the only field createIssueAction can pre-set. */}
      {groupFieldIsStatus ? (
        <QuickAddTask spaceId={spaceId} spaceSlug={spaceSlug} status={id as IssueStatus} label="Add task" />
      ) : null}
    </div>
  );
}
