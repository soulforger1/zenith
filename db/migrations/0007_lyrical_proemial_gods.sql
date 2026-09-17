CREATE TABLE "sync_tombstones" (
	"table_name" text NOT NULL,
	"row_id" uuid NOT NULL,
	"deleted_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "sync_tombstones_table_name_row_id_pk" PRIMARY KEY("table_name","row_id")
);
--> statement-breakpoint
ALTER TABLE "issue_repos" ADD COLUMN "updated_at" timestamp with time zone DEFAULT now() NOT NULL;--> statement-breakpoint
ALTER TABLE "space_images" ADD COLUMN "updated_at" timestamp with time zone DEFAULT now() NOT NULL;--> statement-breakpoint
CREATE INDEX "sync_tombstones_deleted_at_idx" ON "sync_tombstones" USING btree ("deleted_at");