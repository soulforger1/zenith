"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";

import { updateSpaceContextAction } from "@/lib/actions/spaces";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

export function SpaceContextForm({
  spaceId,
  spaceSlug,
  initialContext,
}: {
  spaceId: string;
  spaceSlug: string;
  initialContext: string | null;
}) {
  const [context, setContext] = useState(initialContext ?? "");
  const [, startTransition] = useTransition();

  return (
    <div className="space-y-1.5">
      <Label htmlFor="space-context" className="text-[13px] font-semibold text-foreground/80">
        Context
      </Label>
      <p className="text-xs text-muted-foreground">
        Features, services, stack, conventions — used to inform tasks parsed from pasted text
        for this space.
      </p>
      <Textarea
        id="space-context"
        value={context}
        onChange={(e) => setContext(e.target.value)}
        onBlur={() => {
          if (context.trim() === (initialContext ?? "").trim()) return;
          startTransition(() => {
            updateSpaceContextAction(spaceId, spaceSlug, context).catch(() =>
              toast.error("Couldn't save context."),
            );
          });
        }}
        rows={5}
        placeholder="e.g. Next.js + Postgres monorepo. Services: web app, worker, admin dashboard. Branch names use fix/*, feature/*, chore/*. Payments go through Stripe."
        className="text-[13px]"
      />
    </div>
  );
}
