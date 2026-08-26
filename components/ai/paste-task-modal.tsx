"use client";

import { useRef, useState, type ClipboardEvent } from "react";
import { useRouter } from "next/navigation";
import { Paperclip, X } from "lucide-react";
import { toast } from "sonner";

import { createIssueFromDraftAction, createIssuesFromDraftsAction } from "@/lib/actions/issues";
import { issuePriorityValues, type FieldOption, type IterationOption, type IssuePriority } from "@/lib/db/schema";
import { PRIORITY_LABEL } from "@/lib/priority";
import { normalizeOptions, type FieldDef } from "@/lib/fields/registry";
import type { SidebarSpace } from "@/components/layout/app-shell";
import { FieldValueInput } from "@/components/fields/field-value-input";
import { RepoPicker } from "@/components/fields/repo-picker";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

type Mode = "single" | "list";

type Draft = {
  title: string;
  description: string;
  priority: IssuePriority;
  tags: string[];
  tagText: string;
  branch: string;
  estimate: string;
  dueDate: string;
  repoIds: string[];
  milestoneId: string;
  customFieldValues: Record<string, unknown>;
};

type ListDraft = {
  title: string;
  description: string;
  priority: IssuePriority;
  tags: string[];
  branch: string;
  estimate: string;
  dueDate: string;
  repoIds: string[];
  milestoneId: string;
  customFieldValues: Record<string, unknown>;
  include: boolean;
};

type RepoOption = { id: string; name: string };
type MilestoneOption = { id: string; title: string };
type CustomFieldOption = { id: string; name: string; type: string; options: FieldOption[] | IterationOption[] };

function toFieldDef(field: CustomFieldOption): FieldDef {
  return {
    id: field.id,
    name: field.name,
    type: field.type as FieldDef["type"],
    isBuiltIn: false,
    options: normalizeOptions(field.options),
    getValue: () => undefined,
  };
}

type ParsedTaskResponse = {
  title: string;
  description?: string;
  priority: IssuePriority;
  tags?: string[];
  branch?: string;
  estimate?: string;
  dueDate?: string;
  repoIds?: string[];
  milestoneId?: string | null;
  customFieldValues?: Record<string, unknown>;
};

type Attachment = { file: File; previewUrl: string };

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      resolve(result.split(",")[1] ?? "");
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

export function PasteTaskModal({
  open,
  onOpenChange,
  spaces,
  activeSpaceSlug,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  spaces: SidebarSpace[];
  activeSpaceSlug: string | null;
}) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("single");
  const [text, setText] = useState("");
  const [attachment, setAttachment] = useState<Attachment | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [listDrafts, setListDrafts] = useState<ListDraft[] | null>(null);
  const [repos, setRepos] = useState<RepoOption[]>([]);
  const [milestones, setMilestones] = useState<MilestoneOption[]>([]);
  const [customFields, setCustomFields] = useState<CustomFieldOption[]>([]);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const targetSpace = spaces.find((s) => s.slug === activeSpaceSlug) ?? spaces[0] ?? null;

  function reset() {
    setText("");
    setAttachment(null);
    setDraft(null);
    setListDrafts(null);
    setRepos([]);
    setMilestones([]);
    setCustomFields([]);
    setError(null);
    setPending(false);
  }

  function handleOpenChange(next: boolean) {
    if (!next) reset();
    onOpenChange(next);
  }

  function switchMode(next: Mode) {
    if (next === mode) return;
    setMode(next);
    setText("");
    setAttachment(null);
    setDraft(null);
    setListDrafts(null);
    setRepos([]);
    setMilestones([]);
    setCustomFields([]);
    setError(null);
  }

  function setImageFile(file: File | undefined) {
    if (!file || !file.type.startsWith("image/")) return;
    setAttachment({ file, previewUrl: URL.createObjectURL(file) });
  }

  function handlePaste(e: ClipboardEvent<HTMLTextAreaElement>) {
    const item = Array.from(e.clipboardData.items).find((i) => i.type.startsWith("image/"));
    const file = item?.getAsFile();
    if (file) setImageFile(file);
  }

  async function handleParse() {
    setPending(true);
    setError(null);
    try {
      const attachedImage = attachment
        ? { mimeType: attachment.file.type, data: await fileToBase64(attachment.file) }
        : undefined;
      const res = await fetch("/api/ai/parse-task", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, spaceId: targetSpace?.id, attachedImage }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Couldn't parse that.");
      setRepos(data.repos ?? []);
      setMilestones(data.milestones ?? []);
      const newFieldNames: string[] = (data.customFields ?? [])
        .filter((f: CustomFieldOption) => !customFields.some((existing) => existing.id === f.id))
        .map((f: CustomFieldOption) => f.name);
      setCustomFields(data.customFields ?? []);
      if (newFieldNames.length > 0) {
        toast.success(`Created field${newFieldNames.length === 1 ? "" : "s"}: ${newFieldNames.join(", ")}`);
      }
      setDraft({
        title: data.task.title,
        description: data.task.description ?? "",
        priority: data.task.priority,
        tags: data.task.tags ?? [],
        tagText: (data.task.tags ?? []).join(", "),
        branch: data.task.branch ?? "",
        estimate: data.task.estimate ?? "",
        dueDate: data.task.dueDate ?? "",
        repoIds: data.task.repoIds ?? [],
        milestoneId: data.task.milestoneId ?? "",
        customFieldValues: data.task.customFieldValues ?? {},
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't parse that.");
    } finally {
      setPending(false);
    }
  }

  async function handleParseList() {
    setPending(true);
    setError(null);
    try {
      const res = await fetch("/api/ai/parse-tasks", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, spaceId: targetSpace?.id }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Couldn't parse that.");
      setRepos(data.repos ?? []);
      setMilestones(data.milestones ?? []);
      setCustomFields(data.customFields ?? []);
      setListDrafts(
        (data.tasks as ParsedTaskResponse[]).map((task) => ({
          title: task.title,
          description: task.description ?? "",
          priority: task.priority,
          tags: task.tags ?? [],
          branch: task.branch ?? "",
          estimate: task.estimate ?? "",
          dueDate: task.dueDate ?? "",
          repoIds: task.repoIds ?? [],
          milestoneId: task.milestoneId ?? "",
          customFieldValues: task.customFieldValues ?? {},
          include: true,
        })),
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't parse that.");
    } finally {
      setPending(false);
    }
  }

  async function handleCommit() {
    if (!draft || !targetSpace) return;
    setPending(true);
    try {
      await createIssueFromDraftAction(targetSpace.id, targetSpace.slug, {
        title: draft.title,
        description: draft.description || undefined,
        priority: draft.priority,
        tags: draft.tagText.split(",").map((t) => t.trim()).filter(Boolean),
        branch: draft.branch || undefined,
        estimate: draft.estimate || undefined,
        dueDate: draft.dueDate || undefined,
        repoIds: draft.repoIds,
        milestoneId: draft.milestoneId || undefined,
        customFieldValues: draft.customFieldValues,
      });
      toast.success("Added to Backlog");
      handleOpenChange(false);
      router.refresh();
    } catch {
      toast.error("Couldn't add that task.");
    } finally {
      setPending(false);
    }
  }

  function updateListDraft(index: number, patch: Partial<ListDraft>) {
    setListDrafts((prev) => (prev ? prev.map((d, i) => (i === index ? { ...d, ...patch } : d)) : prev));
  }

  function removeListDraft(index: number) {
    setListDrafts((prev) => (prev ? prev.filter((_, i) => i !== index) : prev));
  }

  const includedCount = listDrafts?.filter((d) => d.include && d.title.trim()).length ?? 0;

  async function handleCommitList() {
    if (!listDrafts || !targetSpace) return;
    const included = listDrafts.filter((d) => d.include && d.title.trim());
    if (included.length === 0) return;
    setPending(true);
    try {
      await createIssuesFromDraftsAction(
        targetSpace.id,
        targetSpace.slug,
        included.map((d) => ({
          title: d.title,
          description: d.description || undefined,
          priority: d.priority,
          tags: d.tags,
          branch: d.branch || undefined,
          estimate: d.estimate || undefined,
          dueDate: d.dueDate || undefined,
          repoIds: d.repoIds,
          milestoneId: d.milestoneId || undefined,
          customFieldValues: d.customFieldValues,
        })),
      );
      toast.success(`Added ${included.length} task${included.length === 1 ? "" : "s"} to Backlog`);
      handleOpenChange(false);
      router.refresh();
    } catch {
      toast.error("Couldn't add those tasks.");
    } finally {
      setPending(false);
    }
  }

  const inputPhase = !draft && !listDrafts;

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className={mode === "list" ? "sm:max-w-[640px]" : "sm:max-w-[560px]"}>
        <DialogHeader>
          <DialogTitle>Paste from manager</DialogTitle>
          {inputPhase ? (
            <DialogDescription>
              {mode === "single"
                ? "Drop the raw message (and/or paste or attach a screenshot) — I'll pull out a title, priority, tags, branch, estimate and due date."
                : "Paste a whole list — one task per line or bullet — and I'll turn each into a task."}
            </DialogDescription>
          ) : null}
        </DialogHeader>

        {inputPhase ? (
          <Tabs value={mode} onValueChange={(v) => switchMode(v as Mode)}>
            <TabsList>
              <TabsTrigger value="single">Single task</TabsTrigger>
              <TabsTrigger value="list">List</TabsTrigger>
            </TabsList>
          </Tabs>
        ) : null}

        {mode === "single" ? (
          !draft ? (
            <>
              <Textarea
                value={text}
                onChange={(e) => setText(e.target.value)}
                onPaste={handlePaste}
                placeholder="e.g. Hey, ASAP fix the checkout 500 error, #bug #payments, should be ~2h, need it by Friday. Branch off fix/checkout-500. (You can also paste a screenshot here.)"
                rows={7}
                className="resize-y"
              />

              {attachment ? (
                <div className="relative inline-block w-fit">
                  {/* eslint-disable-next-line @next/next/no-img-element -- ephemeral object URL preview */}
                  <img
                    src={attachment.previewUrl}
                    alt="Attached screenshot"
                    className="h-20 rounded-md border object-cover"
                  />
                  <button
                    type="button"
                    onClick={() => setAttachment(null)}
                    className="absolute -top-1.5 -right-1.5 flex size-5 items-center justify-center rounded-full bg-foreground text-background"
                  >
                    <X className="size-3" />
                    <span className="sr-only">Remove attachment</span>
                  </button>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  className="flex w-fit items-center gap-1.5 text-xs text-muted-foreground transition-colors hover:text-foreground"
                >
                  <Paperclip className="size-3.5" />
                  Attach screenshot
                </button>
              )}
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => {
                  setImageFile(e.target.files?.[0]);
                  e.target.value = "";
                }}
              />

              {error ? <p className="text-sm text-destructive">{error}</p> : null}
              <DialogFooter>
                <Button variant="ghost" onClick={() => handleOpenChange(false)}>
                  Cancel
                </Button>
                <Button
                  onClick={handleParse}
                  disabled={pending || (text.trim().length < 3 && !attachment)}
                >
                  {pending ? "Parsing…" : "Parse ✦"}
                </Button>
              </DialogFooter>
            </>
          ) : (
            <>
              <div className="space-y-3">
                <div>
                  <Label className="mb-1.5 text-[11px] text-muted-foreground">Title</Label>
                  <Input
                    value={draft.title}
                    onChange={(e) => setDraft({ ...draft, title: e.target.value })}
                  />
                </div>
                <div>
                  <Label className="mb-1.5 text-[11px] text-muted-foreground">Description</Label>
                  <Textarea
                    value={draft.description}
                    onChange={(e) => setDraft({ ...draft, description: e.target.value })}
                    rows={3}
                    className="resize-y text-sm"
                  />
                </div>
                <div className="grid grid-cols-2 gap-2.5">
                  <div>
                    <Label className="mb-1.5 text-[11px] text-muted-foreground">Priority</Label>
                    <Select
                      value={draft.priority}
                      onValueChange={(v) => setDraft({ ...draft, priority: (v ?? "medium") as IssuePriority })}
                    >
                      <SelectTrigger className="w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {issuePriorityValues.map((p) => (
                          <SelectItem key={p} value={p}>
                            {PRIORITY_LABEL[p]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div>
                    <Label className="mb-1.5 text-[11px] text-muted-foreground">Estimate</Label>
                    <Input
                      value={draft.estimate}
                      onChange={(e) => setDraft({ ...draft, estimate: e.target.value })}
                    />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-2.5">
                  <div>
                    <Label className="mb-1.5 text-[11px] text-muted-foreground">Branch</Label>
                    <Input
                      value={draft.branch}
                      onChange={(e) => setDraft({ ...draft, branch: e.target.value })}
                      className="font-mono text-branch"
                    />
                  </div>
                  <div>
                    <Label className="mb-1.5 text-[11px] text-muted-foreground">Due</Label>
                    <Input
                      type="date"
                      value={draft.dueDate}
                      onChange={(e) => setDraft({ ...draft, dueDate: e.target.value })}
                    />
                  </div>
                </div>
                {repos.length > 0 || milestones.length > 0 ? (
                  <div
                    className={
                      repos.length > 0 && milestones.length > 0 ? "grid grid-cols-2 gap-2.5" : ""
                    }
                  >
                    {repos.length > 0 ? (
                      <div>
                        <Label className="mb-1.5 text-[11px] text-muted-foreground">Repo</Label>
                        <RepoPicker
                          repos={repos}
                          value={draft.repoIds}
                          onChange={(next) => setDraft({ ...draft, repoIds: next })}
                        />
                      </div>
                    ) : null}
                    {milestones.length > 0 ? (
                      <div>
                        <Label className="mb-1.5 text-[11px] text-muted-foreground">Milestone</Label>
                        <Select
                          value={draft.milestoneId}
                          onValueChange={(v) => setDraft({ ...draft, milestoneId: v ?? "" })}
                        >
                          <SelectTrigger className="w-full">
                            <SelectValue placeholder="None" />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="">None</SelectItem>
                            {milestones.map((m) => (
                              <SelectItem key={m.id} value={m.id}>
                                {m.title}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    ) : null}
                  </div>
                ) : null}
                <div>
                  <Label className="mb-1.5 text-[11px] text-muted-foreground">Tags</Label>
                  <Input
                    value={draft.tagText}
                    onChange={(e) => setDraft({ ...draft, tagText: e.target.value })}
                  />
                </div>
                {customFields.length > 0 ? (
                  <div className="space-y-2.5 border-t pt-2.5">
                    {customFields.map((field) => (
                      <div key={field.id}>
                        <Label className="mb-1.5 text-[11px] text-muted-foreground">{field.name}</Label>
                        <FieldValueInput
                          field={toFieldDef(field)}
                          value={draft.customFieldValues[field.id]}
                          onChange={(value) =>
                            setDraft({ ...draft, customFieldValues: { ...draft.customFieldValues, [field.id]: value } })
                          }
                        />
                      </div>
                    ))}
                  </div>
                ) : null}
                {!targetSpace ? (
                  <p className="text-sm text-destructive">Create a space first.</p>
                ) : null}
              </div>
              <DialogFooter>
                <Button variant="ghost" onClick={() => setDraft(null)}>
                  Back
                </Button>
                <Button onClick={handleCommit} disabled={pending || !targetSpace}>
                  {pending ? "Adding…" : "Add to Backlog"}
                </Button>
              </DialogFooter>
            </>
          )
        ) : !listDrafts ? (
          <>
            <Textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder={"e.g.\n- Fix checkout 500 error, ASAP\n- Update onboarding docs by Friday\n- Refactor auth module, ~1d, no rush"}
              rows={9}
              className="resize-y"
            />

            {error ? <p className="text-sm text-destructive">{error}</p> : null}
            <DialogFooter>
              <Button variant="ghost" onClick={() => handleOpenChange(false)}>
                Cancel
              </Button>
              <Button onClick={handleParseList} disabled={pending || text.trim().length < 3}>
                {pending ? "Parsing…" : "Parse ✦"}
              </Button>
            </DialogFooter>
          </>
        ) : (
          <>
            <div className="max-h-[360px] space-y-2 overflow-y-auto">
              {listDrafts.map((d, i) => (
                <div key={i} className="flex flex-col gap-1">
                  <div className="flex items-center gap-2">
                    <Checkbox
                      checked={d.include}
                      onCheckedChange={(checked) => updateListDraft(i, { include: checked })}
                    />
                    <Input
                      value={d.title}
                      onChange={(e) => updateListDraft(i, { title: e.target.value })}
                      className="flex-1"
                    />
                    <Select
                      value={d.priority}
                      onValueChange={(v) => updateListDraft(i, { priority: (v ?? "medium") as IssuePriority })}
                    >
                      <SelectTrigger className="w-[110px] shrink-0">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {issuePriorityValues.map((p) => (
                          <SelectItem key={p} value={p}>
                            {PRIORITY_LABEL[p]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    {repos.length > 0 ? (
                      <div className="w-[100px] shrink-0">
                        <RepoPicker
                          repos={repos}
                          value={d.repoIds}
                          onChange={(next) => updateListDraft(i, { repoIds: next })}
                        />
                      </div>
                    ) : null}
                    {milestones.length > 0 ? (
                      <Select
                        value={d.milestoneId}
                        onValueChange={(v) => updateListDraft(i, { milestoneId: v ?? "" })}
                      >
                        <SelectTrigger className="w-[100px] shrink-0">
                          <SelectValue placeholder="None" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="">None</SelectItem>
                          {milestones.map((m) => (
                            <SelectItem key={m.id} value={m.id}>
                              {m.title}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    ) : null}
                    {Object.keys(d.customFieldValues).length > 0 ? (
                      <span
                        title="Edit custom fields after creating this task"
                        className="shrink-0 rounded-[5px] bg-muted px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground"
                      >
                        +{Object.keys(d.customFieldValues).length} field
                        {Object.keys(d.customFieldValues).length === 1 ? "" : "s"}
                      </span>
                    ) : null}
                    <button
                      type="button"
                      onClick={() => removeListDraft(i)}
                      className="flex size-6 shrink-0 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                    >
                      <X className="size-3.5" />
                      <span className="sr-only">Remove</span>
                    </button>
                  </div>
                  <Input
                    value={d.description}
                    onChange={(e) => updateListDraft(i, { description: e.target.value })}
                    placeholder="Description (optional)"
                    className="ml-6 h-7 flex-1 text-xs text-muted-foreground"
                  />
                </div>
              ))}
              {listDrafts.length === 0 ? (
                <p className="text-sm text-muted-foreground">Nothing left — go back and paste a list.</p>
              ) : null}
            </div>
            {!targetSpace ? <p className="text-sm text-destructive">Create a space first.</p> : null}
            <DialogFooter>
              <Button variant="ghost" onClick={() => setListDrafts(null)}>
                Back
              </Button>
              <Button onClick={handleCommitList} disabled={pending || !targetSpace || includedCount === 0}>
                {pending ? "Adding…" : `Create ${includedCount} task${includedCount === 1 ? "" : "s"}`}
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
