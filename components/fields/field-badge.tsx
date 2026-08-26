import { format } from "date-fns";

import { cn } from "@/lib/utils";
import { fieldColorChipClass } from "@/lib/fields/colors";
import type { FieldDef, NormalizedOption } from "@/lib/fields/registry";

function isEmpty(value: unknown): boolean {
  return value === null || value === undefined || value === "" || (Array.isArray(value) && value.length === 0);
}

/** Read-only rendering of a single field value — used in table cells and
 * Kanban card badges. Switches on `field.type`, with a special case for
 * multi_select fields that have no fixed option list (built-in `tags`,
 * free-text values rather than option ids). */
export function FieldBadge({ field, value }: { field: FieldDef; value: unknown }) {
  if (isEmpty(value)) return <span className="text-muted-foreground">—</span>;

  if (field.id === "branch") {
    return <span className="font-mono text-[10.5px] text-branch">⎇ {String(value)}</span>;
  }

  if (field.type === "date") {
    return (
      <span className="font-mono text-[11px] text-muted-foreground">{format(new Date(String(value)), "MMM d")}</span>
    );
  }

  if (field.type === "single_select" || field.type === "iteration") {
    const opt = field.options.find((o) => o.id === value);
    if (!opt) return <span className="text-muted-foreground">—</span>;
    return <OptionChip opt={opt} />;
  }

  if (field.type === "multi_select") {
    const ids = Array.isArray(value) ? value : [];
    if (field.options.length === 0) {
      return (
        <div className="flex flex-wrap gap-1">
          {ids.map((raw) => (
            <span
              key={String(raw)}
              className="rounded-[5px] bg-muted px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground"
            >
              {String(raw)}
            </span>
          ))}
        </div>
      );
    }
    const opts = ids
      .map((id) => field.options.find((o) => o.id === id))
      .filter((o): o is NormalizedOption => Boolean(o));
    if (opts.length === 0) return <span className="text-muted-foreground">—</span>;
    return (
      <div className="flex flex-wrap gap-1">
        {opts.map((opt) => (
          <OptionChip key={opt.id} opt={opt} />
        ))}
      </div>
    );
  }

  return <span className="truncate text-[12px]">{String(value)}</span>;
}

function OptionChip({ opt }: { opt: NormalizedOption }) {
  return (
    <span className={cn("rounded-[5px] px-1.5 py-0.5 text-[10.5px] font-medium whitespace-nowrap", fieldColorChipClass(opt.color))}>
      {opt.label}
    </span>
  );
}
