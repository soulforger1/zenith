"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ChevronsLeft, ChevronsRight, Plus, Search } from "lucide-react";

import { cn } from "@/lib/utils";
import { ThemeToggle } from "@/components/layout/theme-toggle";
import { ZenithMark } from "@/components/icons/zenith-mark";

type SidebarSpace = { id: string; name: string; slug: string; count: number };

const COLLAPSED_STORAGE_KEY = "zenith:sidebar-collapsed";

export function AppSidebar({
  spaces,
  onPasteTask,
  onSearch,
}: {
  spaces: SidebarSpace[];
  onPasteTask: () => void;
  onSearch: () => void;
}) {
  const pathname = usePathname();

  // Starts expanded on every render (server and first client paint) so
  // hydration always matches, then flips from localStorage right after
  // mount — same tradeoff next-themes documents for its own persisted
  // state: one brief collapse animation on load instead of a hydration
  // mismatch. See theme-toggle.tsx for the analogous "mounted" pattern.
  const [collapsed, setCollapsed] = useState(false);

  useEffect(() => {
    if (localStorage.getItem(COLLAPSED_STORAGE_KEY) === "1") {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setCollapsed(true);
    }
  }, []);

  function toggleCollapsed() {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem(COLLAPSED_STORAGE_KEY, next ? "1" : "0");
      return next;
    });
  }

  return (
    <aside
      className={cn(
        "flex h-screen shrink-0 flex-col overflow-hidden border-r border-sidebar-border bg-sidebar p-4 text-sidebar-foreground transition-[width] duration-200 ease-in-out",
        collapsed ? "w-[68px]" : "w-[260px]",
      )}
    >
      {/* Reserves space for (and lets you drag the window by) the macOS
          traffic-light buttons, which electron/main.js repositions to float
          over this corner now that the native title bar is hidden. */}
      <div className="app-drag-region h-6 shrink-0" />

      <div className={cn("mb-[22px] flex items-center gap-2", collapsed ? "flex-col" : "justify-between px-1")}>
        <Link href="/spaces" className="flex items-center gap-2">
          <span className="flex size-[26px] shrink-0 items-center justify-center rounded-[7px] bg-primary/15 text-primary">
            <ZenithMark className="size-4" />
          </span>
          {!collapsed && <span className="font-mono text-base font-semibold tracking-tight">zenith</span>}
        </Link>
        <button
          type="button"
          onClick={toggleCollapsed}
          aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          className="shrink-0 text-muted-foreground transition-colors hover:text-foreground"
        >
          {collapsed ? <ChevronsRight className="size-4" /> : <ChevronsLeft className="size-4" />}
        </button>
      </div>

      <button
        type="button"
        onClick={onPasteTask}
        title={collapsed ? "Paste task (C)" : undefined}
        className={cn(
          "mb-[22px] flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/15 text-sm font-semibold text-primary transition-colors hover:bg-primary/25",
          collapsed ? "justify-center py-2.5" : "px-3 py-2.5",
        )}
      >
        <span className="text-[15px] leading-none">✦</span>
        {!collapsed && (
          <>
            <span className="whitespace-nowrap">Paste task</span>
            <span className="ml-auto rounded border border-current px-[5px] py-px font-mono text-[10px] opacity-70">
              C
            </span>
          </>
        )}
      </button>

      {!collapsed && (
        <div className="mb-2 flex items-center justify-between px-1">
          <span className="font-mono text-[11px] font-semibold tracking-[0.08em] text-muted-foreground">
            SPACES
          </span>
          <Link
            href="/spaces/new"
            className="text-muted-foreground hover:text-foreground"
            aria-label="New space"
          >
            <Plus className="size-[15px]" />
          </Link>
        </div>
      )}

      <nav className="mb-5 flex min-h-0 flex-col gap-0.5 overflow-y-auto">
        {spaces.length === 0 ? (
          !collapsed && <p className="px-2.5 py-1.5 text-[13.5px] text-muted-foreground">No spaces yet.</p>
        ) : (
          spaces.map((space) => {
            const href = `/spaces/${space.slug}`;
            const active = pathname.startsWith(href);
            return (
              <Link
                key={space.id}
                href={href}
                title={collapsed ? space.name : undefined}
                className={cn(
                  "flex items-center rounded-[7px] text-[13.5px] font-medium transition-colors",
                  collapsed ? "justify-center py-2" : "justify-between gap-2 px-2.5 py-2",
                  active
                    ? "bg-sidebar-accent text-sidebar-accent-foreground"
                    : "text-muted-foreground hover:bg-sidebar-accent/60",
                )}
              >
                {collapsed ? (
                  <span className="flex size-6 items-center justify-center rounded-[6px] bg-sidebar-accent/60 text-[11px] font-semibold uppercase">
                    {space.name.slice(0, 1)}
                  </span>
                ) : (
                  <>
                    <span className="truncate">{space.name}</span>
                    <span className="font-mono text-[11px] text-muted-foreground">{space.count}</span>
                  </>
                )}
              </Link>
            );
          })
        )}
      </nav>

      <div className={cn("mt-auto flex shrink-0 flex-col gap-2.5", collapsed && "items-center")}>
        <button
          type="button"
          onClick={onSearch}
          title={collapsed ? "Search & commands (⌘K)" : undefined}
          className={cn(
            "flex items-center rounded-[7px] border border-sidebar-border text-[12.5px] text-muted-foreground transition-colors hover:border-ring/40",
            collapsed ? "justify-center p-2" : "justify-between gap-2 px-2.5 py-2",
          )}
        >
          <span className="flex items-center gap-1.5">
            <Search className="size-3.5" />
            {!collapsed && "Search & commands"}
          </span>
          {!collapsed && <span className="rounded border border-border px-[5px] py-px font-mono text-[10.5px]">⌘K</span>}
        </button>
        <div className={cn("flex items-center", collapsed ? "flex-col gap-2" : "justify-between px-0.5")}>
          <div className="flex items-center gap-2">
            <span className="flex size-[22px] shrink-0 items-center justify-center rounded-full bg-muted text-[11px] font-semibold">
              G
            </span>
            {!collapsed && <span className="text-[12.5px] text-muted-foreground">grind</span>}
          </div>
          <div className="flex items-center gap-0.5">
            <ThemeToggle />
          </div>
        </div>
      </div>
    </aside>
  );
}
