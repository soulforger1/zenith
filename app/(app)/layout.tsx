import { Suspense } from "react";

import { getSpaces } from "@/lib/db/queries/spaces";
import { getIssueCountsBySpace } from "@/lib/db/queries/issues";
import { AppShell } from "@/components/layout/app-shell";
import { AppShellSkeleton } from "@/components/layout/page-skeleton";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <Suspense fallback={<AppShellSkeleton />}>
      <AppShellData>{children}</AppShellData>
    </Suspense>
  );
}

// Split out so the sidebar's data fetch can sit behind a <Suspense>
// boundary — without this, the layout's own await blocks navigation with no
// loading indicator at all (a layout's data access is never covered by its
// own segment's loading.tsx; see spaces/[spaceSlug]/layout.tsx for the same
// pattern). AppShell threads `children` through its own JSX (sidebar/modals
// all need `spaces` too), so children ends up inside this boundary as well —
// this trades "frozen blank screen" for "instant skeleton, then everything
// together" rather than fully independent streaming past the sidebar.
async function AppShellData({ children }: { children: React.ReactNode }) {
  const [spaces, counts] = await Promise.all([getSpaces(), getIssueCountsBySpace()]);
  const spacesWithCounts = spaces.map((space) => ({
    id: space.id,
    name: space.name,
    slug: space.slug,
    count: counts.get(space.id)?.total ?? 0,
  }));

  return <AppShell spaces={spacesWithCounts}>{children}</AppShell>;
}
