"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createRepo, deleteRepo, getRepoById, setRepoCache, updateRepo } from "@/lib/db/queries/repos";
import { getRepoSnapshot, parseRepoUrl } from "@/lib/github/client";
import { summarizeRepoContext } from "@/lib/ai/prompts";

const repoInputSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(50),
  url: z.string().trim().min(1, "Repo URL is required").max(300),
});

export async function createRepoAction(
  spaceId: string,
  spaceSlug: string,
  input: { name: string; url: string },
): Promise<{ error?: string }> {
  const parsed = repoInputSchema.safeParse(input);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid input." };
  try {
    parseRepoUrl(parsed.data.url);
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Invalid repo URL." };
  }
  await createRepo({ spaceId, ...parsed.data });
  revalidatePath(`/spaces/${spaceSlug}/settings`);
  return {};
}

export async function updateRepoAction(
  id: string,
  spaceSlug: string,
  input: { name?: string; url?: string },
): Promise<{ error?: string }> {
  const parsed = repoInputSchema.partial().safeParse(input);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid input." };
  if (parsed.data.url) {
    try {
      parseRepoUrl(parsed.data.url);
    } catch (err) {
      return { error: err instanceof Error ? err.message : "Invalid repo URL." };
    }
  }
  await updateRepo(id, parsed.data);
  revalidatePath(`/spaces/${spaceSlug}/settings`);
  return {};
}

export async function deleteRepoAction(id: string, spaceSlug: string): Promise<void> {
  await deleteRepo(id);
  revalidatePath(`/spaces/${spaceSlug}/settings`);
}

/** Manual "Sync" — the only way a repo's cached context is ever (re)generated.
 * Never called from task-parsing; that only ever reads the cache. */
export async function syncRepoContextAction(id: string, spaceSlug: string): Promise<{ error?: string }> {
  const repo = await getRepoById(id);
  if (!repo) return { error: "Repo not found." };

  try {
    const snapshot = await getRepoSnapshot(repo.url);
    const summary = await summarizeRepoContext(snapshot);
    await setRepoCache(id, { cachedContext: summary, cachedAt: new Date() });
    revalidatePath(`/spaces/${spaceSlug}/settings`);
    return {};
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Couldn't sync from GitHub." };
  }
}
