"use client";

import { useState, useTransition } from "react";
import { Plus } from "lucide-react";

import { cn } from "@/lib/utils";
import { createIssueAction } from "@/lib/actions/issues";
import type { IssueStatus } from "@/lib/db/schema";

export function QuickAddTask({
  spaceId,
  spaceSlug,
  status,
  label = "Add task",
  className,
}: {
  spaceId: string;
  spaceSlug: string;
  status: IssueStatus;
  label?: string;
  className?: string;
}) {
  const [active, setActive] = useState(false);
  const [value, setValue] = useState("");
  const [, startTransition] = useTransition();

  function submit() {
    const title = value.trim();
    setValue("");
    setActive(false);
    if (!title) return;
    startTransition(() => {
      createIssueAction(spaceId, spaceSlug, status, title);
    });
  }

  if (!active) {
    return (
      <button
        type="button"
        onClick={() => setActive(true)}
        className={cn(
          "flex items-center gap-1.5 text-left text-xs text-muted-foreground transition-colors hover:text-foreground",
          className,
        )}
      >
        <Plus className="size-3.5" />
        {label}
      </button>
    );
  }

  return (
    <input
      autoFocus
      value={value}
      onChange={(e) => setValue(e.target.value)}
      onBlur={submit}
      onKeyDown={(e) => {
        if (e.key === "Enter") submit();
        if (e.key === "Escape") {
          setValue("");
          setActive(false);
        }
      }}
      placeholder="Task title…"
      className={cn(
        "w-full rounded-md border border-input bg-transparent px-2 py-1.5 text-xs outline-none focus-visible:ring-1 focus-visible:ring-ring",
        className,
      )}
    />
  );
}
