"use client";

import Link from "next/link";
import { useTransition } from "react";
import { Trash2 } from "lucide-react";

import { deleteMilestoneAction, updateMilestoneAction } from "@/lib/actions/milestones";
import { cn } from "@/lib/utils";
import { PRIORITY_TEXT_CLASS } from "@/lib/priority";
import type { IssuePriority } from "@/lib/db/schema";
import { Button } from "@/components/ui/button";
import { MilestoneCloseButton } from "@/components/milestones/milestone-close-button";
import { MilestoneFormDialog } from "@/components/milestones/milestone-form-dialog";
import { MilestoneProgressBar } from "@/components/milestones/milestone-progress-bar";

export function MilestoneCard({
  milestone,
  spaceSlug,
  closed,
  total,
  linked,
}: {
  milestone: { id: string; title: string; description: string | null; dueDate: string | null; status: string };
  spaceSlug: string;
  closed: number;
  total: number;
  linked: { title: string; priority: IssuePriority }[];
}) {
  const [pending, startTransition] = useTransition();
  const boundUpdate = updateMilestoneAction.bind(null, milestone.id, spaceSlug);
  const isClosed = milestone.status === "closed";

  return (
    <div className={cn("group rounded-[10px] border bg-card p-[18px_20px] px-5 py-[18px]", isClosed && "opacity-60")}>
      <div className="mb-2.5 flex items-baseline justify-between gap-2">
        <Link
          href={`/spaces/${spaceSlug}/milestones/${milestone.id}`}
          className={cn(
            "text-[15px] font-semibold hover:underline",
            isClosed && "text-muted-foreground line-through",
          )}
        >
          {milestone.title}
        </Link>
        <div className="flex items-center gap-2">
          {milestone.dueDate ? (
            <span className="text-xs text-muted-foreground">Due {milestone.dueDate}</span>
          ) : null}
          <MilestoneCloseButton
            milestoneId={milestone.id}
            spaceSlug={spaceSlug}
            isClosed={isClosed}
            className="opacity-0 transition-opacity group-hover:opacity-100"
          />
          <div className="opacity-0 transition-opacity group-hover:opacity-100">
            <MilestoneFormDialog
              action={boundUpdate}
              mode="edit"
              defaultValues={{
                title: milestone.title,
                description: milestone.description,
                dueDate: milestone.dueDate,
              }}
            />
          </div>
          <Button
            variant="ghost"
            size="icon-xs"
            disabled={pending}
            className="opacity-0 transition-opacity group-hover:opacity-100"
            onClick={() => {
              if (!window.confirm(`Delete "${milestone.title}"? Its tasks will be unassigned.`)) return;
              startTransition(() => {
                deleteMilestoneAction(milestone.id, spaceSlug);
              });
            }}
          >
            <Trash2 className="size-3.5" />
            <span className="sr-only">Delete milestone</span>
          </Button>
        </div>
      </div>
      <div className="mb-2.5">
        <MilestoneProgressBar closed={closed} total={total} />
      </div>
      {linked.length > 0 ? (
        <div className="flex flex-wrap gap-1.5">
          {linked.map((task, idx) => (
            <span
              key={idx}
              className={`rounded-[5px] bg-muted px-2 py-0.5 text-[11.5px] ${PRIORITY_TEXT_CLASS[task.priority]}`}
            >
              {task.title}
            </span>
          ))}
        </div>
      ) : null}
    </div>
  );
}
