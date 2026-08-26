import "server-only";

import { imageBlock, runClaudeJSON, runClaudeText, type ContentBlock } from "@/lib/ai/claude";
import type { RepoSnapshot } from "@/lib/github/client";
import {
  generatedSubtasksSchema,
  parsedTaskSchema,
  parsedTasksSchema,
  type AttachedImage,
  type ParsedTask,
  type ParsedTasks,
} from "@/lib/ai/schemas";

// Shared per-task shape: used both as the top-level schema for the single-task
// flow and as the `items` schema of the array for the bulk-list flow below.
// `fieldValues`/`newFields` are fixed-shape (all-string) regardless of which
// custom fields actually exist in the space — a JSON schema can't vary its
// shape per request, so the per-space field *list* only ever appears in the
// prompt text (buildCustomFieldsBlock below), and the route (via
// lib/ai/field-resolver.ts) coerces these generic string values to each
// field's real type afterward.
const parseTaskJsonSchema = {
  type: "object",
  properties: {
    title: { type: "string" },
    description: { type: "string" },
    priority: { type: "string", enum: ["low", "medium", "high"] },
    tags: { type: "array", items: { type: "string" } },
    branch: { type: "string" },
    estimate: { type: "string" },
    dueDate: { type: "string" },
    repos: { type: "array", items: { type: "string" } },
    milestone: { type: "string" },
    fieldValues: {
      type: "array",
      items: {
        type: "object",
        properties: { fieldKey: { type: "string" }, value: { type: "string" } },
        required: ["fieldKey", "value"],
      },
    },
    newFields: {
      type: "array",
      items: {
        type: "object",
        properties: {
          key: { type: "string" },
          name: { type: "string" },
          type: {
            type: "string",
            enum: ["text", "number", "date", "single_select", "multi_select", "iteration"],
          },
          options: { type: "array", items: { type: "string" } },
        },
        required: ["key", "name", "type"],
      },
    },
  },
  required: ["title", "priority", "tags"],
};

// The Messages API requires a structured-output schema to be `type: "object"`
// at the root — a bare array gets rejected — so array-shaped results are
// wrapped in an object and unwrapped again via `unwrapKey` after the call.
const parseTasksJsonSchema = {
  type: "object",
  properties: { tasks: { type: "array", items: parseTaskJsonSchema } },
  required: ["tasks"],
};

const generatedSubtasksJsonSchema = {
  type: "object",
  properties: { subtasks: { type: "array", items: { type: "string" } } },
  required: ["subtasks"],
};

/** A space's linked repos, as fed into a parse prompt — cached summaries only,
 * never live repo content (see lib/github/client.ts + summarizeRepoContext). */
export type RepoContext = { name: string; context: string | null };

function buildReposBlock(repos: RepoContext[] | undefined): string[] {
  if (!repos || repos.length === 0) return [];
  return [
    "",
    "This space has these linked repos. Add each one clearly named (or obviously",
    "synonymous) to `repos` by its exact name below — a task can span more than one,",
    "so include all that clearly apply. Use their context to inform tags/branch/priority.",
    "If no repo is clearly named, leave `repos` empty; don't guess:",
    ...repos.map((r) => `- ${r.name}${r.context ? `: ${r.context}` : ""}`),
  ];
}

/** A space's milestones, as fed into a parse prompt — the existing free-text
 * "description" milestones already have, reused as-is (no separate field). */
export type MilestoneContext = { title: string; description: string | null };

function buildMilestonesBlock(milestones: MilestoneContext[] | undefined): string[] {
  if (!milestones || milestones.length === 0) return [];
  return [
    "",
    "This space has these milestones (goals). Unlike repos, this doesn't require an",
    "explicit name mention — if the task's content clearly fits one milestone's stated",
    "scope (by name, or by what it covers), set `milestone` to its exact title below.",
    "If nothing clearly fits, omit `milestone` entirely — don't force a task into a",
    "milestone it doesn't clearly belong to:",
    ...milestones.map((m) => `- ${m.title}${m.description ? `: ${m.description}` : ""}`),
  ];
}

/** A space's custom field definitions, as fed into a parse prompt. `options`
 * is the current option *labels* only (for select/iteration types) — the
 * route resolves labels back to option ids after parsing. */
export type CustomFieldContext = { key: string; name: string; type: string; options: string[] };

function buildCustomFieldsBlock(fields: CustomFieldContext[] | undefined): string[] {
  const lines = [
    "",
    "This space has custom fields (beyond the built-in ones above). If the message",
    "clearly gives a value for one, add it to `fieldValues` as `{ fieldKey, value }`",
    '(value always as plain text — e.g. "L", "3", "2026-09-01", or "alice, bob" for a',
    "multi-value field — never invent a value that isn't stated or clearly implied).",
  ];
  if (fields && fields.length > 0) {
    lines.push(
      "Existing fields (fieldKey — type — options if any):",
      ...fields.map((f) => `- ${f.key} — ${f.type}${f.options.length ? ` — options: ${f.options.join(", ")}` : ""}`),
    );
  } else {
    lines.push("This space has no custom fields yet.");
  }
  lines.push(
    "",
    "If the message clearly implies a field that doesn't exist yet (e.g. \"Size: L\" with",
    "no Size field above), you may propose up to 3 new ones via `newFields` — each",
    "`{ key, name, type, options? }` (type one of text/number/date/single_select/",
    "multi_select/iteration; include a short `options` list of labels only for",
    "single_select/multi_select) — and also add its value to `fieldValues` using that",
    "same `key`. Don't propose a field for something the built-in fields already cover",
    "(priority, tags, due date, branch, estimate, repos, milestone).",
  );
  return lines;
}

// Field-extraction rules shared by the single-task and bulk-list prompts.
const TASK_FIELD_RULES = [
  "- title: a short, actionable summary (rewrite it if the source is rambly).",
  "- description: a short 1-4 sentence elaboration ONLY if the source has real detail",
  "  beyond the title worth preserving (context, repro steps, acceptance criteria);",
  "  omit entirely if the title already says it all — don't pad for the sake of it.",
  '- priority: "high" if urgent/ASAP/blocker language is present, "low" if',
  '  explicitly deprioritized ("no rush", "whenever"), otherwise "medium".',
  "- tags: short lowercase keywords (e.g. bug, frontend, backend, security, infra,",
  "  docs, payments, design) — infer from context, don't invent unrelated ones.",
  "- branch: a git branch name only if one is mentioned or clearly implied",
  '  (e.g. "fix/checkout-500"); omit otherwise.',
  '- estimate: a short effort estimate like "2h" or "1d" only if the text gives one;',
  "  omit otherwise, don't guess.",
  "- dueDate: resolve relative dates (\"by Friday\", \"end of week\") to an absolute",
  "  ISO date (YYYY-MM-DD) using today's date above; omit if no due date is implied.",
];

export async function parseTaskFromText(input: {
  text: string;
  spaceContext?: string | null;
  spaceImages?: AttachedImage[];
  attachedImage?: AttachedImage | null;
  repos?: RepoContext[];
  milestones?: MilestoneContext[];
  customFields?: CustomFieldContext[];
}): Promise<ParsedTask> {
  const today = new Date().toISOString().slice(0, 10);

  const instructions = [
    "You extract a single structured task from a raw message someone pasted from a",
    "chat/ticket/manager (Slack, email, standup notes, etc), and/or a screenshot they",
    "attached (e.g. a bug, an error dialog, a design mockup). Today's date is",
    `${today}.`,
    "",
    ...TASK_FIELD_RULES,
    ...buildReposBlock(input.repos),
    ...buildMilestonesBlock(input.milestones),
    ...buildCustomFieldsBlock(input.customFields),
  ];

  if (input.spaceContext) {
    instructions.push(
      "",
      "Project context for this space (use it to pick better-fitting tags, branch names,",
      "and priority — e.g. known services, tech stack, conventions):",
      `"""\n${input.spaceContext}\n"""`,
    );
  }

  instructions.push("", "Message:", `"""\n${input.text || "(no text — see attached image)"}\n"""`);

  const images = input.spaceImages ?? [];
  const hasImages = images.length > 0 || Boolean(input.attachedImage);

  let prompt: string | ContentBlock[] = instructions.join("\n");
  if (hasImages) {
    const blocks: ContentBlock[] = [{ type: "text", text: prompt }];
    for (const image of images) {
      blocks.push(imageBlock(image.mimeType, image.data));
    }
    if (input.attachedImage) {
      blocks.push({ type: "text", text: "Screenshot attached with this task:" });
      blocks.push(imageBlock(input.attachedImage.mimeType, input.attachedImage.data));
    }
    prompt = blocks;
  }

  return runClaudeJSON(prompt, parseTaskJsonSchema, parsedTaskSchema, { timeoutMs: hasImages ? 120_000 : 90_000 });
}

/** Bulk "paste a list" flow: splits a pasted list into many structured tasks. */
export async function parseTasksFromText(input: {
  text: string;
  spaceContext?: string | null;
  repos?: RepoContext[];
  milestones?: MilestoneContext[];
  customFields?: CustomFieldContext[];
}): Promise<ParsedTasks> {
  const today = new Date().toISOString().slice(0, 10);

  const instructions = [
    "You extract a list of structured tasks from a raw list someone pasted from a",
    "chat/ticket/manager/notes app (Slack, email, standup notes, a backlog dump, etc).",
    "Split it into one task per distinct bullet, numbered item, or line — ignore section",
    "headers and blank lines, and don't merge unrelated items together. Different items",
    "may belong to different repos/milestones (see below) — decide those independently",
    "per item. Today's date is",
    `${today}.`,
    "",
    "For each task, apply these rules:",
    ...TASK_FIELD_RULES,
    ...buildReposBlock(input.repos),
    ...buildMilestonesBlock(input.milestones),
    ...buildCustomFieldsBlock(input.customFields),
  ];

  if (input.spaceContext) {
    instructions.push(
      "",
      "Project context for this space (use it to pick better-fitting tags, branch names,",
      "and priority — e.g. known services, tech stack, conventions):",
      `"""\n${input.spaceContext}\n"""`,
    );
  }

  instructions.push("", "List:", `"""\n${input.text}\n"""`);

  return runClaudeJSON(instructions.join("\n"), parseTasksJsonSchema, parsedTasksSchema, {
    timeoutMs: 180_000,
    unwrapKey: "tasks",
  });
}

/** One-off "Sync" summary: turns a curated repo snapshot (README/package.json/
 * top-level tree, never full source) into a short paragraph cached on the repo
 * and reused — unlike parseTaskFromText/parseTasksFromText, this is never
 * called per task-parse. */
export async function summarizeRepoContext(snapshot: RepoSnapshot): Promise<string> {
  const instructions = [
    `Summarize the GitHub repo "${snapshot.fullName}" in about 150-300 words of plain`,
    "prose, for use as background context fed to another AI whenever someone pastes a",
    "task for this repo — not for a human reader. Cover: the stack/framework, key",
    "services or modules, and any conventions implied by the file layout (branch",
    "naming, folder structure, etc). Be concrete and specific, skip filler like",
    '"this repo contains...". Output only the summary, no headings or markdown.',
    "",
    snapshot.description ? `Description: ${snapshot.description}` : "",
    snapshot.language ? `Primary language: ${snapshot.language}` : "",
    snapshot.topics.length > 0 ? `Topics: ${snapshot.topics.join(", ")}` : "",
    snapshot.tree.length > 0 ? `Top-level files/dirs: ${snapshot.tree.join(", ")}` : "",
    "",
    snapshot.readme ? `README:\n"""\n${snapshot.readme}\n"""` : "(no README found)",
    "",
    snapshot.packageJson ? `package.json:\n"""\n${snapshot.packageJson}\n"""` : "",
  ].filter(Boolean);

  return runClaudeText(instructions.join("\n"), { timeoutMs: 90_000 });
}

/** "Generate ✦" in the task detail drawer: breaks a task down into a handful
 * of concrete subtask checklist items. No space context — keeps this from
 * needing to thread spaceId through the drawer's prop chain, which today
 * only carries spaceSlug. */
export async function generateSubtasks(input: {
  title: string;
  description?: string | null;
}): Promise<string[]> {
  const instructions = [
    "Break the following task down into 3-8 concrete, actionable subtasks — short",
    "checklist items a developer would tick off one by one. Order them in the sequence",
    "they'd actually be done in. Don't restate the task title as a single subtask, and",
    "don't invent scope that isn't implied by the task.",
    "",
    `Title: ${input.title}`,
    input.description ? `Description:\n"""\n${input.description}\n"""` : "",
  ].filter(Boolean);

  return runClaudeJSON(instructions.join("\n"), generatedSubtasksJsonSchema, generatedSubtasksSchema, {
    timeoutMs: 60_000,
    unwrapKey: "subtasks",
  });
}
