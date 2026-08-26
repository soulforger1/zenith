/** Resolves a *name* Claude returned (a repo name or a milestone title) back
 * to a real id — matched case-insensitively against the space's actual
 * repos/milestones, so a hallucinated or slightly-off name never gets
 * attached to an issue. Shared by both the single-task and bulk-list parse
 * routes, for both repo and milestone matching. */
export function resolveIdByName(
  name: string | undefined,
  items: Array<{ id: string; name: string }>,
): string | null {
  if (!name) return null;
  const match = items.find((item) => item.name.toLowerCase() === name.toLowerCase());
  return match?.id ?? null;
}

/** Plural form for multi-value fields (repos) — resolves each name the same
 * way as `resolveIdByName`, drops any that don't match, and dedupes. */
export function resolveIdsByNames(
  names: string[] | undefined,
  items: Array<{ id: string; name: string }>,
): string[] {
  if (!names || names.length === 0) return [];
  const ids = names.map((name) => resolveIdByName(name, items)).filter((id): id is string => id !== null);
  return [...new Set(ids)];
}
