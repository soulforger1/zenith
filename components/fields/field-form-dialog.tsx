"use client";

import { useState, useTransition } from "react";
import { Pencil, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { createCustomFieldAction, updateCustomFieldAction } from "@/lib/actions/custom-fields";
import { customFieldTypeValues, type CustomFieldType } from "@/lib/db/schema";
import { fieldColorDotClass, fieldColorValues } from "@/lib/fields/colors";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const TYPE_LABEL: Record<CustomFieldType, string> = {
  text: "Text",
  number: "Number",
  date: "Date",
  single_select: "Single select",
  multi_select: "Multi select",
  iteration: "Iteration",
};

type OptionRow = { id: string; name: string; color: string };
type IterationRow = { id: string; title: string; startDate: string; durationDays: number };

export type FieldSummary = {
  id: string;
  name: string;
  type: CustomFieldType;
  options: OptionRow[] | IterationRow[];
};

function randomId() {
  return crypto.randomUUID();
}

function isSelectType(type: CustomFieldType) {
  return type === "single_select" || type === "multi_select";
}

export function FieldFormDialog({
  spaceId,
  spaceSlug,
  mode,
  field,
}: {
  spaceId: string;
  spaceSlug: string;
  mode: "create" | "edit";
  field?: FieldSummary;
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState(field?.name ?? "");
  const [type, setType] = useState<CustomFieldType>(field?.type ?? "text");
  const [options, setOptions] = useState<OptionRow[]>(
    field && isSelectType(field.type) ? (field.options as OptionRow[]) : [],
  );
  const [iterations, setIterations] = useState<IterationRow[]>(
    field?.type === "iteration" ? (field.options as IterationRow[]) : [],
  );
  const [pending, startTransition] = useTransition();

  function reset() {
    setName(field?.name ?? "");
    setType(field?.type ?? "text");
    setOptions(field && isSelectType(field.type) ? (field.options as OptionRow[]) : []);
    setIterations(field?.type === "iteration" ? (field.options as IterationRow[]) : []);
  }

  function handleOpenChange(next: boolean) {
    if (!next) reset();
    setOpen(next);
  }

  function addOption() {
    setOptions((prev) => [
      ...prev,
      { id: randomId(), name: "", color: fieldColorValues[prev.length % fieldColorValues.length] },
    ]);
  }
  function updateOption(id: string, patch: Partial<OptionRow>) {
    setOptions((prev) => prev.map((o) => (o.id === id ? { ...o, ...patch } : o)));
  }
  function removeOption(id: string) {
    setOptions((prev) => prev.filter((o) => o.id !== id));
  }

  function addIteration() {
    setIterations((prev) => [
      ...prev,
      { id: randomId(), title: `Sprint ${prev.length + 1}`, startDate: new Date().toISOString().slice(0, 10), durationDays: 14 },
    ]);
  }
  function updateIteration(id: string, patch: Partial<IterationRow>) {
    setIterations((prev) => prev.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  }
  function removeIteration(id: string) {
    setIterations((prev) => prev.filter((it) => it.id !== id));
  }

  function handleSave() {
    const trimmed = name.trim();
    if (!trimmed) return;
    const finalOptions = isSelectType(type)
      ? options.filter((o) => o.name.trim())
      : type === "iteration"
        ? iterations.filter((it) => it.title.trim())
        : [];

    startTransition(() => {
      const action =
        mode === "create"
          ? createCustomFieldAction(spaceId, spaceSlug, { name: trimmed, type, options: finalOptions })
          : updateCustomFieldAction(field!.id, spaceSlug, { name: trimmed, options: finalOptions });
      action.then((result) => {
        if (result?.error) {
          toast.error(result.error);
          return;
        }
        toast.success(mode === "create" ? `Created field "${trimmed}"` : "Field updated");
        handleOpenChange(false);
      });
    });
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      {mode === "create" ? (
        <DialogTrigger render={<Button size="sm" className="gap-1.5" />}>
          <Plus className="size-3.5" />
          Add field
        </DialogTrigger>
      ) : (
        <DialogTrigger render={<Button variant="ghost" size="icon-sm" />}>
          <Pencil className="size-3.5" />
          <span className="sr-only">Edit {field?.name}</span>
        </DialogTrigger>
      )}
      <DialogContent className="sm:max-w-[440px]">
        <DialogHeader>
          <DialogTitle>{mode === "create" ? "New field" : "Edit field"}</DialogTitle>
          <DialogDescription>
            {mode === "create"
              ? "Custom fields show up as columns in Table, group/filter options in Board, and date options in Roadmap."
              : "Rename this field or edit its options."}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div>
            <Label className="mb-1.5 text-[11px] text-muted-foreground">Name</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Size" autoFocus />
          </div>
          <div>
            <Label className="mb-1.5 text-[11px] text-muted-foreground">Type</Label>
            <Select
              value={type}
              onValueChange={(v) => setType((v ?? "text") as CustomFieldType)}
              disabled={mode === "edit"}
            >
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {customFieldTypeValues.map((t) => (
                  <SelectItem key={t} value={t}>
                    {TYPE_LABEL[t]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {isSelectType(type) ? (
            <div>
              <Label className="mb-1.5 text-[11px] text-muted-foreground">Options</Label>
              <div className="flex flex-col gap-1.5">
                {options.map((opt) => (
                  <div key={opt.id} className="flex items-center gap-1.5">
                    <Select value={opt.color} onValueChange={(v) => updateOption(opt.id, { color: v ?? opt.color })}>
                      <SelectTrigger className="w-[52px] justify-center px-2">
                        <span className={cn("size-3 rounded-full", fieldColorDotClass(opt.color))} />
                      </SelectTrigger>
                      <SelectContent>
                        {fieldColorValues.map((c) => (
                          <SelectItem key={c} value={c}>
                            <span className={cn("size-3 rounded-full", fieldColorDotClass(c))} />
                            {c}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <Input
                      value={opt.name}
                      onChange={(e) => updateOption(opt.id, { name: e.target.value })}
                      placeholder="Option name"
                      className="flex-1"
                    />
                    <button
                      type="button"
                      onClick={() => removeOption(opt.id)}
                      className="text-muted-foreground transition-colors hover:text-destructive"
                    >
                      <Trash2 className="size-3.5" />
                      <span className="sr-only">Remove option</span>
                    </button>
                  </div>
                ))}
              </div>
              <button
                type="button"
                onClick={addOption}
                className="mt-1.5 flex items-center gap-1 text-xs text-muted-foreground transition-colors hover:text-foreground"
              >
                <Plus className="size-3.5" />
                Add option
              </button>
            </div>
          ) : null}

          {type === "iteration" ? (
            <div>
              <Label className="mb-1.5 text-[11px] text-muted-foreground">Sprints</Label>
              <div className="flex flex-col gap-1.5">
                {iterations.map((it) => (
                  <div key={it.id} className="flex items-center gap-1.5">
                    <Input
                      value={it.title}
                      onChange={(e) => updateIteration(it.id, { title: e.target.value })}
                      placeholder="Sprint name"
                      className="flex-1"
                    />
                    <Input
                      type="date"
                      value={it.startDate}
                      onChange={(e) => updateIteration(it.id, { startDate: e.target.value })}
                      className="w-[132px]"
                    />
                    <Input
                      type="number"
                      min={1}
                      value={it.durationDays}
                      onChange={(e) => updateIteration(it.id, { durationDays: Number(e.target.value) || 1 })}
                      className="w-[60px]"
                      title="Duration (days)"
                    />
                    <button
                      type="button"
                      onClick={() => removeIteration(it.id)}
                      className="text-muted-foreground transition-colors hover:text-destructive"
                    >
                      <Trash2 className="size-3.5" />
                      <span className="sr-only">Remove sprint</span>
                    </button>
                  </div>
                ))}
              </div>
              <button
                type="button"
                onClick={addIteration}
                className="mt-1.5 flex items-center gap-1 text-xs text-muted-foreground transition-colors hover:text-foreground"
              >
                <Plus className="size-3.5" />
                Add sprint
              </button>
            </div>
          ) : null}
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => handleOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={pending || !name.trim()}>
            {pending ? "Saving…" : mode === "create" ? "Create field" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
