import "server-only";

import { asc, eq } from "drizzle-orm";

import { db } from "@/lib/db";
import { spaces } from "@/lib/db/schema";
import { slugify } from "@/lib/slug";

export async function getSpaces() {
  return db.select().from(spaces).orderBy(asc(spaces.name));
}

export async function getSpaceBySlug(slug: string) {
  const [space] = await db.select().from(spaces).where(eq(spaces.slug, slug)).limit(1);
  return space ?? null;
}

export async function getSpaceById(id: string) {
  const [space] = await db.select().from(spaces).where(eq(spaces.id, id)).limit(1);
  return space ?? null;
}

/** Generates a unique slug from a name, appending -2, -3, ... on collision. */
async function generateUniqueSlug(name: string): Promise<string> {
  const base = slugify(name) || "space";
  let candidate = base;
  let suffix = 2;
  while (await getSpaceBySlug(candidate)) {
    candidate = `${base}-${suffix}`;
    suffix += 1;
  }
  return candidate;
}

export async function createSpace(input: { name: string; description?: string | null }) {
  const slug = await generateUniqueSlug(input.name);
  const [space] = await db
    .insert(spaces)
    .values({ name: input.name, description: input.description ?? null, slug })
    .returning();
  return space;
}

export async function updateSpace(
  id: string,
  input: { name?: string; description?: string | null; context?: string | null },
) {
  const [space] = await db
    .update(spaces)
    .set({ ...input, updatedAt: new Date() })
    .where(eq(spaces.id, id))
    .returning();
  return space ?? null;
}

export async function deleteSpace(id: string) {
  await db.delete(spaces).where(eq(spaces.id, id));
}
