import { Skeleton } from "@/components/ui/skeleton";

export function ListSkeleton() {
  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <Skeleton className="h-7 w-24" />
      </div>
      <Skeleton className="h-8 w-40" />
      <div className="space-y-2 rounded-lg border p-2">
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-9 w-full" />
        ))}
      </div>
    </div>
  );
}

export function BoardSkeleton() {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {Array.from({ length: 4 }).map((_, col) => (
        <div key={col} className="space-y-2 rounded-lg border bg-muted/30 p-2">
          <Skeleton className="h-4 w-16" />
          {Array.from({ length: 3 }).map((_, row) => (
            <Skeleton key={row} className="h-16 w-full" />
          ))}
        </div>
      ))}
    </div>
  );
}

export function CardGridSkeleton() {
  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <Skeleton className="h-7 w-32" />
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-28 w-full" />
        ))}
      </div>
    </div>
  );
}

/** Matches components/layout/space-tabs.tsx's <SpaceHeader> shape (title +
 * search link row, then a tab row) — the Suspense fallback for the space
 * layout's header while it resolves the space/views fetch. */
export function SpaceHeaderSkeleton() {
  return (
    <div className="shrink-0 border-b px-8 pt-2.5">
      <div className="mb-2 flex items-center justify-between">
        <Skeleton className="h-5 w-40" />
        <Skeleton className="h-4 w-24" />
      </div>
      <div className="flex items-center gap-4 pb-[7px]">
        <Skeleton className="h-4 w-16" />
        <Skeleton className="h-4 w-16" />
        <Skeleton className="h-4 w-16" />
      </div>
    </div>
  );
}

/** Matches components/layout/app-sidebar.tsx's fixed w-[260px] shape — the
 * Suspense fallback for the whole app shell while the sidebar's spaces list
 * resolves. Blank main area since page content streams inside this same
 * boundary too (see app/(app)/layout.tsx for why). */
export function AppShellSkeleton() {
  return (
    <div className="flex h-screen flex-1 overflow-hidden">
      <aside className="flex h-screen w-[260px] shrink-0 flex-col gap-2.5 overflow-hidden border-r border-sidebar-border bg-sidebar p-4">
        <div className="app-drag-region h-6 shrink-0" />
        <Skeleton className="mb-[22px] h-[26px] w-24" />
        <Skeleton className="mb-[22px] h-10 w-full" />
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-8 w-full" />
        ))}
      </aside>
      <main className="flex flex-1 min-h-0 flex-col overflow-hidden">
        <div className="app-drag-region h-6 shrink-0" />
      </main>
    </div>
  );
}
