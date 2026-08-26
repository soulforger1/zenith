import { Suspense } from "react";
import { notFound } from "next/navigation";

import { getSpaceBySlug, getSpaces } from "@/lib/db/queries/spaces";
import { getSpaceImages } from "@/lib/db/queries/space-images";
import { getReposForSpace } from "@/lib/db/queries/repos";
import { getCustomFieldsForSpace } from "@/lib/db/queries/custom-fields";
import type { CustomFieldType } from "@/lib/db/schema";
import { SHORTCUTS } from "@/lib/shortcuts";
import { QuickAddSpace } from "@/components/spaces/quick-add-space";
import { RemoveSpaceLink } from "@/components/spaces/remove-space-link";
import { SpaceContextForm } from "@/components/spaces/space-context-form";
import { SpaceImageGallery } from "@/components/spaces/space-image-gallery";
import { RepoManager } from "@/components/spaces/repo-manager";
import { FieldManager } from "@/components/fields/field-manager";
import { CardGridSkeleton } from "@/components/layout/page-skeleton";

export default function SpaceSettingsPage({
  params,
}: {
  params: Promise<{ spaceSlug: string }>;
}) {
  return (
    <Suspense fallback={<CardGridSkeleton />}>
      <SpaceSettingsPageBody params={params} />
    </Suspense>
  );
}

async function SpaceSettingsPageBody({ params }: { params: Promise<{ spaceSlug: string }> }) {
  const { spaceSlug } = await params;
  const [space, spaces] = await Promise.all([getSpaceBySlug(spaceSlug), getSpaces()]);
  if (!space) notFound();

  const [images, repos, customFields] = await Promise.all([
    getSpaceImages(space.id),
    getReposForSpace(space.id),
    getCustomFieldsForSpace(space.id),
  ]);

  return (
    <div className="flex max-w-[560px] flex-col gap-7">
      <SpaceContextForm spaceId={space.id} spaceSlug={space.slug} initialContext={space.context} />

      <FieldManager
        spaceId={space.id}
        spaceSlug={space.slug}
        fields={customFields.map((f) => ({
          id: f.id,
          name: f.name,
          type: f.type as CustomFieldType,
          options: f.options as never,
        }))}
      />

      <RepoManager
        spaceId={space.id}
        spaceSlug={space.slug}
        repos={repos.map((r) => ({
          id: r.id,
          name: r.name,
          url: r.url,
          cachedAt: r.cachedAt ? r.cachedAt.toISOString() : null,
        }))}
      />

      <SpaceImageGallery spaceId={space.id} spaceSlug={space.slug} images={images} />

      <div>
        <div className="mb-2.5 text-[13px] font-semibold text-foreground/80">Spaces</div>
        <div className="mb-2.5 flex flex-col gap-1.5">
          {spaces.map((sp) => (
            <div
              key={sp.id}
              className="flex items-center justify-between rounded-[7px] border px-3 py-2 text-[13px]"
            >
              <span>{sp.name}</span>
              <RemoveSpaceLink spaceId={sp.id} spaceName={sp.name} />
            </div>
          ))}
        </div>
        <QuickAddSpace />
      </div>

      <div>
        <div className="mb-2.5 text-[13px] font-semibold text-foreground/80">Keyboard shortcuts</div>
        <div className="flex flex-col overflow-hidden rounded-lg border">
          {SHORTCUTS.map((s) => (
            <div
              key={s.keys}
              className="flex items-center justify-between border-b bg-card px-3.5 py-[9px] text-[12.5px] last:border-b-0"
            >
              <span className="text-muted-foreground">{s.desc}</span>
              <span className="rounded-[5px] border px-[7px] py-px font-mono text-[11px]">{s.keys}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
