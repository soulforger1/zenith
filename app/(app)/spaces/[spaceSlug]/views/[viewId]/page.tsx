import { Suspense } from "react";
import { notFound } from "next/navigation";

import { getSpaceBySlug } from "@/lib/db/queries/spaces";
import { getViewById } from "@/lib/db/queries/views";
import {
  getIssuesForSpace,
  getRepoIdsByIssueIds,
  getSubtaskCountsByParentIds,
} from "@/lib/db/queries/issues";
import { getMilestonesForSpace } from "@/lib/db/queries/milestones";
import { getReposForSpace } from "@/lib/db/queries/repos";
import { getCustomFieldsForSpace } from "@/lib/db/queries/custom-fields";
import { toIssueRecord, toIssueRecords } from "@/lib/issue-types";
import type {
  BoardViewConfig,
  RoadmapViewConfig,
  TableViewConfig,
} from "@/lib/views/types";
import { QuickAddTask } from "@/components/issues/quick-add-task";
import { TableView } from "@/components/views/table-view";
import { KanbanBoard } from "@/components/board/kanban-board";
import { RoadmapView } from "@/components/roadmap/roadmap-view";
import { BoardSkeleton } from "@/components/layout/page-skeleton";

export default function SpaceViewPage({
  params,
}: {
  params: Promise<{ spaceSlug: string; viewId: string }>;
}) {
  return (
    <Suspense fallback={<BoardSkeleton />}>
      <SpaceViewPageBody params={params} />
    </Suspense>
  );
}

async function SpaceViewPageBody({
  params,
}: {
  params: Promise<{ spaceSlug: string; viewId: string }>;
}) {
  const { spaceSlug, viewId } = await params;
  const space = await getSpaceBySlug(spaceSlug);
  if (!space) notFound();

  const view = await getViewById(viewId);
  if (!view || view.spaceId !== space.id) notFound();

  const [issues, milestones, repos, customFields] = await Promise.all([
    getIssuesForSpace(space.id),
    getMilestonesForSpace(space.id),
    getReposForSpace(space.id),
    getCustomFieldsForSpace(space.id),
  ]);
  const issueIds = issues.map((issue) => issue.id);
  const [repoIdsByIssue, subtaskCountByIssue] = await Promise.all([
    getRepoIdsByIssueIds(issueIds),
    getSubtaskCountsByParentIds(issueIds),
  ]);

  const milestoneOptions = milestones.map((m) => ({
    id: m.id,
    title: m.title,
  }));
  const repoOptions = repos.map((r) => ({ id: r.id, name: r.name }));

  if (view.type === "table") {
    return (
      <div className="space-y-3">
        <div className="flex justify-end">
          <QuickAddTask
            spaceId={space.id}
            spaceSlug={space.slug}
            status="backlog"
            label="New task"
          />
        </div>
        <TableView
          view={{ id: view.id, config: view.config as TableViewConfig }}
          issues={toIssueRecords(issues, repoIdsByIssue, subtaskCountByIssue)}
          spaceId={space.id}
          spaceSlug={space.slug}
          customFields={customFields}
          milestones={milestoneOptions}
          repos={repoOptions}
        />
      </div>
    );
  }

  if (view.type === "board") {
    return (
      <KanbanBoard
        view={{ id: view.id, config: view.config as BoardViewConfig }}
        issues={issues.map((issue) => ({
          ...toIssueRecord(
            issue,
            repoIdsByIssue.get(issue.id) ?? [],
            subtaskCountByIssue.get(issue.id) ?? { total: 0, done: 0 },
          ),
          position: issue.position,
        }))}
        spaceId={space.id}
        spaceSlug={space.slug}
        customFields={customFields}
        milestones={milestoneOptions}
        repos={repoOptions}
      />
    );
  }

  return (
    <RoadmapView
      view={{ id: view.id, config: view.config as RoadmapViewConfig }}
      issues={toIssueRecords(issues, repoIdsByIssue, subtaskCountByIssue)}
      spaceId={space.id}
      spaceSlug={space.slug}
      customFields={customFields}
      milestones={milestoneOptions}
      repos={repoOptions}
    />
  );
}
