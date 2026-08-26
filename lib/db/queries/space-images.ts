import "server-only";

import { asc, eq } from "drizzle-orm";

import { db } from "@/lib/db";
import { spaceImages } from "@/lib/db/schema";

export async function getSpaceImages(spaceId: string) {
  return db
    .select()
    .from(spaceImages)
    .where(eq(spaceImages.spaceId, spaceId))
    .orderBy(asc(spaceImages.createdAt));
}

export async function addSpaceImage(input: { spaceId: string; dataUrl: string; label?: string | null }) {
  const [image] = await db
    .insert(spaceImages)
    .values({ spaceId: input.spaceId, dataUrl: input.dataUrl, label: input.label ?? null })
    .returning();
  return image;
}

export async function deleteSpaceImage(id: string) {
  await db.delete(spaceImages).where(eq(spaceImages.id, id));
}
