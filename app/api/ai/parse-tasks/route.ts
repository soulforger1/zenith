import { NextResponse } from "next/server";

import { parseTasksFromText } from "@/lib/ai/prompts";
import { parseTasksRequestSchema } from "@/lib/ai/schemas";
import { resolveAiCustomFields, type CustomFieldRow } from "@/lib/ai/field-resolver";
import { getSpaceById } from "@/lib/db/queries/spaces";
import { getReposForSpace } from "@/lib/db/queries/repos";
import { getMilestonesForSpace } from "@/lib/db/queries/milestones";
import { getCustomFieldsForSpace } from "@/lib/db/queries/custom-fields";
import { resolveIdByName, resolveIdsByNames } from "@/lib/name-match";
import type { FieldOption, IterationOption } from "@/lib/db/schema";

function optionLabels(field: { type: string; options: FieldOption[] | IterationOption[] }): string[] {
  if (field.type === "single_select" || field.type === "multi_select") return (field.options as FieldOption[]).map((o) => o.name);
  if (field.type === "iteration") return (field.options as IterationOption[]).map((o) => o.title);
  return [];
}

export const maxDuration = 30;

export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  const parsed = parseTasksRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.issues[0]?.message ?? "Invalid request." }, { status: 400 });
  }

  const { text, spaceId } = parsed.data;

  let spaceContext: string | null = null;
  let repos: Awaited<ReturnType<typeof getReposForSpace>> = [];
  let milestones: Awaited<ReturnType<typeof getMilestonesForSpace>> = [];
  let fields: CustomFieldRow[] = [];
  if (spaceId) {
    const [space, spaceRepos, spaceMilestones, spaceCustomFields] = await Promise.all([
      getSpaceById(spaceId),
      getReposForSpace(spaceId),
      getMilestonesForSpace(spaceId),
      getCustomFieldsForSpace(spaceId),
    ]);
    spaceContext = space?.context ?? null;
    repos = spaceRepos;
    milestones = spaceMilestones;
    fields = spaceCustomFields;
  }

  try {
    const tasks = await parseTasksFromText({
      text,
      spaceContext,
      repos: repos.map((r) => ({ name: r.name, context: r.cachedContext })),
      milestones: milestones.map((m) => ({ title: m.title, description: m.description })),
      customFields: fields.map((f) => ({ key: f.key, name: f.name, type: f.type, options: optionLabels(f) })),
    });
    const milestoneOptions = milestones.map((m) => ({ id: m.id, name: m.title }));

    // Sequential, not parallel — so if two tasks in the same paste both
    // imply the same missing field (e.g. two "Size: ..." lines), the second
    // resolution sees the field the first one just created instead of
    // racing to create a duplicate.
    const resolvedTasks = [];
    for (const task of tasks) {
      let customFieldValues: Record<string, unknown> = {};
      if (spaceId && (task.fieldValues?.length || task.newFields?.length)) {
        const resolved = await resolveAiCustomFields({
          spaceId,
          customFields: fields,
          newFields: task.newFields,
          fieldValues: task.fieldValues,
        });
        customFieldValues = resolved.customFieldValues;
        fields = resolved.fields;
      }
      resolvedTasks.push({
        ...task,
        repoIds: resolveIdsByNames(task.repos, repos),
        milestoneId: resolveIdByName(task.milestone, milestoneOptions),
        customFieldValues,
      });
    }

    return NextResponse.json({
      tasks: resolvedTasks,
      repos: repos.map((r) => ({ id: r.id, name: r.name })),
      milestones: milestones.map((m) => ({ id: m.id, title: m.title })),
      customFields: fields.map((f) => ({ id: f.id, name: f.name, type: f.type, options: f.options })),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to parse the tasks.";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
