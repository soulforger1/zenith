import Link from "next/link";
import { format } from "date-fns";

import { cn } from "@/lib/utils";
import { isOverdue } from "@/lib/date";
import type { IssuePriority, IssueStatus } from "@/lib/db/schema";
import { PRIORITY_DOT_CLASS } from "@/lib/priority";

export type UpcomingIssue = {
  id: string;
  title: string;
  priority: IssuePriority;
  status: IssueStatus;
  dueDate: string;
  spaceName: string;
  spaceSlug: string;
};

export function UpcomingWidget({ issues }: { issues: UpcomingIssue[] }) {
  return (
    <div className="overflow-hidden rounded-lg border bg-card">
      <div className="border-b bg-muted/60 px-4 py-2.5">
        <span className="font-mono text-[11px] font-semibold tracking-wide text-muted-foreground">
          DUE THIS WEEK
        </span>
      </div>
      {issues.length === 0 ? (
        <p className="px-4 py-6 text-center text-sm text-muted-foreground">
          Nothing due this week.
        </p>
      ) : (
        <div className="divide-y">
          {issues.map((issue) => {
            const overdue = isOverdue(issue.dueDate, issue.status);
            return (
              <Link
                key={issue.id}
                href={`/spaces/${issue.spaceSlug}`}
                className="flex items-center gap-2.5 px-4 py-2.5 text-[13px] transition-colors hover:bg-accent/40"
              >
                <span
                  className={cn(
                    "size-1.5 shrink-0 rounded-full",
                    PRIORITY_DOT_CLASS[issue.priority],
                  )}
                />
                <span className="flex-1 truncate">{issue.title}</span>
                <span className="rounded-[5px] bg-muted px-1.5 py-0.5 font-mono text-[10.5px] text-muted-foreground">
                  {issue.spaceName}
                </span>
                <span
                  className={cn(
                    "font-mono text-[11px]",
                    overdue
                      ? "font-semibold text-destructive"
                      : "text-muted-foreground",
                  )}
                >
                  {format(new Date(issue.dueDate), "MMM d")}
                </span>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}
