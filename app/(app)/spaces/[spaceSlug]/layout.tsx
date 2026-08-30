import { Suspense } from "react";
import { notFound } from "next/navigation";

import { getSpaceBySlug } from "@/lib/db/queries/spaces";
import { getOrCreateDefaultViewsForSpace } from "@/lib/db/queries/views";
import { SpaceHeader } from "@/components/layout/space-tabs";
import { SpaceHeaderSkeleton } from "@/components/layout/page-skeleton";

export default function SpaceLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ spaceSlug: string }>;
}) {
  return (
    <div className="flex h-full min-h-0 flex-1 flex-col overflow-hidden">
      <Suspense fallback={<SpaceHeaderSkeleton />}>
        <SpaceHeaderData params={params} />
      </Suspense>
      <div className="flex-1 min-h-0 overflow-y-auto px-8 py-[26px]">{children}</div>
    </div>
  );
}

// Split out so this layout's data fetch (space lookup + view seeding) sits
// behind its own <Suspense> boundary. A layout's own blocking data access is
// never covered by its segment's loading.tsx (that only wraps page.tsx and
// nested layouts) — without this, every navigation into any space blocked
// completely with no loading indicator at all. `children` stays a direct
// sibling above, outside this boundary, so route content streams
// independently of the header's fetch.
async function SpaceHeaderData({ params }: { params: Promise<{ spaceSlug: string }> }) {
  const { spaceSlug } = await params;
  const space = await getSpaceBySlug(spaceSlug);
  if (!space) notFound();

  const views = await getOrCreateDefaultViewsForSpace(space.id);

  return (
    <SpaceHeader
      spaceId={space.id}
      spaceName={space.name}
      slug={space.slug}
      views={views.map((v) => ({ id: v.id, name: v.name, type: v.type as "table" | "board" | "roadmap" }))}
    />
  );
}
