"use client";

import { useState, useTransition } from "react";
import {
  closestCenter,
  DndContext,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import { SortableContext, useSortable, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { GripVertical, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { deleteCustomFieldAction, reorderCustomFieldsAction } from "@/lib/actions/custom-fields";
import type { CustomFieldType } from "@/lib/db/schema";
import { FieldFormDialog, type FieldSummary } from "@/components/fields/field-form-dialog";
import { Label } from "@/components/ui/label";

const TYPE_LABEL: Record<CustomFieldType, string> = {
  text: "Text",
  number: "Number",
  date: "Date",
  single_select: "Single select",
  multi_select: "Multi select",
  iteration: "Iteration",
};

function FieldRow({ field, spaceId, spaceSlug }: { field: FieldSummary; spaceId: string; spaceSlug: string }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: field.id });
  const style = { transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.5 : 1 };
  const [, startTransition] = useTransition();

  function handleDelete() {
    if (!window.confirm(`Delete field "${field.name}"? Existing values on tasks will be lost.`)) return;
    startTransition(() => {
      deleteCustomFieldAction(field.id, spaceSlug).catch(() => toast.error("Couldn't delete that field."));
    });
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="flex items-center justify-between gap-2 border-b bg-card px-3 py-2 text-[12.5px] last:border-b-0"
    >
      <div className="flex min-w-0 items-center gap-2">
        <button
          type="button"
          {...attributes}
          {...listeners}
          className="cursor-grab text-muted-foreground active:cursor-grabbing"
        >
          <GripVertical className="size-3.5" />
        </button>
        <span className="font-medium">{field.name}</span>
        <span className="rounded-[5px] bg-muted px-1.5 py-0.5 font-mono text-[10.5px] text-muted-foreground">
          {TYPE_LABEL[field.type]}
        </span>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        <FieldFormDialog spaceId={spaceId} spaceSlug={spaceSlug} mode="edit" field={field} />
        <button type="button" onClick={handleDelete} className="text-muted-foreground transition-colors hover:text-destructive">
          <Trash2 className="size-3.5" />
          <span className="sr-only">Delete {field.name}</span>
        </button>
      </div>
    </div>
  );
}

export function FieldManager({
  spaceId,
  spaceSlug,
  fields,
}: {
  spaceId: string;
  spaceSlug: string;
  fields: FieldSummary[];
}) {
  const [ordered, setOrdered] = useState(fields);
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 6 } }));

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const from = ordered.findIndex((f) => f.id === active.id);
    const to = ordered.findIndex((f) => f.id === over.id);
    if (from === -1 || to === -1) return;

    const next = [...ordered];
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);
    setOrdered(next);
    reorderCustomFieldsAction(
      spaceSlug,
      next.map((f, i) => ({ id: f.id, position: (i + 1) * 1000 })),
    ).catch(() => toast.error("Couldn't save the new order."));
  }

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <div>
          <Label className="text-[13px] font-semibold text-foreground/80">Custom fields</Label>
          <p className="text-xs text-muted-foreground">
            Show up as columns in Table, group/filter options in Board, and date ranges in Roadmap.
          </p>
        </div>
        <FieldFormDialog spaceId={spaceId} spaceSlug={spaceSlug} mode="create" />
      </div>

      {ordered.length > 0 ? (
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
          <SortableContext items={ordered.map((f) => f.id)} strategy={verticalListSortingStrategy}>
            <div className="flex flex-col overflow-hidden rounded-lg border">
              {ordered.map((field) => (
                <FieldRow key={field.id} field={field} spaceId={spaceId} spaceSlug={spaceSlug} />
              ))}
            </div>
          </SortableContext>
        </DndContext>
      ) : (
        <p className="rounded-lg border border-dashed p-4 text-center text-xs text-muted-foreground">
          No custom fields yet.
        </p>
      )}
    </div>
  );
}
