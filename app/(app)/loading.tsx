import { Skeleton } from "@/components/ui/skeleton";

// Catch-all for routes without a more specific loading.tsx (settings,
// milestone detail, AI wizard steps).
export default function Loading() {
  return (
    <div className="mx-auto max-w-2xl space-y-4 p-8">
      <Skeleton className="h-6 w-48" />
      <Skeleton className="h-24 w-full" />
      <Skeleton className="h-24 w-full" />
    </div>
  );
}
