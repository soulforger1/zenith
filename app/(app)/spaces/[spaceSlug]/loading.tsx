import { Skeleton } from "@/components/ui/skeleton";
import { BoardSkeleton } from "@/components/layout/page-skeleton";

// Covers the first-ever navigation into a space (header + tabs haven't
// rendered yet). Once in, tab switches reuse this layout and only the
// nested list/board/milestones loading.tsx fires.
export default function Loading() {
  return (
    <div className="space-y-6 p-8">
      <div className="space-y-2">
        <Skeleton className="h-6 w-40" />
        <Skeleton className="h-4 w-64" />
      </div>
      <div className="flex gap-4 border-b pb-2">
        <Skeleton className="h-5 w-12" />
        <Skeleton className="h-5 w-12" />
        <Skeleton className="h-5 w-20" />
        <Skeleton className="h-5 w-16" />
      </div>
      <BoardSkeleton />
    </div>
  );
}
