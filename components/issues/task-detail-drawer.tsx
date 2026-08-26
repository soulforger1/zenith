"use client";

import { useState, useTransition } from "react";
import { Copy } from "lucide-react";
import { toast } from "sonner";

import { deleteIssueAction, updateIssueFieldsAction } from "@/lib/actions/issues";
import { issuePriorityValues, issueStatusValues, type IssuePriority, type IssueStatus, type Subtask } from "@/lib/db/schema";
import { PRIORITY_LABEL } from "@/lib/priority";
import { buildTaskPrompt } from "@/lib/claude-prompt";
import { buildFieldPatch, type FieldDef } from "@/lib/fields/registry";
import type { DrawerContext, DrawerTask } from "@/components/layout/app-shell-context";
import { FieldValueInput } from "@/components/fields/field-value-input";
import { RepoPicker } from "@/components/fields/repo-picker";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const STATUS_LABEL: Record<IssueStatus, string> = {
  backlog: "Backlog",
  todo: "Todo",
  in_progress: "In Progress",
  done: "Done",
};

export function TaskDetailDrawer({
  task,
  spaceSlug,
  milestones,
  repos,
  registry,
  onClose,
}: {
  task: DrawerTask | null;
  spaceSlug: string;
  milestones: DrawerContext["milestones"];
  repos: DrawerContext["repos"];
  registry: FieldDef[];
  onClose: () => void;
}) {
  return (
    <Sheet open={!!task} onOpenChange={(open) => !open && onClose()}>
      <SheetContent className="gap-0 p-0 sm:max-w-[400px]">
        {task ? (
          <DrawerBody
            key={task.id}
            task={task}
            spaceSlug={spaceSlug}
            milestones={milestones}
            repos={repos}
            registry={registry}
            onClose={onClose}
          />
        ) : null}
      </SheetContent>
    </Sheet>
  );
}

function DrawerBody({
  task,
  spaceSlug,
  milestones,
  repos,
  registry,
  onClose,
}: {
  task: DrawerTask;
  spaceSlug: string;
  milestones: DrawerContext["milestones"];
  repos: DrawerContext["repos"];
  registry: FieldDef[];
  onClose: () => void;
}) {
  const customFields = registry.filter((f) => !f.isBuiltIn);
  const [customValues, setCustomValues] = useState<Record<string, unknown>>(task.customFieldValues);
  const [title, setTitle] = useState(task.title);
  const [description, setDescription] = useState(task.description ?? "");
  const [priority, setPriority] = useState<IssuePriority>(task.priority);
  const [status, setStatus] = useState<IssueStatus>(task.status);
  const [branch, setBranch] = useState(task.branch ?? "");
  const [estimate, setEstimate] = useState(task.estimate ?? "");
  const [due, setDue] = useState(task.dueDate ?? "");
  const [tagText, setTagText] = useState(task.tags.join(", "));
  const [milestoneId, setMilestoneId] = useState(task.milestoneId ?? "");
  const [repoIds, setRepoIds] = useState<string[]>(task.repoIds);
  const [subtasks, setSubtasks] = useState<Subtask[]>(task.subtasks);
  const [subtasksPending, setSubtasksPending] = useState(false);
  const [, startTransition] = useTransition();

  function save(patch: Parameters<typeof updateIssueFieldsAction>[2]) {
    startTransition(() => {
      updateIssueFieldsAction(task.id, spaceSlug, patch).catch(() => {
        toast.error("Couldn't save that change.");
      });
    });
  }

  function saveCustomField(field: FieldDef, value: unknown) {
    setCustomValues((prev) => ({ ...prev, [field.id]: value }));
    save(buildFieldPatch(field, value));
  }

  function toggleSubtask(idx: number) {
    const next = subtasks.map((st, i) => (i === idx ? { ...st, done: !st.done } : st));
    setSubtasks(next);
    save({ subtasks: next });
  }

  async function handleGenerateSubtasks() {
    setSubtasksPending(true);
    try {
      const res = await fetch("/api/ai/generate-subtasks", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title, description: description || undefined }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Couldn't generate subtasks.");
      const generated: Subtask[] = (data.subtasks as string[]).map((text) => ({ text, done: false }));
      const merged = [...subtasks, ...generated];
      setSubtasks(merged);
      save({ subtasks: merged });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Couldn't generate subtasks.");
    } finally {
      setSubtasksPending(false);
    }
  }

  function handleDelete() {
    if (!window.confirm(`Delete "${task.title}"?`)) return;
    startTransition(() => {
      deleteIssueAction(task.id, spaceSlug).catch(() => toast.error("Couldn't delete that task."));
    });
    onClose();
  }

  async function handleCopyPrompt() {
    const prompt = buildTaskPrompt({ title, description, subtasks });
    try {
      await navigator.clipboard.writeText(prompt);
      toast.success("Prompt copied — paste it into Claude to start work.");
    } catch {
      toast.error("Couldn't copy the prompt.");
    }
  }

  return (
    <div className="flex h-full flex-col overflow-y-auto p-6">
      <SheetHeader className="mb-2 p-0">
        <SheetTitle className="sr-only">Task</SheetTitle>
        <div className="flex items-center justify-between">
          <span className="font-mono text-[11px] text-muted-foreground">TASK</span>
          <button
            type="button"
            onClick={handleCopyPrompt}
            className="flex items-center gap-1 text-[11px] text-muted-foreground transition-colors hover:text-foreground"
          >
            <Copy className="size-3" />
            Copy prompt
          </button>
        </div>
      </SheetHeader>

      <Textarea
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        onBlur={() => title.trim() && title !== task.title && save({ title: title.trim() })}
        rows={2}
        className="mb-4 resize-none border-none bg-transparent p-0 text-lg font-semibold shadow-none focus-visible:ring-0"
      />

      <div className="mb-4">
        <Label className="mb-1.5 text-[11px] text-muted-foreground">Description</Label>
        <Textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          onBlur={() => save({ description: description.trim() || null })}
          rows={3}
          placeholder="Add more context…"
          className="text-xs"
        />
      </div>

      <div className="mb-4 grid grid-cols-2 gap-2.5">
        <div>
          <Label className="mb-1.5 text-[11px] text-muted-foreground">Priority</Label>
          <Select
            value={priority}
            onValueChange={(v) => {
              const value = (v ?? "medium") as IssuePriority;
              setPriority(value);
              save({ priority: value });
            }}
          >
            <SelectTrigger className="w-full text-xs">
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
          <Label className="mb-1.5 text-[11px] text-muted-foreground">Status</Label>
          <Select
            value={status}
            onValueChange={(v) => {
              const value = (v ?? "backlog") as IssueStatus;
              setStatus(value);
              save({ status: value });
            }}
          >
            <SelectTrigger className="w-full text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {issueStatusValues.map((s) => (
                <SelectItem key={s} value={s}>
                  {STATUS_LABEL[s]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <div className="mb-4">
        <Label className="mb-1.5 text-[11px] text-muted-foreground">Branch / PR</Label>
        <Input
          value={branch}
          onChange={(e) => setBranch(e.target.value)}
          onBlur={() => save({ branch: branch.trim() || null })}
          placeholder="feature/my-branch"
          className="font-mono text-xs text-branch"
        />
      </div>

      <div className="mb-4 grid grid-cols-2 gap-2.5">
        <div>
          <Label className="mb-1.5 text-[11px] text-muted-foreground">Estimate</Label>
          <Input
            value={estimate}
            onChange={(e) => setEstimate(e.target.value)}
            onBlur={() => save({ estimate: estimate.trim() || null })}
            placeholder="2h"
            className="text-xs"
          />
        </div>
        <div>
          <Label className="mb-1.5 text-[11px] text-muted-foreground">Due</Label>
          <Input
            type="date"
            value={due}
            onChange={(e) => setDue(e.target.value)}
            onBlur={() => save({ dueDate: due || null })}
            className="text-xs"
          />
        </div>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-2.5">
        <div>
          <Label className="mb-1.5 text-[11px] text-muted-foreground">Milestone</Label>
          <Select
            value={milestoneId}
            onValueChange={(v) => {
              const value = v ?? "";
              setMilestoneId(value);
              save({ milestoneId: value || null });
            }}
          >
            <SelectTrigger className="w-full text-xs">
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
        <div>
          <Label className="mb-1.5 text-[11px] text-muted-foreground">Repo</Label>
          <RepoPicker
            repos={repos}
            value={repoIds}
            onChange={(next) => {
              setRepoIds(next);
              save({ repoIds: next });
            }}
          />
        </div>
      </div>

      <div className="mb-4">
        <Label className="mb-1.5 text-[11px] text-muted-foreground">Tags (comma separated)</Label>
        <Input
          value={tagText}
          onChange={(e) => setTagText(e.target.value)}
          onBlur={() =>
            save({ tags: tagText.split(",").map((t) => t.trim()).filter(Boolean) })
          }
          placeholder="frontend, bug"
          className="text-xs"
        />
      </div>

      <div className="mb-5">
        <div className="mb-1.5 flex items-center justify-between">
          <Label className="text-[11px] text-muted-foreground">Subtasks</Label>
          <button
            type="button"
            onClick={handleGenerateSubtasks}
            disabled={subtasksPending}
            className="text-[11px] text-muted-foreground transition-colors hover:text-foreground disabled:opacity-50"
          >
            {subtasksPending ? "Generating…" : "Generate ✦"}
          </button>
        </div>
        <div className="flex flex-col gap-1.5">
          {subtasks.length === 0 ? (
            <p className="text-xs text-muted-foreground">No subtasks.</p>
          ) : (
            subtasks.map((st, idx) => (
              <button
                key={idx}
                type="button"
                onClick={() => toggleSubtask(idx)}
                className="flex items-center gap-2 text-left text-[13px]"
              >
                <span
                  className={
                    "flex size-[15px] shrink-0 items-center justify-center rounded border text-[10px] " +
                    (st.done ? "border-primary bg-primary text-primary-foreground" : "border-input")
                  }
                >
                  {st.done ? "✓" : ""}
                </span>
                <span className={st.done ? "text-muted-foreground line-through" : ""}>{st.text}</span>
              </button>
            ))
          )}
        </div>
      </div>

      {customFields.length > 0 ? (
        <div className="mb-5 space-y-3">
          <Label className="text-[11px] text-muted-foreground">Custom fields</Label>
          {customFields.map((field) => (
            <div key={field.id}>
              <Label className="mb-1.5 text-[11px] text-muted-foreground">{field.name}</Label>
              <FieldValueInput
                field={field}
                value={customValues[field.id]}
                onChange={(value) => saveCustomField(field, value)}
              />
            </div>
          ))}
        </div>
      ) : null}

      <Button
        variant="destructive"
        onClick={handleDelete}
        className="mt-auto w-full justify-center"
      >
        Delete task
      </Button>
    </div>
  );
}
