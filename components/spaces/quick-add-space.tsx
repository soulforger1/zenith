"use client";

import { useActionState } from "react";

import { createSpaceAction, type SpaceFormState } from "@/lib/actions/spaces";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export function QuickAddSpace() {
  const [state, formAction, pending] = useActionState<SpaceFormState, FormData>(
    createSpaceAction,
    undefined,
  );

  return (
    <form action={formAction} className="space-y-1.5">
      <div className="flex gap-2">
        <Input name="name" placeholder="New space name" required className="flex-1" />
        <Button type="submit" disabled={pending}>
          {pending ? "Adding…" : "Add"}
        </Button>
      </div>
      {state?.error ? <p className="text-sm text-destructive">{state.error}</p> : null}
    </form>
  );
}
