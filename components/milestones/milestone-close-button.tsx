"use client";

import { useTransition } from "react";
import { CircleCheck, RotateCcw } from "lucide-react";

import { toggleMilestoneClosedAction } from "@/lib/actions/milestones";
import { Button } from "@/components/ui/button";

export function MilestoneCloseButton({
  milestoneId,
  spaceSlug,
  isClosed,
  className,
}: {
  milestoneId: string;
  spaceSlug: string;
  isClosed: boolean;
  className?: string;
}) {
  const [pending, startTransition] = useTransition();

  return (
    <Button
      variant="ghost"
      size="icon-xs"
      disabled={pending}
      className={className}
      onClick={() => {
        startTransition(() => {
          toggleMilestoneClosedAction(milestoneId, spaceSlug, !isClosed);
        });
      }}
    >
      {isClosed ? <RotateCcw className="size-3.5" /> : <CircleCheck className="size-3.5" />}
      <span className="sr-only">{isClosed ? "Reopen milestone" : "Close milestone"}</span>
    </Button>
  );
}
