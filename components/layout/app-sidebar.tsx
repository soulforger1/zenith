"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Plus, Search } from "lucide-react";

import { cn } from "@/lib/utils";
import { logoutAction } from "@/lib/auth/actions";
import { ThemeToggle } from "@/components/layout/theme-toggle";

type SidebarSpace = { id: string; name: string; slug: string; count: number };

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

  return (
    <aside className="flex w-[260px] shrink-0 flex-col border-r border-sidebar-border bg-sidebar p-4 text-sidebar-foreground">
      <Link href="/spaces" className="mb-[22px] flex items-center gap-2 px-1">
        <span className="flex size-[26px] items-center justify-center rounded-[7px] bg-primary/15 font-mono text-sm font-semibold text-primary">
          g
        </span>
        <span className="font-mono text-base font-semibold tracking-tight">grind</span>
      </Link>

      <button
        type="button"
        onClick={onPasteTask}
        className="mb-[22px] flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/15 px-3 py-2.5 text-sm font-semibold text-primary transition-colors hover:bg-primary/25"
      >
        <span className="text-[15px] leading-none">✦</span>
        <span className="whitespace-nowrap">Paste task</span>
        <span className="ml-auto rounded border border-current px-[5px] py-px font-mono text-[10px] opacity-70">
          C
        </span>
      </button>

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

      <nav className="mb-5 flex flex-col gap-0.5 overflow-y-auto">
        {spaces.length === 0 ? (
          <p className="px-2.5 py-1.5 text-[13.5px] text-muted-foreground">No spaces yet.</p>
        ) : (
          spaces.map((space) => {
            const href = `/spaces/${space.slug}`;
            const active = pathname.startsWith(href);
            return (
              <Link
                key={space.id}
                href={href}
                className={cn(
                  "flex items-center justify-between gap-2 rounded-[7px] px-2.5 py-2 text-[13.5px] font-medium transition-colors",
                  active
                    ? "bg-sidebar-accent text-sidebar-accent-foreground"
                    : "text-muted-foreground hover:bg-sidebar-accent/60",
                )}
              >
                <span className="truncate">{space.name}</span>
                <span className="font-mono text-[11px] text-muted-foreground">{space.count}</span>
              </Link>
            );
          })
        )}
      </nav>

      <div className="mt-auto flex flex-col gap-2.5">
        <button
          type="button"
          onClick={onSearch}
          className="flex items-center justify-between gap-2 rounded-[7px] border border-sidebar-border px-2.5 py-2 text-[12.5px] text-muted-foreground transition-colors hover:border-ring/40"
        >
          <span className="flex items-center gap-1.5">
            <Search className="size-3.5" />
            Search &amp; commands
          </span>
          <span className="rounded border border-border px-[5px] py-px font-mono text-[10.5px]">⌘K</span>
        </button>
        <div className="flex items-center justify-between px-0.5">
          <div className="flex items-center gap-2">
            <span className="flex size-[22px] items-center justify-center rounded-full bg-muted text-[11px] font-semibold">
              G
            </span>
            <span className="text-[12.5px] text-muted-foreground">grind</span>
          </div>
          <div className="flex items-center gap-0.5">
            <ThemeToggle />
            <form action={logoutAction}>
              <button
                type="submit"
                className="px-1.5 text-xs text-muted-foreground transition-colors hover:text-foreground"
              >
                Sign out
              </button>
            </form>
          </div>
        </div>
      </div>
    </aside>
  );
}
