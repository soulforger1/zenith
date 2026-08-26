"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter } from "next/navigation";

import { AppShellContext, type DrawerContext, type DrawerTask } from "@/components/layout/app-shell-context";
import { AppSidebar } from "@/components/layout/app-sidebar";
import { CommandPalette } from "@/components/layout/command-palette";
import { ShortcutsDialog } from "@/components/layout/shortcuts-dialog";
import { TaskDetailDrawer } from "@/components/issues/task-detail-drawer";
import { PasteTaskModal } from "@/components/ai/paste-task-modal";

export type SidebarSpace = { id: string; name: string; slug: string; count: number };

export function AppShell({
  spaces,
  children,
}: {
  spaces: SidebarSpace[];
  children: React.ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();

  const [selected, setSelected] = useState<{ task: DrawerTask; ctx: DrawerContext } | null>(null);
  const [aiModalOpen, setAiModalOpen] = useState(false);
  const [commandPaletteOpen, setCommandPaletteOpen] = useState(false);
  const [shortcutsOpen, setShortcutsOpen] = useState(false);

  const activeSpaceSlug = useMemo(() => {
    const match = /^\/spaces\/([^/]+)/.exec(pathname);
    return match && match[1] !== "new" ? match[1] : null;
  }, [pathname]);

  const openTask = useCallback((task: DrawerTask, ctx: DrawerContext) => {
    setSelected({ task, ctx });
  }, []);
  const closeTask = useCallback(() => setSelected(null), []);
  const openAiModal = useCallback(() => setAiModalOpen(true), []);
  const openCommandPalette = useCallback(() => setCommandPaletteOpen(true), []);
  const openShortcuts = useCallback(() => setShortcutsOpen(true), []);

  const closeAll = useCallback(() => {
    setSelected(null);
    setAiModalOpen(false);
    setCommandPaletteOpen(false);
    setShortcutsOpen(false);
  }, []);

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      const target = e.target as HTMLElement | null;
      const tag = target?.tagName.toLowerCase();
      const typing = tag === "input" || tag === "textarea" || target?.isContentEditable;

      if (typing) {
        if (e.key === "Escape") {
          target?.blur();
          closeAll();
        }
        return;
      }
      if (e.key === "Escape") {
        closeAll();
        return;
      }
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setCommandPaletteOpen(true);
        return;
      }
      if (e.key.toLowerCase() === "c") {
        setAiModalOpen(true);
        return;
      }
      if (e.key === "?") {
        setShortcutsOpen(true);
        return;
      }
      // Views are now dynamic/named per space (List/Board are no longer
      // fixed routes), so number shortcuts only cover the two routes that
      // are still static: Milestones and Settings.
      if (activeSpaceSlug && ["1", "2"].includes(e.key)) {
        const view = { "1": "milestones", "2": "settings" }[e.key];
        router.push(`/spaces/${activeSpaceSlug}/${view}`);
      }
    }
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [activeSpaceSlug, router, closeAll]);

  return (
    <AppShellContext.Provider value={{ openTask, openAiModal, openCommandPalette }}>
      <div className="flex min-h-screen flex-1">
        <AppSidebar
          spaces={spaces}
          onPasteTask={openAiModal}
          onSearch={openCommandPalette}
        />
        <main className="flex-1 overflow-y-auto">{children}</main>
      </div>

      <TaskDetailDrawer
        task={selected?.task ?? null}
        spaceSlug={selected?.ctx.spaceSlug ?? ""}
        milestones={selected?.ctx.milestones ?? []}
        repos={selected?.ctx.repos ?? []}
        registry={selected?.ctx.registry ?? []}
        onClose={closeTask}
      />
      <CommandPalette
        open={commandPaletteOpen}
        onOpenChange={setCommandPaletteOpen}
        spaces={spaces}
        activeSpaceSlug={activeSpaceSlug}
        onOpenAiModal={openAiModal}
        onOpenShortcuts={openShortcuts}
      />
      <PasteTaskModal
        open={aiModalOpen}
        onOpenChange={setAiModalOpen}
        spaces={spaces}
        activeSpaceSlug={activeSpaceSlug}
      />
      <ShortcutsDialog open={shortcutsOpen} onOpenChange={setShortcutsOpen} />
    </AppShellContext.Provider>
  );
}
