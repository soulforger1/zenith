import { Suspense } from "react";
import { notFound } from "next/navigation";

import { getSpaceBySlug } from "@/lib/db/queries/spaces";
import { getMilestonesForSpace } from "@/lib/db/queries/milestones";
import { getIssuesForSpace } from "@/lib/db/queries/issues";
import { createMilestoneAction } from "@/lib/actions/milestones";
import { MilestoneFormDialog } from "@/components/milestones/milestone-form-dialog";
import { MilestoneCard } from "@/components/milestones/milestone-card";
import { CardGridSkeleton } from "@/components/layout/page-skeleton";

export default function MilestonesPage({
  params,
}: {
  params: Promise<{ spaceSlug: string }>;
}) {
  return (
    <Suspense fallback={<CardGridSkeleton />}>
      <MilestonesPageBody params={params} />
    </Suspense>
  );
}

async function MilestonesPageBody({ params }: { params: Promise<{ spaceSlug: string }> }) {
  const { spaceSlug } = await params;
  const space = await getSpaceBySlug(spaceSlug);
  if (!space) notFound();

  const [milestones, issues] = await Promise.all([
    getMilestonesForSpace(space.id),
    getIssuesForSpace(space.id),
  ]);

  const boundCreate = createMilestoneAction.bind(null, space.id, space.slug);

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <MilestoneFormDialog action={boundCreate} mode="create" />
      </div>
      {milestones.length === 0 ? (
        <div className="rounded-lg border border-dashed p-12 text-center text-muted-foreground">
          <p>No milestones yet.</p>
        </div>
      ) : (
        <div className="flex max-w-[640px] flex-col gap-3.5">
          {milestones.map((milestone) => {
            const linkedIssues = issues.filter((issue) => issue.milestoneId === milestone.id);
            const closed = linkedIssues.filter((issue) => issue.isClosed).length;
            return (
              <MilestoneCard
                key={milestone.id}
                milestone={{
                  id: milestone.id,
                  title: milestone.title,
                  description: milestone.description,
                  dueDate: milestone.dueDate,
                  status: milestone.status,
                }}
                spaceSlug={space.slug}
                closed={closed}
                total={linkedIssues.length}
                linked={linkedIssues.map((issue) => ({
                  title: issue.title,
                  priority: issue.priority as "low" | "medium" | "high",
                }))}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
