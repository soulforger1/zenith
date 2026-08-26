"use client";

import { useMemo, useState, useTransition } from "react";
import {
  closestCorners,
  DndContext,
  DragOverlay,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import { toast } from "sonner";

import { updateIssueGroupAction } from "@/lib/actions/issues";
import type { IssuePriority, IssueStatus } from "@/lib/db/schema";
import { positionBetween } from "@/lib/position";
import { buildFieldPatch, buildFieldRegistry, getFieldDef, type CustomFieldRow, type FieldDef } from "@/lib/fields/registry";
import { applyFilters } from "@/lib/fields/filter";
import type { BoardViewConfig } from "@/lib/views/types";
import { KanbanCard } from "@/components/board/kanban-card";
import { KanbanColumn } from "@/components/board/kanban-column";
import type { DrawerTask } from "@/components/layout/app-shell-context";

export type KanbanIssue = DrawerTask & { position: number };

const NO_VALUE_KEY = "__none__";

/** Buckets a flat issue list by `field`'s value into `{ [optionId]: issues[] }`
 * (plus a NO_VALUE_KEY bucket) — the Board-specific version of
 * lib/fields/filter.ts's groupIssuesBy, kept separate because drag-and-drop
 * needs a plain keyed record it can mutate per-bucket, not the array-of-groups
 * shape the read-only Table/Roadmap views use. */
function groupByField(list: KanbanIssue[], field: FieldDef): Record<string, KanbanIssue[]> {
  const grouped: Record<string, KanbanIssue[]> = {};
  for (const opt of field.options) grouped[opt.id] = [];
  grouped[NO_VALUE_KEY] = [];
  for (const issue of list) {
    const raw = field.getValue(issue);
    const key = raw === null || raw === undefined || raw === "" ? NO_VALUE_KEY : String(raw);
    if (!grouped[key]) grouped[key] = [];
    grouped[key].push(issue);
  }
  for (const key of Object.keys(grouped)) grouped[key].sort((a, b) => a.position - b.position);
  return grouped;
}

/** Returns a copy of `issue` with its value for `field` updated — used to
 * reflect a drag-and-drop move locally before the server action round-trips.
 * Only ever called with single_select/iteration fields (Board's group-by is
 * restricted to those in the view-settings popover), so every built-in case
 * here is a single scalar column. */
function withGroupValue(issue: KanbanIssue, field: FieldDef, value: string | null): KanbanIssue {
  if (!field.isBuiltIn) {
    return { ...issue, customFieldValues: { ...issue.customFieldValues, [field.id]: value } };
  }
  switch (field.id) {
    case "status":
      return { ...issue, status: (value ?? "backlog") as IssueStatus };
    case "priority":
      return { ...issue, priority: (value ?? "medium") as IssuePriority };
    case "milestoneId":
      return { ...issue, milestoneId: value };
    default:
      return issue;
  }
}

export function KanbanBoard({
  view,
  issues,
  spaceId,
  spaceSlug,
  customFields,
  milestones,
  repos,
}: {
  view: { id: string; config: BoardViewConfig };
  issues: KanbanIssue[];
  spaceId: string;
  spaceSlug: string;
  customFields: CustomFieldRow[];
  milestones: { id: string; title: string }[];
  repos: { id: string; name: string }[];
}) {
  // Built client-side — FieldDef.getValue is a function, which can't cross
  // the RSC serialization boundary from the server component page.
  const registry = useMemo(() => buildFieldRegistry(customFields, { milestones, repos }), [customFields, milestones, repos]);
  const groupField = getFieldDef(registry, view.config.groupByFieldId) ?? getFieldDef(registry, "status")!;
  const [columns, setColumns] = useState(() => groupByField(issues, groupField));
  const [activeIssue, setActiveIssue] = useState<KanbanIssue | null>(null);
  const [, startTransition] = useTransition();

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 6 } }));

  const columnKeys = useMemo(() => {
    const optionKeys = groupField.options.map((o) => o.id);
    return (columns[NO_VALUE_KEY]?.length ?? 0) > 0 ? [...optionKeys, NO_VALUE_KEY] : optionKeys;
  }, [groupField, columns]);

  // Filtering only affects what's rendered, never `columns` itself — the
  // drag handlers below rely on the full per-bucket arrays for correct
  // fractional position math, same trick as the earlier milestone-only
  // filter this component had before views existed.
  const visibleColumns = useMemo(() => {
    if (view.config.filters.length === 0) return columns;
    const filtered: Record<string, KanbanIssue[]> = {};
    for (const key of Object.keys(columns)) filtered[key] = applyFilters(columns[key], view.config.filters, registry);
    return filtered;
  }, [columns, view.config.filters, registry]);

  function findColumnOf(id: string): string | undefined {
    return Object.keys(columns).find((key) => columns[key].some((issue) => issue.id === id));
  }

  function handleDragStart(event: DragStartEvent) {
    const id = String(event.active.id);
    const key = findColumnOf(id);
    if (!key) return;
    setActiveIssue(columns[key].find((issue) => issue.id === id) ?? null);
  }

  function handleDragEnd(event: DragEndEvent) {
    setActiveIssue(null);
    const { active, over } = event;
    if (!over) return;

    const activeId = String(active.id);
    const overId = String(over.id);
    const sourceKey = findColumnOf(activeId);
    if (!sourceKey) return;
    const destKey = columnKeys.includes(overId) ? overId : findColumnOf(overId);
    if (!destKey) return;

    const sourceList = [...columns[sourceKey]];
    const activeIndex = sourceList.findIndex((issue) => issue.id === activeId);
    if (activeIndex === -1) return;
    const [moved] = sourceList.splice(activeIndex, 1);

    const destList = sourceKey === destKey ? sourceList : [...(columns[destKey] ?? [])];
    let overIndex = destList.findIndex((issue) => issue.id === overId);
    if (overIndex === -1) overIndex = destList.length;

    const before = destList[overIndex - 1]?.position ?? null;
    const after = destList[overIndex]?.position ?? null;
    const newPosition = positionBetween(before, after);
    const newValue = destKey === NO_VALUE_KEY ? null : destKey;

    const updatedMoved = { ...withGroupValue(moved, groupField, newValue), position: newPosition };
    destList.splice(overIndex, 0, updatedMoved);

    setColumns((prev) => ({
      ...prev,
      [sourceKey]: sourceKey === destKey ? destList : sourceList,
      [destKey]: destList,
    }));

    const patch = buildFieldPatch(groupField, newValue);
    startTransition(() => {
      updateIssueGroupAction(activeId, spaceSlug, patch, newPosition).catch(() => {
        toast.error("Couldn't move the issue. It may not be saved — refresh to check.");
      });
    });
  }

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCorners}
      onDragStart={handleDragStart}
      onDragEnd={handleDragEnd}
    >
      <div className="flex items-start gap-4 overflow-x-auto pb-2">
        {columnKeys.map((key) => {
          const option = groupField.options.find((o) => o.id === key);
          const title = option ? option.label.toUpperCase() : `NO ${groupField.name.toUpperCase()}`;
          return (
            <KanbanColumn
              key={key}
              id={key}
              title={title}
              issues={visibleColumns[key] ?? []}
              spaceId={spaceId}
              spaceSlug={spaceSlug}
              groupFieldIsStatus={groupField.id === "status"}
              registry={registry}
              visibleFieldIds={view.config.visibleFieldIds}
              milestones={milestones}
              repos={repos}
            />
          );
        })}
      </div>
      <DragOverlay>
        {activeIssue ? (
          <KanbanCard
            issue={activeIssue}
            spaceSlug={spaceSlug}
            registry={registry}
            visibleFieldIds={view.config.visibleFieldIds}
            milestones={milestones}
            repos={repos}
            overlay
          />
        ) : null}
      </DragOverlay>
    </DndContext>
  );
}
