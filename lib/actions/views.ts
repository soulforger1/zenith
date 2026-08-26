"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { createView, deleteView, getViewById, updateView } from "@/lib/db/queries/views";
import { viewTypeValues } from "@/lib/db/schema";
import type { ViewConfig } from "@/lib/views/types";

const DEFAULT_CONFIG_BY_TYPE: Record<(typeof viewTypeValues)[number], ViewConfig> = {
  table: { visibleFieldIds: ["status", "priority"], sort: [], groupByFieldId: null, filters: [] },
  board: { groupByFieldId: "status", visibleFieldIds: ["dueDate", "branch", "estimate"], filters: [] },
  roadmap: { startFieldId: null, endFieldId: null, groupByFieldId: null, filters: [], zoom: "month" },
};

const createViewSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(60),
  type: z.enum(viewTypeValues),
});

/** Creates a view with a sensible default config for its type, then sends the
 * caller straight to it — used by the "+" new-view control in the tab bar. */
export async function createViewAction(
  spaceId: string,
  spaceSlug: string,
  input: { name: string; type: string },
): Promise<{ error?: string }> {
  const parsed = createViewSchema.safeParse(input);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid view." };

  const view = await createView({
    spaceId,
    name: parsed.data.name,
    type: parsed.data.type,
    config: DEFAULT_CONFIG_BY_TYPE[parsed.data.type],
  });
  revalidatePath(`/spaces/${spaceSlug}`);
  redirect(`/spaces/${spaceSlug}/views/${view.id}`);
}

export async function renameViewAction(id: string, spaceSlug: string, name: string): Promise<{ error?: string }> {
  const trimmed = name.trim();
  if (!trimmed) return { error: "Name is required." };
  await updateView(id, { name: trimmed });
  revalidatePath(`/spaces/${spaceSlug}`);
  return {};
}

/** Autosave from the filter bar / view-settings popover — pass the view's
 * whole new config each time (small object, cheap to replace wholesale). */
export async function updateViewConfigAction(id: string, spaceSlug: string, config: ViewConfig): Promise<void> {
  await updateView(id, { config });
  revalidatePath(`/spaces/${spaceSlug}`);
}

/** "Duplicate" from a view tab's "..." menu — copies name/type/config as a
 * new, non-default view right after the original. */
export async function duplicateViewAction(id: string, spaceSlug: string): Promise<{ error?: string }> {
  const source = await getViewById(id);
  if (!source) return { error: "View not found." };
  const view = await createView({
    spaceId: source.spaceId,
    name: `${source.name} copy`,
    type: source.type as (typeof viewTypeValues)[number],
    config: source.config as ViewConfig,
  });
  revalidatePath(`/spaces/${spaceSlug}`);
  redirect(`/spaces/${spaceSlug}/views/${view.id}`);
}

export async function setDefaultViewAction(id: string, spaceSlug: string): Promise<void> {
  await updateView(id, { isDefault: true });
  revalidatePath(`/spaces/${spaceSlug}`);
}

export async function deleteViewAction(id: string, spaceSlug: string): Promise<{ error?: string }> {
  const result = await deleteView(id);
  if (result.error) return result;
  revalidatePath(`/spaces/${spaceSlug}`);
  return {};
}
