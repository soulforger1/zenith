import { Suspense } from "react";
import { notFound, redirect } from "next/navigation";

import { getSpaceBySlug } from "@/lib/db/queries/spaces";
import { getOrCreateDefaultViewsForSpace } from "@/lib/db/queries/views";
import { BoardSkeleton } from "@/components/layout/page-skeleton";

export default function SpaceIndexPage({
  params,
}: {
  params: Promise<{ spaceSlug: string }>;
}) {
  return (
    <Suspense fallback={<BoardSkeleton />}>
      <SpaceIndexRedirect params={params} />
    </Suspense>
  );
}

async function SpaceIndexRedirect({
  params,
}: {
  params: Promise<{ spaceSlug: string }>;
}) {
  const { spaceSlug } = await params;
  const space = await getSpaceBySlug(spaceSlug);
  if (!space) notFound();

  const views = await getOrCreateDefaultViewsForSpace(space.id);
  const target = views.find((v) => v.isDefault) ?? views[0];
  return redirect(`/spaces/${spaceSlug}/views/${target.id}`);
}
