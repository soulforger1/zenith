"use client";

import { useTransition } from "react";

import { deleteSpaceAction } from "@/lib/actions/spaces";

export function RemoveSpaceLink({ spaceId, spaceName }: { spaceId: string; spaceName: string }) {
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => {
        if (!window.confirm(`Delete "${spaceName}" and everything in it?`)) return;
        startTransition(() => {
          deleteSpaceAction(spaceId);
        });
      }}
      className="text-xs text-muted-foreground transition-colors hover:text-destructive"
    >
      {pending ? "Removing…" : "Remove"}
    </button>
  );
}
