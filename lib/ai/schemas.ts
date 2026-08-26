import { z } from "zod";

import { customFieldTypeValues, issuePriorityValues } from "@/lib/db/schema";

// A detected value for one of the space's existing custom fields, keyed by
// the field's `key` (not id — the route resolves key -> id, same spirit as
// repo/milestone name resolution). `value` is always a string; the route's
// resolveAiCustomFields coerces it per the field's real type (number/date
// parsing, option-label matching) since a fixed JSON schema can't vary its
// value type per dynamic field.
const aiFieldValueSchema = z.object({
  fieldKey: z.string().min(1).max(60),
  value: z.string().min(1).max(200),
});

// A field the AI thinks should exist but doesn't yet (e.g. "Size: L" with no
// Size field in the space) — the route creates it via createCustomField.
const aiNewFieldSchema = z.object({
  key: z.string().min(1).max(60),
  name: z.string().min(1).max(60),
  type: z.enum(customFieldTypeValues),
  options: z.array(z.string().min(1).max(60)).max(10).optional(),
});

// Shape returned by the "paste a task" AI flow: one raw text blob in,
// one structured task draft out. Validated even though we also ask Claude
// for constrained/JSON output — structured output isn't a 100% guarantee.
export const parsedTaskSchema = z.object({
  title: z.string().min(1).max(200),
  description: z.string().max(2000).optional(),
  priority: z.enum(issuePriorityValues),
  tags: z.array(z.string().min(1).max(30)).max(8).default([]),
  branch: z.string().max(100).optional(),
  estimate: z.string().max(20).optional(),
  dueDate: z.string().optional(), // ISO date (YYYY-MM-DD), if Claude could resolve one
  repos: z.array(z.string().max(100)).max(5).optional(), // repo names (not ids) — resolved to repoIds by the route
  milestone: z.string().max(150).optional(), // milestone title (not id) — resolved to milestoneId by the route
  fieldValues: z.array(aiFieldValueSchema).max(10).optional(),
  newFields: z.array(aiNewFieldSchema).max(3).optional(),
});
export type ParsedTask = z.infer<typeof parsedTaskSchema>;

// Shape returned by the "paste a list" bulk AI flow: one raw text blob in
// (a bullet/numbered/one-per-line list), one structured task per item out.
export const parsedTasksSchema = z.array(parsedTaskSchema).min(1).max(50);
export type ParsedTasks = z.infer<typeof parsedTasksSchema>;

export const attachedImageSchema = z.object({
  mimeType: z.string().min(1),
  data: z.string().min(1), // raw base64, no "data:...;base64," prefix
});
export type AttachedImage = z.infer<typeof attachedImageSchema>;

export const parseTaskRequestSchema = z
  .object({
    text: z.string().max(4000).default(""),
    spaceId: z.string().uuid().optional(),
    attachedImage: attachedImageSchema.optional(),
  })
  .refine((data) => data.text.trim().length >= 3 || data.attachedImage, {
    message: "Paste some text or attach a screenshot.",
  });

export const parseTasksRequestSchema = z
  .object({
    text: z.string().max(8000).default(""),
    spaceId: z.string().uuid().optional(),
  })
  .refine((data) => data.text.trim().length >= 3, {
    message: "Paste a list of tasks.",
  });

// Shape returned by the "Generate subtasks" AI flow in the task detail drawer.
export const generatedSubtasksSchema = z.array(z.string().min(1).max(200)).min(1).max(10);

export const generateSubtasksRequestSchema = z.object({
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(5000).optional(),
});
