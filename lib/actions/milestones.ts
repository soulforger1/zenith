"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import {
  createMilestone,
  deleteMilestone,
  setMilestoneClosed,
  updateMilestone,
} from "@/lib/db/queries/milestones";

const milestoneInputSchema = z.object({
  title: z.string().trim().min(1, "Title is required").max(150),
  description: z.string().trim().max(2000).optional(),
  dueDate: z.string().optional(),
});

export type MilestoneFormState = { error?: string } | undefined;

export async function createMilestoneAction(
  spaceId: string,
  spaceSlug: string,
  _prevState: MilestoneFormState,
  formData: FormData,
): Promise<MilestoneFormState> {
  const parsed = milestoneInputSchema.safeParse({
    title: formData.get("title"),
    description: formData.get("description") || undefined,
    dueDate: formData.get("dueDate") || undefined,
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Invalid input." };
  }

  await createMilestone({ spaceId, ...parsed.data });
  revalidatePath(`/spaces/${spaceSlug}/milestones`);
  return undefined;
}

export async function updateMilestoneAction(
  id: string,
  spaceSlug: string,
  _prevState: MilestoneFormState,
  formData: FormData,
): Promise<MilestoneFormState> {
  const parsed = milestoneInputSchema.safeParse({
    title: formData.get("title"),
    description: formData.get("description") || undefined,
    dueDate: formData.get("dueDate") || undefined,
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Invalid input." };
  }

  await updateMilestone(id, parsed.data);
  revalidatePath(`/spaces/${spaceSlug}/milestones`);
  revalidatePath(`/spaces/${spaceSlug}/milestones/${id}`);
  return undefined;
}

export async function toggleMilestoneClosedAction(
  id: string,
  spaceSlug: string,
  isClosed: boolean,
): Promise<void> {
  await setMilestoneClosed(id, isClosed);
  revalidatePath(`/spaces/${spaceSlug}/milestones`);
  revalidatePath(`/spaces/${spaceSlug}/milestones/${id}`);
}

export async function deleteMilestoneAction(id: string, spaceSlug: string): Promise<void> {
  await deleteMilestone(id);
  revalidatePath(`/spaces/${spaceSlug}/milestones`);
}
