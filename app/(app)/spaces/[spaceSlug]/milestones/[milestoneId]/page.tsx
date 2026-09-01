import { Suspense } from "react";
import { notFound } from "next/navigation";

import { getSpaceBySlug } from "@/lib/db/queries/spaces";
import { getMilestoneById, getMilestonesForSpace } from "@/lib/db/queries/milestones";
import { getIssuesForMilestone, getRepoIdsByIssueIds, getSubtaskCountsByParentIds } from "@/lib/db/queries/issues";
import { getReposForSpace } from "@/lib/db/queries/repos";
import { updateMilestoneAction } from "@/lib/actions/milestones";
import { toIssueRecords } from "@/lib/issue-types";
import { IssueListClient } from "@/components/issues/issue-list-client";
import { MilestoneFormDialog } from "@/components/milestones/milestone-form-dialog";
import { MilestoneProgressBar } from "@/components/milestones/milestone-progress-bar";
import { MilestoneCloseButton } from "@/components/milestones/milestone-close-button";
import { BoardSkeleton } from "@/components/layout/page-skeleton";

export default function MilestoneDetailPage({
  params,
}: {
  params: Promise<{ spaceSlug: string; milestoneId: string }>;
}) {
  return (
    <Suspense fallback={<BoardSkeleton />}>
      <MilestoneDetailPageBody params={params} />
    </Suspense>
  );
}

async function MilestoneDetailPageBody({
  params,
}: {
  params: Promise<{ spaceSlug: string; milestoneId: string }>;
}) {
  const { spaceSlug, milestoneId } = await params;
  const space = await getSpaceBySlug(spaceSlug);
  if (!space) notFound();

  const milestone = await getMilestoneById(milestoneId);
  if (!milestone || milestone.spaceId !== space.id) notFound();

  const [issues, milestones, repos] = await Promise.all([
    getIssuesForMilestone(milestone.id),
    getMilestonesForSpace(space.id),
    getReposForSpace(space.id),
  ]);
  const issueIds = issues.map((issue) => issue.id);
  const [repoIdsByIssue, subtaskCountByIssue] = await Promise.all([
    getRepoIdsByIssueIds(issueIds),
    getSubtaskCountsByParentIds(issueIds),
  ]);
  const closed = issues.filter((issue) => issue.isClosed).length;
  const boundUpdate = updateMilestoneAction.bind(null, milestone.id, space.slug);
  const isClosed = milestone.status === "closed";

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-2">
            <h3 className={isClosed ? "text-lg font-semibold text-muted-foreground line-through" : "text-lg font-semibold"}>
              {milestone.title}
            </h3>
            {isClosed ? (
              <span className="rounded-[5px] bg-muted px-1.5 py-0.5 font-mono text-[10.5px] text-muted-foreground">
                CLOSED
              </span>
            ) : null}
          </div>
          {milestone.description ? (
            <p className="text-sm text-muted-foreground">{milestone.description}</p>
          ) : null}
        </div>
        <div className="flex items-center gap-1.5">
          <MilestoneCloseButton milestoneId={milestone.id} spaceSlug={space.slug} isClosed={isClosed} />
          <MilestoneFormDialog
            action={boundUpdate}
            mode="edit"
            defaultValues={{
              title: milestone.title,
              description: milestone.description,
              dueDate: milestone.dueDate,
            }}
          />
        </div>
      </div>
      <MilestoneProgressBar closed={closed} total={issues.length} />
      <IssueListClient
        issues={toIssueRecords(issues, repoIdsByIssue, subtaskCountByIssue)}
        spaceSlug={space.slug}
        milestones={milestones}
        repos={repos}
      />
    </div>
  );
}
