"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight, Diamond, Keyboard, Sparkles } from "lucide-react";

import { cn } from "@/lib/utils";
import type { SidebarSpace } from "@/components/layout/app-shell";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";

// Table/Board/Roadmap are now dynamic, user-named views per space (no fixed
// route to jump to) — only Milestones/Settings stay as static routes here.
const VIEWS = [
  { key: "milestones", label: "Milestones" },
  { key: "settings", label: "Settings" },
];

export function CommandPalette({
  open,
  onOpenChange,
  spaces,
  activeSpaceSlug,
  onOpenAiModal,
  onOpenShortcuts,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  spaces: SidebarSpace[];
  activeSpaceSlug: string | null;
  onOpenAiModal: () => void;
  onOpenShortcuts: () => void;
}) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);

  const commands = useMemo(() => {
    const items: { id: string; icon: React.ReactNode; label: string; hint: string; onSelect: () => void }[] = [];

    if (activeSpaceSlug) {
      for (const view of VIEWS) {
        items.push({
          id: `view-${view.key}`,
          icon: <ArrowRight className="size-3.5" />,
          label: `Go to ${view.label}`,
          hint: "view",
          onSelect: () => router.push(`/spaces/${activeSpaceSlug}/${view.key}`),
        });
      }
    }
    for (const space of spaces) {
      items.push({
        id: `space-${space.id}`,
        icon: <Diamond className="size-3.5" />,
        label: `Switch to ${space.name}`,
        hint: "space",
        onSelect: () => router.push(`/spaces/${space.slug}`),
      });
    }
    items.push({
      id: "paste-task",
      icon: <Sparkles className="size-3.5" />,
      label: "Paste from manager…",
      hint: "C",
      onSelect: onOpenAiModal,
    });
    items.push({
      id: "shortcuts",
      icon: <Keyboard className="size-3.5" />,
      label: "Show keyboard shortcuts",
      hint: "?",
      onSelect: onOpenShortcuts,
    });
    return items;
  }, [activeSpaceSlug, spaces, router, onOpenAiModal, onOpenShortcuts]);

  const filtered = commands.filter((c) => c.label.toLowerCase().includes(query.toLowerCase()));

  function select(cmd: (typeof commands)[number]) {
    cmd.onSelect();
    onOpenChange(false);
    setQuery("");
    setSelectedIndex(0);
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (filtered.length === 0) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelectedIndex((i) => (i + 1) % filtered.length);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelectedIndex((i) => (i - 1 + filtered.length) % filtered.length);
    } else if (e.key === "Enter") {
      e.preventDefault();
      select(filtered[selectedIndex]);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        onOpenChange(next);
        if (!next) setQuery("");
        setSelectedIndex(0);
      }}
    >
      <DialogContent
        showCloseButton={false}
        className="top-[110px] max-w-[520px] -translate-x-1/2 -translate-y-0 gap-0 overflow-hidden p-0 sm:max-w-[520px]"
      >
        <Input
          autoFocus
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setSelectedIndex(0);
          }}
          onKeyDown={handleKeyDown}
          placeholder="Type a command or search…"
          className="rounded-none border-x-0 border-t-0 border-b px-4 py-5 text-[14.5px] shadow-none focus-visible:ring-0"
        />
        <div className="max-h-80 overflow-y-auto p-1.5">
          {filtered.map((cmd, i) => (
            <button
              key={cmd.id}
              type="button"
              ref={(el) => {
                if (i === selectedIndex) el?.scrollIntoView({ block: "nearest" });
              }}
              onClick={() => select(cmd)}
              onMouseEnter={() => setSelectedIndex(i)}
              className={cn(
                "flex w-full items-center gap-2.5 rounded-[7px] px-3 py-2.5 text-left text-[13.5px] transition-colors hover:bg-accent",
                i === selectedIndex && "bg-accent/60",
              )}
            >
              <span className="w-5 text-center text-muted-foreground">{cmd.icon}</span>
              <span>{cmd.label}</span>
              <span className="ml-auto text-[11px] text-muted-foreground">{cmd.hint}</span>
            </button>
          ))}
          {filtered.length === 0 ? (
            <p className="px-3 py-4 text-center text-sm text-muted-foreground">No matches.</p>
          ) : null}
        </div>
      </DialogContent>
    </Dialog>
  );
}
