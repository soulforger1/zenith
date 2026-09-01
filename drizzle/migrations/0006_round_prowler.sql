ALTER TABLE "issues" ADD COLUMN "parent_id" uuid;--> statement-breakpoint
ALTER TABLE "issues" ADD CONSTRAINT "issues_parent_id_issues_id_fk" FOREIGN KEY ("parent_id") REFERENCES "public"."issues"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "issues_parent_id_idx" ON "issues" USING btree ("parent_id");--> statement-breakpoint
-- Carry forward every existing inline subtask checklist entry as a real
-- child issue row before the column is dropped below — hand-added,
-- drizzle-kit only generates the shape diff. Position is appended well
-- past normal fractional-index territory since exact placement among
-- siblings doesn't matter for rows that were previously invisible on the
-- board. Postgres takes the SELECT's snapshot before this command's own
-- inserts, so it can safely read and insert into "issues" in one statement.
INSERT INTO "issues" (
  "space_id", "parent_id", "title", "status", "is_closed", "priority",
  "position", "closed_at", "created_at", "updated_at"
)
SELECT
  "issues"."space_id",
  "issues"."id",
  trim(subtask.value ->> 'text'),
  CASE WHEN COALESCE((subtask.value ->> 'done')::boolean, false) THEN 'done' ELSE 'todo' END,
  COALESCE((subtask.value ->> 'done')::boolean, false),
  'medium',
  1000000 + subtask.ordinality,
  CASE WHEN COALESCE((subtask.value ->> 'done')::boolean, false) THEN now() ELSE NULL END,
  now(),
  now()
FROM "issues", jsonb_array_elements("issues"."subtasks") WITH ORDINALITY AS subtask(value, ordinality)
WHERE jsonb_array_length("issues"."subtasks") > 0
  AND NULLIF(trim(subtask.value ->> 'text'), '') IS NOT NULL;
--> statement-breakpoint
ALTER TABLE "issues" DROP COLUMN "subtasks";