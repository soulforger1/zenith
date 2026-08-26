DROP TABLE IF EXISTS "ai_drafts" CASCADE;--> statement-breakpoint
ALTER TABLE "issues" ALTER COLUMN "priority" SET DEFAULT 'medium';--> statement-breakpoint
UPDATE "issues" SET "priority" = 'medium' WHERE "priority" IS NULL;--> statement-breakpoint
ALTER TABLE "issues" ALTER COLUMN "priority" SET NOT NULL;--> statement-breakpoint
ALTER TABLE "issues" ADD COLUMN IF NOT EXISTS "tags" text[] DEFAULT '{}' NOT NULL;--> statement-breakpoint
ALTER TABLE "issues" ADD COLUMN IF NOT EXISTS "branch" text;--> statement-breakpoint
ALTER TABLE "issues" ADD COLUMN IF NOT EXISTS "estimate" text;--> statement-breakpoint
ALTER TABLE "issues" ADD COLUMN IF NOT EXISTS "subtasks" jsonb DEFAULT '[]'::jsonb NOT NULL;
