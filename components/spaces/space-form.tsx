"use client";

import { useActionState } from "react";

import type { SpaceFormState } from "@/lib/actions/spaces";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

export function SpaceForm({
  action,
  defaultValues,
  submitLabel = "Create space",
}: {
  action: (prevState: SpaceFormState, formData: FormData) => Promise<SpaceFormState>;
  defaultValues?: { name?: string; description?: string | null };
  submitLabel?: string;
}) {
  const [state, formAction, pending] = useActionState<SpaceFormState, FormData>(action, undefined);

  return (
    <form action={formAction} className="max-w-md space-y-4">
      <div className="space-y-2">
        <Label htmlFor="name">Name</Label>
        <Input
          id="name"
          name="name"
          placeholder="Work, Side Projects…"
          defaultValue={defaultValues?.name}
          required
          autoFocus
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="description">Description</Label>
        <Textarea
          id="description"
          name="description"
          placeholder="Optional"
          defaultValue={defaultValues?.description ?? ""}
          rows={3}
        />
      </div>
      {state?.error ? <p className="text-sm text-destructive">{state.error}</p> : null}
      <Button type="submit" disabled={pending}>
        {pending ? "Saving…" : submitLabel}
      </Button>
    </form>
  );
}
