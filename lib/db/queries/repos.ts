import "server-only";

import { asc, eq } from "drizzle-orm";

import { db } from "@/lib/db";
import { repos } from "@/lib/db/schema";

export async function getReposForSpace(spaceId: string) {
  return db.select().from(repos).where(eq(repos.spaceId, spaceId)).orderBy(asc(repos.name));
}

export async function getRepoById(id: string) {
  const [repo] = await db.select().from(repos).where(eq(repos.id, id)).limit(1);
  return repo ?? null;
}

export async function createRepo(input: { spaceId: string; name: string; url: string }) {
  const [repo] = await db
    .insert(repos)
    .values({ spaceId: input.spaceId, name: input.name, url: input.url })
    .returning();
  return repo;
}

export async function updateRepo(id: string, input: { name?: string; url?: string }) {
  const [repo] = await db
    .update(repos)
    .set({ ...input, updatedAt: new Date() })
    .where(eq(repos.id, id))
    .returning();
  return repo ?? null;
}

/** Writes the AI-generated summary from a manual "Sync" — the only way
 * `cachedContext` ever changes; never touched by task-parsing itself. */
export async function setRepoCache(id: string, input: { cachedContext: string; cachedAt: Date }) {
  const [repo] = await db
    .update(repos)
    .set({ ...input, updatedAt: new Date() })
    .where(eq(repos.id, id))
    .returning();
  return repo ?? null;
}

export async function deleteRepo(id: string) {
  await db.delete(repos).where(eq(repos.id, id));
}
