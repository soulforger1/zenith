import "server-only";

import { and, asc, eq, max, ne } from "drizzle-orm";

import { db } from "@/lib/db";
import { customFields, views, type ViewType } from "@/lib/db/schema";
import { positionAtEnd } from "@/lib/position";
import type { BoardViewConfig, RoadmapViewConfig, TableViewConfig, ViewConfig } from "@/lib/views/types";

export async function getViewsForSpace(spaceId: string) {
  return db.select().from(views).where(eq(views.spaceId, spaceId)).orderBy(asc(views.position));
}

export async function getViewById(id: string) {
  const [view] = await db.select().from(views).where(eq(views.id, id)).limit(1);
  return view ?? null;
}

export async function createView(input: { spaceId: string; name: string; type: ViewType; config: ViewConfig }) {
  const [{ value: maxPosition }] = await db
    .select({ value: max(views.position) })
    .from(views)
    .where(eq(views.spaceId, input.spaceId));

  const [view] = await db
    .insert(views)
    .values({
      spaceId: input.spaceId,
      name: input.name,
      type: input.type,
      config: input.config,
      position: positionAtEnd(maxPosition ?? null),
    })
    .returning();
  return view;
}

export async function updateView(
  id: string,
  input: Partial<{ name: string; config: ViewConfig; position: number; isDefault: boolean }>,
) {
  // Setting a new default unsets every other view's default flag in the same
  // space first, so exactly one view stays `isDefault: true`.
  if (input.isDefault) {
    const current = await getViewById(id);
    if (current) {
      await db
        .update(views)
        .set({ isDefault: false, updatedAt: new Date() })
        .where(and(eq(views.spaceId, current.spaceId), ne(views.id, id)));
    }
  }

  const [view] = await db
    .update(views)
    .set({ ...input, config: input.config as Record<string, unknown> | undefined, updatedAt: new Date() })
    .where(eq(views.id, id))
    .returning();
  return view ?? null;
}

/** Rejects deleting a space's last remaining view — there must always be
 * something for a bare `/spaces/[slug]` to redirect to. */
export async function deleteView(id: string): Promise<{ error?: string }> {
  const view = await getViewById(id);
  if (!view) return {};
  const remaining = await getViewsForSpace(view.spaceId);
  if (remaining.length <= 1) return { error: "A space needs at least one view." };

  await db.delete(views).where(eq(views.id, id));
  if (view.isDefault) {
    const next = remaining.find((v) => v.id !== id);
    if (next) await db.update(views).set({ isDefault: true }).where(eq(views.id, next.id));
  }
  return {};
}

const DEFAULT_TABLE_CONFIG: TableViewConfig = {
  visibleFieldIds: ["status", "priority"],
  sort: [],
  groupByFieldId: null,
  filters: [],
};

const DEFAULT_BOARD_CONFIG: BoardViewConfig = {
  groupByFieldId: "status",
  visibleFieldIds: ["dueDate", "branch", "estimate"],
  filters: [],
};

const DEFAULT_ROADMAP_CONFIG: RoadmapViewConfig = {
  startFieldId: null,
  endFieldId: null,
  groupByFieldId: null,
  filters: [],
  zoom: "month",
};

const STARTER_FIELDS: Array<{ key: string; name: string; type: "multi_select" | "single_select"; options: { name: string; color: string }[] }> = [
  { key: "assignees", name: "Assignees", type: "multi_select", options: [] },
  {
    key: "size",
    name: "Size",
    type: "single_select",
    options: [
      { name: "XS", color: "gray" },
      { name: "S", color: "blue" },
      { name: "M", color: "yellow" },
      { name: "L", color: "orange" },
      { name: "XL", color: "red" },
    ],
  },
];

/** If a space has no views yet (brand new, or an existing space visited for
 * the first time after this feature shipped), seed the standard trio —
 * Table (default), Board, Roadmap — plus the two starter custom fields
 * (Assignees, Size) referenced by the Table/Board defaults above. Idempotent:
 * returns the existing views untouched if there are already any. */
export async function getOrCreateDefaultViewsForSpace(spaceId: string) {
  const existing = await getViewsForSpace(spaceId);
  if (existing.length > 0) return existing;

  // One position lookup + one batched insert for both starter fields,
  // instead of a select-then-insert round trip per field — positions are
  // computed in memory by threading positionAtEnd forward, same pattern
  // lib/db/queries/issues.ts's createIssues bulk-insert already uses.
  const [{ value: maxFieldPosition }] = await db
    .select({ value: max(customFields.position) })
    .from(customFields)
    .where(eq(customFields.spaceId, spaceId));

  let fieldPosition = maxFieldPosition ?? null;
  const fieldRows = STARTER_FIELDS.map((starter) => {
    fieldPosition = positionAtEnd(fieldPosition);
    return {
      spaceId,
      key: starter.key,
      name: starter.name,
      type: starter.type,
      options: starter.options.map((o) => ({ id: crypto.randomUUID(), name: o.name, color: o.color })),
      position: fieldPosition,
    };
  });
  await db.insert(customFields).values(fieldRows);

  // Board stays the default landing view (carried forward from this app's
  // earlier "Board is the default view" decision) even though Table is
  // listed first in the tab order — `isDefault` and tab position are
  // independent, same as GitHub Projects.
  const rows = [
    { spaceId, name: "Table", type: "table" as const, position: positionAtEnd(null), isDefault: false, config: DEFAULT_TABLE_CONFIG },
    { spaceId, name: "Board", type: "board" as const, position: positionAtEnd(positionAtEnd(null)), isDefault: true, config: DEFAULT_BOARD_CONFIG },
    {
      spaceId,
      name: "Roadmap",
      type: "roadmap" as const,
      position: positionAtEnd(positionAtEnd(positionAtEnd(null))),
      isDefault: false,
      config: DEFAULT_ROADMAP_CONFIG,
    },
  ];

  return db
    .insert(views)
    .values(rows.map((r) => ({ ...r, config: r.config as Record<string, unknown> })))
    .returning();
}
