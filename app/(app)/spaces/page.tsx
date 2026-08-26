import { Suspense } from "react";
import Link from "next/link";

import { getSpaces } from "@/lib/db/queries/spaces";
import { getIssueCountsBySpace, getUpcomingIssues } from "@/lib/db/queries/issues";
import type { IssuePriority, IssueStatus } from "@/lib/db/schema";
import { Button } from "@/components/ui/button";
import { SpaceCard } from "@/components/spaces/space-card";
import { UpcomingWidget } from "@/components/spaces/upcoming-widget";
import { CardGridSkeleton } from "@/components/layout/page-skeleton";

export default function SpacesPage() {
  return (
    <div className="space-y-6 p-8">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold">Spaces</h2>
        <Button render={<Link href="/spaces/new" />} nativeButton={false}>
          New space
        </Button>
      </div>
      <Suspense fallback={<CardGridSkeleton />}>
        <SpacesPageBody />
      </Suspense>
    </div>
  );
}

async function SpacesPageBody() {
  const [spaces, counts, upcoming] = await Promise.all([
    getSpaces(),
    getIssueCountsBySpace(),
    getUpcomingIssues(7),
  ]);

  return (
    <>
      {spaces.length > 0 ? (
        <UpcomingWidget
          issues={upcoming.map((issue) => ({
            id: issue.id,
            title: issue.title,
            priority: issue.priority as IssuePriority,
            status: issue.status as IssueStatus,
            dueDate: issue.dueDate as string,
            spaceName: issue.spaceName,
            spaceSlug: issue.spaceSlug,
          }))}
        />
      ) : null}

      {spaces.length === 0 ? (
        <div className="rounded-lg border border-dashed p-12 text-center text-muted-foreground">
          <p>No spaces yet. Create one to start tracking issues and milestones.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {spaces.map((space) => {
            const c = counts.get(space.id) ?? { total: 0, open: 0 };
            return (
              <SpaceCard
                key={space.id}
                name={space.name}
                slug={space.slug}
                description={space.description}
                openCount={c.open}
                totalCount={c.total}
              />
            );
          })}
        </div>
      )}
    </>
  );
}
