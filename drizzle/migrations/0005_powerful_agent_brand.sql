CREATE TABLE "issue_repos" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"issue_id" uuid NOT NULL,
	"repo_id" uuid NOT NULL
);
--> statement-breakpoint
-- Carry forward every existing single repo link before the column is
-- dropped below — hand-added, drizzle-kit only generates the shape diff.
INSERT INTO "issue_repos" ("issue_id", "repo_id") SELECT "id", "repo_id" FROM "issues" WHERE "repo_id" IS NOT NULL;
--> statement-breakpoint
ALTER TABLE "issues" DROP CONSTRAINT "issues_repo_id_repos_id_fk";
--> statement-breakpoint
DROP INDEX "issues_repo_id_idx";--> statement-breakpoint
ALTER TABLE "issue_repos" ADD CONSTRAINT "issue_repos_issue_id_issues_id_fk" FOREIGN KEY ("issue_id") REFERENCES "public"."issues"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "issue_repos" ADD CONSTRAINT "issue_repos_repo_id_repos_id_fk" FOREIGN KEY ("repo_id") REFERENCES "public"."repos"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "issue_repos_issue_id_repo_id_idx" ON "issue_repos" USING btree ("issue_id","repo_id");--> statement-breakpoint
CREATE INDEX "issue_repos_repo_id_idx" ON "issue_repos" USING btree ("repo_id");--> statement-breakpoint
ALTER TABLE "issues" DROP COLUMN "repo_id";