import {
  boolean,
  date,
  doublePrecision,
  index,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

// FieldOption/IterationOption are the two shapes `customFields.options` can
// hold, depending on `type`. Declared up top since both `customFields` and
// (indirectly, via issue values) the views config reference them.
export type FieldOption = { id: string; name: string; color: string };
export type IterationOption = { id: string; title: string; startDate: string; durationDays: number };

// ---------------------------------------------------------------------------
// Spaces — top-level containers per project/org (e.g. "Work", "Side Projects")
// `context` is free text (features, services, stack, conventions) that gets
// prepended to every AI paste-task prompt for this space so parsed tasks fit
// the actual project instead of being generic.
// ---------------------------------------------------------------------------
export const spaces = pgTable("spaces", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  slug: text("slug").notNull().unique(),
  description: text("description"),
  context: text("context"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Space images — persistent reference images (architecture diagrams, design
// mockups, screenshots) attached to a space's context. Stored inline as
// base64 data URLs — no separate object storage service to configure for a
// personal-scale app; sent to Claude as multimodal input alongside the text
// context on every paste-task parse in that space.
// ---------------------------------------------------------------------------
export const spaceImages = pgTable(
  "space_images",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    spaceId: uuid("space_id")
      .notNull()
      .references(() => spaces.id, { onDelete: "cascade" }),
    dataUrl: text("data_url").notNull(),
    label: text("label"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index("space_images_space_id_idx").on(table.spaceId)],
);

// ---------------------------------------------------------------------------
// Milestones — grouped goals within a space. Progress is computed on read
// from the issues that reference them; no manual open/closed state.
// ---------------------------------------------------------------------------
export const milestones = pgTable(
  "milestones",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    spaceId: uuid("space_id")
      .notNull()
      .references(() => spaces.id, { onDelete: "cascade" }),
    title: text("title").notNull(),
    description: text("description"),
    dueDate: date("due_date"),
    // Kept for potential future use; not currently exposed in the UI.
    status: text("status").notNull().default("open"),
    closedAt: timestamp("closed_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index("milestones_space_id_idx").on(table.spaceId)],
);

// ---------------------------------------------------------------------------
// Repos — GitHub repos linked to a space (a space can track several, e.g.
// "web"/"api"/"worker"). `name` is the short label the AI matches against
// pasted task text to figure out which repo a task belongs to. `cachedContext`
// is an AI-generated summary refreshed only by an explicit manual sync — repo
// content is never fetched live on every task-parse.
// ---------------------------------------------------------------------------
export const repos = pgTable(
  "repos",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    spaceId: uuid("space_id")
      .notNull()
      .references(() => spaces.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    url: text("url").notNull(),
    cachedContext: text("cached_context"),
    cachedAt: timestamp("cached_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index("repos_space_id_idx").on(table.spaceId)],
);

// ---------------------------------------------------------------------------
// Custom fields — per-space, user-defined fields (Size, Assignees, Sprint,
// ...), the same idea as GitHub Projects' custom fields. `key` is a slug used
// by the AI resolver to match a field by name across parse requests without
// depending on its uuid. `options` holds `FieldOption[]` for select-type
// fields or `IterationOption[]` for iteration fields — empty array otherwise.
// Values live on `issues.customFieldValues`, keyed by this table's `id`, not
// as a separate join table — this app loads full per-space lists and filters
// client-side everywhere already, so there's no need for DB-side joins/filters.
// ---------------------------------------------------------------------------
export const customFieldTypeValues = [
  "text",
  "number",
  "date",
  "single_select",
  "multi_select",
  "iteration",
] as const;
export type CustomFieldType = (typeof customFieldTypeValues)[number];

export const customFields = pgTable(
  "custom_fields",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    spaceId: uuid("space_id")
      .notNull()
      .references(() => spaces.id, { onDelete: "cascade" }),
    key: text("key").notNull(),
    name: text("name").notNull(),
    type: text("type").notNull(),
    options: jsonb("options").$type<FieldOption[] | IterationOption[]>().notNull().default([]),
    position: doublePrecision("position").notNull().default(0),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index("custom_fields_space_id_idx").on(table.spaceId)],
);

// ---------------------------------------------------------------------------
// Views — saved, named Table/Board/Roadmap views per space (GitHub Projects
// style), each remembering its own visible fields/filters/sort/group-by in
// `config`. Exactly one view per space should have `isDefault: true` — that's
// what a bare `/spaces/[slug]` redirects to (enforced in the views queries,
// not a DB constraint).
// ---------------------------------------------------------------------------
export const viewTypeValues = ["table", "board", "roadmap"] as const;
export type ViewType = (typeof viewTypeValues)[number];

export const views = pgTable(
  "views",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    spaceId: uuid("space_id")
      .notNull()
      .references(() => spaces.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    type: text("type").notNull(),
    position: doublePrecision("position").notNull().default(0),
    isDefault: boolean("is_default").notNull().default(false),
    // Shape depends on `type` — see lib/views/types.ts for
    // TableViewConfig/BoardViewConfig/RoadmapViewConfig.
    config: jsonb("config").$type<Record<string, unknown>>().notNull().default({}),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index("views_space_id_idx").on(table.spaceId)],
);

// ---------------------------------------------------------------------------
// Issues — the actual to-dos. `status` drives both the Kanban columns and
// "done"-ness (no separate close/reopen concept — `is_closed`/`closed_at`
// are kept in sync automatically whenever status flips to/from "done", for
// any future reporting, but the UI is status-driven only).
// ---------------------------------------------------------------------------
export const issueStatusValues = ["backlog", "todo", "in_progress", "done"] as const;
export type IssueStatus = (typeof issueStatusValues)[number];

export const issuePriorityValues = ["low", "medium", "high"] as const;
export type IssuePriority = (typeof issuePriorityValues)[number];

export type Subtask = { text: string; done: boolean };

export const issues = pgTable(
  "issues",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    spaceId: uuid("space_id")
      .notNull()
      .references(() => spaces.id, { onDelete: "cascade" }),
    milestoneId: uuid("milestone_id").references(() => milestones.id, {
      onDelete: "set null",
    }),
    title: text("title").notNull(),
    description: text("description"),
    status: text("status").notNull().default("backlog"),
    isClosed: boolean("is_closed").notNull().default(false),
    priority: text("priority").notNull().default("medium"),
    tags: text("tags").array().notNull().default([]),
    branch: text("branch"),
    estimate: text("estimate"),
    subtasks: jsonb("subtasks").$type<Subtask[]>().notNull().default([]),
    dueDate: date("due_date"),
    // First-class start date alongside `dueDate`, so a Roadmap view has a
    // built-in date range to draw from without forcing a custom field.
    startDate: date("start_date"),
    // Values for this space's custom fields, keyed by `customFields.id`.
    // Shape per entry depends on the field's `type`: string for text/date,
    // number for number, an option id for single_select, an option id array
    // for multi_select, an iteration id for iteration.
    customFieldValues: jsonb("custom_field_values").$type<Record<string, unknown>>().notNull().default({}),
    // fractional index for manual drag ordering within a status column
    position: doublePrecision("position").notNull().default(0),
    closedAt: timestamp("closed_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index("issues_space_id_status_idx").on(table.spaceId, table.status),
    index("issues_milestone_id_idx").on(table.milestoneId),
  ],
);

// ---------------------------------------------------------------------------
// Issue <-> repo links — many-to-many, since a task can span more than one
// linked repo. Both FKs cascade off their parent (an issue or a repo being
// deleted takes its link rows with it, no orphaned rows to clean up).
// ---------------------------------------------------------------------------
export const issueRepos = pgTable(
  "issue_repos",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    issueId: uuid("issue_id")
      .notNull()
      .references(() => issues.id, { onDelete: "cascade" }),
    repoId: uuid("repo_id")
      .notNull()
      .references(() => repos.id, { onDelete: "cascade" }),
  },
  (table) => [
    uniqueIndex("issue_repos_issue_id_repo_id_idx").on(table.issueId, table.repoId),
    index("issue_repos_repo_id_idx").on(table.repoId),
  ],
);
