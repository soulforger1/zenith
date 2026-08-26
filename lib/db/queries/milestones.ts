import "server-only";

import { asc, eq } from "drizzle-orm";

import { db } from "@/lib/db";
import { milestones } from "@/lib/db/schema";

export async function getMilestonesForSpace(spaceId: string) {
  return db
    .select()
    .from(milestones)
    .where(eq(milestones.spaceId, spaceId))
    .orderBy(asc(milestones.dueDate), asc(milestones.createdAt));
}

export async function getMilestoneById(id: string) {
  const [milestone] = await db.select().from(milestones).where(eq(milestones.id, id)).limit(1);
  return milestone ?? null;
}

export async function createMilestone(input: {
  spaceId: string;
  title: string;
  description?: string | null;
  dueDate?: string | null;
}) {
  const [milestone] = await db
    .insert(milestones)
    .values({
      spaceId: input.spaceId,
      title: input.title,
      description: input.description ?? null,
      dueDate: input.dueDate ?? null,
    })
    .returning();
  return milestone;
}

export async function updateMilestone(
  id: string,
  input: { title?: string; description?: string | null; dueDate?: string | null },
) {
  const [milestone] = await db
    .update(milestones)
    .set({ ...input, updatedAt: new Date() })
    .where(eq(milestones.id, id))
    .returning();
  return milestone ?? null;
}

export async function setMilestoneClosed(id: string, isClosed: boolean) {
  const [milestone] = await db
    .update(milestones)
    .set({
      status: isClosed ? "closed" : "open",
      closedAt: isClosed ? new Date() : null,
      updatedAt: new Date(),
    })
    .where(eq(milestones.id, id))
    .returning();
  return milestone ?? null;
}

export async function deleteMilestone(id: string) {
  await db.delete(milestones).where(eq(milestones.id, id));
}
