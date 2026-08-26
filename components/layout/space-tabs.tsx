"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { MoreHorizontal, Plus, Search } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { useAppShell } from "@/components/layout/app-shell-context";
import {
  createViewAction,
  deleteViewAction,
  duplicateViewAction,
  renameViewAction,
  setDefaultViewAction,
} from "@/lib/actions/views";
import { viewTypeValues, type ViewType } from "@/lib/db/schema";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const VIEW_TYPE_LABEL: Record<ViewType, string> = { table: "Table", board: "Board", roadmap: "Roadmap" };

export type SpaceView = { id: string; name: string; type: ViewType };

export function SpaceHeader({
  spaceId,
  spaceName,
  slug,
  views,
}: {
  spaceId: string;
  spaceName: string;
  slug: string;
  views: SpaceView[];
}) {
  const pathname = usePathname();
  const { openCommandPalette } = useAppShell();

  const fixedTabs = [
    { href: `/spaces/${slug}/milestones`, label: "Milestones" },
    { href: `/spaces/${slug}/settings`, label: "Settings" },
  ];

  return (
    <div className="border-b px-8 pt-[26px]">
      <div className="mb-4 flex items-center justify-between">
        <h1 className="text-[22px] font-semibold tracking-tight">{spaceName}</h1>
        <button
          type="button"
          onClick={openCommandPalette}
          className="flex items-center gap-1.5 text-[12.5px] text-muted-foreground transition-colors hover:text-foreground"
        >
          <Search className="size-3.5" />
          Search tasks
        </button>
      </div>
      <div className="flex items-center justify-between gap-4">
        <div className="flex min-w-0 flex-1 items-center gap-4 overflow-x-auto">
          {views.map((view) => {
            const href = `/spaces/${slug}/views/${view.id}`;
            const active = pathname === href;
            return (
              <div
                key={view.id}
                className={cn(
                  "group flex shrink-0 items-center gap-1 border-b-2 pb-[11px]",
                  active ? "border-primary" : "border-transparent",
                )}
              >
                <Link
                  href={href}
                  className={cn(
                    "text-sm font-medium whitespace-nowrap transition-colors",
                    active ? "text-foreground" : "text-muted-foreground hover:text-foreground",
                  )}
                >
                  {view.name}
                </Link>
                <ViewTabMenu view={view} spaceSlug={slug} disableDelete={views.length <= 1} />
              </div>
            );
          })}
          <NewViewButton spaceId={spaceId} spaceSlug={slug} />
        </div>
        <div className="flex shrink-0 gap-6">
          {fixedTabs.map((tab) => {
            const active = pathname.startsWith(tab.href);
            return (
              <Link
                key={tab.href}
                href={tab.href}
                className={cn(
                  "border-b-2 pb-[11px] text-sm font-medium whitespace-nowrap transition-colors",
                  active
                    ? "border-primary text-foreground"
                    : "border-transparent text-muted-foreground hover:text-foreground",
                )}
              >
                {tab.label}
              </Link>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function ViewTabMenu({
  view,
  spaceSlug,
  disableDelete,
}: {
  view: SpaceView;
  spaceSlug: string;
  disableDelete: boolean;
}) {
  const [renameOpen, setRenameOpen] = useState(false);
  const [name, setName] = useState(view.name);
  const [pending, startTransition] = useTransition();

  function handleRenameSave() {
    const trimmed = name.trim();
    if (!trimmed) return;
    startTransition(() => {
      renameViewAction(view.id, spaceSlug, trimmed).then((result) => {
        if (result?.error) {
          toast.error(result.error);
          return;
        }
        setRenameOpen(false);
      });
    });
  }

  function handleDuplicate() {
    startTransition(() => {
      duplicateViewAction(view.id, spaceSlug);
    });
  }

  function handleSetDefault() {
    startTransition(() => {
      setDefaultViewAction(view.id, spaceSlug).catch(() => toast.error("Couldn't set as default."));
    });
  }

  function handleDelete() {
    if (!window.confirm(`Delete the "${view.name}" view?`)) return;
    startTransition(() => {
      deleteViewAction(view.id, spaceSlug).then((result) => {
        if (result?.error) toast.error(result.error);
      });
    });
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <button
              type="button"
              className="text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 data-popup-open:opacity-100 hover:text-foreground"
            />
          }
        >
          <MoreHorizontal className="size-3.5" />
          <span className="sr-only">View options for {view.name}</span>
        </DropdownMenuTrigger>
        <DropdownMenuContent>
          <DropdownMenuItem onClick={() => setRenameOpen(true)}>Rename</DropdownMenuItem>
          <DropdownMenuItem onClick={handleDuplicate}>Duplicate</DropdownMenuItem>
          <DropdownMenuItem onClick={handleSetDefault}>Set as default</DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem variant="destructive" disabled={disableDelete} onClick={handleDelete}>
            Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <Dialog open={renameOpen} onOpenChange={setRenameOpen}>
        <DialogContent className="sm:max-w-[360px]">
          <DialogHeader>
            <DialogTitle>Rename view</DialogTitle>
          </DialogHeader>
          <Input value={name} onChange={(e) => setName(e.target.value)} autoFocus />
          <DialogFooter>
            <Button variant="ghost" onClick={() => setRenameOpen(false)}>
              Cancel
            </Button>
            <Button onClick={handleRenameSave} disabled={pending || !name.trim()}>
              Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function NewViewButton({ spaceId, spaceSlug }: { spaceId: string; spaceSlug: string }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [type, setType] = useState<ViewType>("table");
  const [pending, startTransition] = useTransition();

  function handleCreate() {
    const trimmed = name.trim();
    if (!trimmed) return;
    startTransition(() => {
      createViewAction(spaceId, spaceSlug, { name: trimmed, type }).catch(() => {
        toast.error("Couldn't create that view.");
      });
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={
          <button
            type="button"
            className="shrink-0 pb-[11px] text-muted-foreground transition-colors hover:text-foreground"
          />
        }
      >
        <Plus className="size-4" />
        <span className="sr-only">New view</span>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[360px]">
        <DialogHeader>
          <DialogTitle>New view</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label className="mb-1.5 text-[11px] text-muted-foreground">Name</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Sprint board" autoFocus />
          </div>
          <div>
            <Label className="mb-1.5 text-[11px] text-muted-foreground">Type</Label>
            <Select value={type} onValueChange={(v) => setType((v ?? "table") as ViewType)}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {viewTypeValues.map((t) => (
                  <SelectItem key={t} value={t}>
                    {VIEW_TYPE_LABEL[t]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)}>
            Cancel
          </Button>
          <Button onClick={handleCreate} disabled={pending || !name.trim()}>
            {pending ? "Creating…" : "Create view"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
