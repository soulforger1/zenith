import { NextResponse } from "next/server";

import { parseTaskFromText } from "@/lib/ai/prompts";
import { parseTaskRequestSchema, type AttachedImage } from "@/lib/ai/schemas";
import { resolveAiCustomFields, type CustomFieldRow } from "@/lib/ai/field-resolver";
import { getSpaceById } from "@/lib/db/queries/spaces";
import { getSpaceImages } from "@/lib/db/queries/space-images";
import { getReposForSpace } from "@/lib/db/queries/repos";
import { getMilestonesForSpace } from "@/lib/db/queries/milestones";
import { getCustomFieldsForSpace } from "@/lib/db/queries/custom-fields";
import { parseDataUrl } from "@/lib/data-url";
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
  const parsed = parseTaskRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.issues[0]?.message ?? "Invalid request." }, { status: 400 });
  }

  const { text, spaceId, attachedImage } = parsed.data;

  let spaceContext: string | null = null;
  let spaceImages: AttachedImage[] = [];
  let repos: Awaited<ReturnType<typeof getReposForSpace>> = [];
  let milestones: Awaited<ReturnType<typeof getMilestonesForSpace>> = [];
  let customFields: Awaited<ReturnType<typeof getCustomFieldsForSpace>> = [];
  if (spaceId) {
    const [space, images, spaceRepos, spaceMilestones, spaceCustomFields] = await Promise.all([
      getSpaceById(spaceId),
      getSpaceImages(spaceId),
      getReposForSpace(spaceId),
      getMilestonesForSpace(spaceId),
      getCustomFieldsForSpace(spaceId),
    ]);
    spaceContext = space?.context ?? null;
    spaceImages = images
      .map((img) => parseDataUrl(img.dataUrl))
      .filter((img): img is AttachedImage => img !== null);
    repos = spaceRepos;
    milestones = spaceMilestones;
    customFields = spaceCustomFields;
  }

  try {
    const task = await parseTaskFromText({
      text,
      spaceContext,
      spaceImages,
      attachedImage,
      repos: repos.map((r) => ({ name: r.name, context: r.cachedContext })),
      milestones: milestones.map((m) => ({ title: m.title, description: m.description })),
      customFields: customFields.map((f) => ({ key: f.key, name: f.name, type: f.type, options: optionLabels(f) })),
    });
    const repoIds = resolveIdsByNames(task.repos, repos);
    const milestoneId = resolveIdByName(task.milestone, milestones.map((m) => ({ id: m.id, name: m.title })));

    let customFieldValues: Record<string, unknown> = {};
    let resultFields: CustomFieldRow[] = customFields;
    if (spaceId && (task.fieldValues?.length || task.newFields?.length)) {
      const resolved = await resolveAiCustomFields({
        spaceId,
        customFields,
        newFields: task.newFields,
        fieldValues: task.fieldValues,
      });
      customFieldValues = resolved.customFieldValues;
      resultFields = resolved.fields;
    }

    return NextResponse.json({
      task: { ...task, repoIds, milestoneId, customFieldValues },
      repos: repos.map((r) => ({ id: r.id, name: r.name })),
      milestones: milestones.map((m) => ({ id: m.id, title: m.title })),
      customFields: resultFields.map((f) => ({ id: f.id, name: f.name, type: f.type, options: f.options })),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to parse the task.";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
