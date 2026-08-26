"use client";

import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";

/** Compact repo multi-select — a trigger button showing "None"/one repo
 * name/"N repos" that opens a Dialog with a checkbox list. Built as a Dialog
 * rather than a true anchored popover for the same reason as
 * ViewSettingsPopover (components/views/view-settings-popover.tsx): avoids
 * nesting interactive controls inside a focus-trapped menu. Shared by the
 * task detail drawer and the AI paste-task modal (single + bulk rows),
 * which would otherwise each hand-roll their own repo picker. */
export function RepoPicker({
  repos,
  value,
  onChange,
}: {
  repos: { id: string; name: string }[];
  value: string[];
  onChange: (next: string[]) => void;
}) {
  const [open, setOpen] = useState(false);

  function toggle(id: string) {
    onChange(value.includes(id) ? value.filter((v) => v !== id) : [...value, id]);
  }

  const label =
    value.length === 0
      ? "None"
      : value.length === 1
        ? (repos.find((r) => r.id === value[0])?.name ?? "1 repo")
        : `${value.length} repos`;

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={<Button variant="outline" size="sm" className="w-full justify-start text-xs font-normal" />}
      >
        <span className="truncate">{label}</span>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[320px]">
        <DialogHeader>
          <DialogTitle>Repos</DialogTitle>
        </DialogHeader>
        {repos.length === 0 ? (
          <p className="text-xs text-muted-foreground">No repos linked to this space yet.</p>
        ) : (
          <div className="flex max-h-[240px] flex-col gap-1.5 overflow-y-auto">
            {repos.map((repo) => (
              <label key={repo.id} className="flex items-center gap-2 text-[13px]">
                <Checkbox checked={value.includes(repo.id)} onCheckedChange={() => toggle(repo.id)} />
                {repo.name}
              </label>
            ))}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
