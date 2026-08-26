"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import {
  createCustomField,
  deleteCustomField,
  updateCustomField,
} from "@/lib/db/queries/custom-fields";
import { customFieldTypeValues } from "@/lib/db/schema";
import { slugify } from "@/lib/slug";

const optionSchema = z.object({
  id: z.string(),
  name: z.string().trim().min(1).max(60),
  color: z.string().trim().min(1).max(20),
});
const iterationSchema = z.object({
  id: z.string(),
  title: z.string().trim().min(1).max(60),
  startDate: z.string(),
  durationDays: z.number().int().min(1).max(365),
});

const fieldInputSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(60),
  type: z.enum(customFieldTypeValues),
  options: z.union([z.array(optionSchema), z.array(iterationSchema)]).default([]),
});

export async function createCustomFieldAction(
  spaceId: string,
  spaceSlug: string,
  input: { name: string; type: string; options?: unknown },
): Promise<{ error?: string }> {
  const parsed = fieldInputSchema.safeParse(input);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid field." };

  await createCustomField({
    spaceId,
    key: slugify(parsed.data.name) || "field",
    name: parsed.data.name,
    type: parsed.data.type,
    options: parsed.data.options as never,
  });
  revalidatePath(`/spaces/${spaceSlug}`);
  return {};
}

export async function updateCustomFieldAction(
  id: string,
  spaceSlug: string,
  input: { name?: string; options?: unknown },
): Promise<{ error?: string }> {
  const parsed = fieldInputSchema.partial().safeParse(input);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid field." };

  await updateCustomField(id, {
    name: parsed.data.name,
    options: parsed.data.options as never,
  });
  revalidatePath(`/spaces/${spaceSlug}`);
  return {};
}

export async function reorderCustomFieldsAction(
  spaceSlug: string,
  updates: { id: string; position: number }[],
): Promise<void> {
  await Promise.all(updates.map((u) => updateCustomField(u.id, { position: u.position })));
  revalidatePath(`/spaces/${spaceSlug}`);
}

export async function deleteCustomFieldAction(id: string, spaceSlug: string): Promise<void> {
  await deleteCustomField(id);
  revalidatePath(`/spaces/${spaceSlug}`);
}
