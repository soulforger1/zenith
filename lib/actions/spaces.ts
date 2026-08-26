"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { createSpace, deleteSpace, updateSpace } from "@/lib/db/queries/spaces";
import { addSpaceImage, deleteSpaceImage } from "@/lib/db/queries/space-images";

const MAX_IMAGE_BYTES = 4 * 1024 * 1024; // 4MB — stored inline as base64, keep it reasonable

const spaceInputSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(100),
  description: z.string().trim().max(500).optional(),
});

export type SpaceFormState = { error?: string } | undefined;

export async function createSpaceAction(
  _prevState: SpaceFormState,
  formData: FormData,
): Promise<SpaceFormState> {
  const parsed = spaceInputSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") || undefined,
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Invalid input." };
  }

  const space = await createSpace(parsed.data);
  revalidatePath("/spaces");
  redirect(`/spaces/${space.slug}`);
}

export async function updateSpaceAction(
  id: string,
  _prevState: SpaceFormState,
  formData: FormData,
): Promise<SpaceFormState> {
  const parsed = spaceInputSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") || undefined,
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Invalid input." };
  }

  const space = await updateSpace(id, parsed.data);
  revalidatePath("/spaces");
  if (space) revalidatePath(`/spaces/${space.slug}`);
  redirect(`/spaces/${space?.slug ?? ""}/settings`);
}

export async function deleteSpaceAction(id: string): Promise<void> {
  await deleteSpace(id);
  revalidatePath("/spaces");
  redirect("/spaces");
}

/** Autosave for the Settings "context" textarea — features, services, stack,
 * conventions — prepended to every AI paste-task prompt for this space. */
export async function updateSpaceContextAction(
  id: string,
  spaceSlug: string,
  context: string,
): Promise<void> {
  await updateSpace(id, { context: context.trim() || null });
  revalidatePath(`/spaces/${spaceSlug}/settings`);
}

export async function addSpaceImageAction(
  spaceId: string,
  spaceSlug: string,
  file: File,
): Promise<{ error?: string }> {
  if (!file.type.startsWith("image/")) {
    return { error: "Only image files are supported." };
  }
  if (file.size > MAX_IMAGE_BYTES) {
    return { error: "Image is too large (max 4MB)." };
  }
  const buffer = Buffer.from(await file.arrayBuffer());
  const dataUrl = `data:${file.type};base64,${buffer.toString("base64")}`;
  await addSpaceImage({ spaceId, dataUrl, label: file.name });
  revalidatePath(`/spaces/${spaceSlug}/settings`);
  return {};
}

export async function deleteSpaceImageAction(id: string, spaceSlug: string): Promise<void> {
  await deleteSpaceImage(id);
  revalidatePath(`/spaces/${spaceSlug}/settings`);
}
