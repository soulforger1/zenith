"use client";

import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { FieldDef } from "@/lib/fields/registry";

/** One generic editable input per field type — used for inline cell editing
 * (Table), the task detail drawer's custom-fields section, and the AI paste
 * draft preview. `onChange` fires the resolved value (already coerced to the
 * right shape for that field type) ready to hand to `buildFieldPatch`. */
export function FieldValueInput({
  field,
  value,
  onChange,
}: {
  field: FieldDef;
  value: unknown;
  onChange: (value: unknown) => void;
}) {
  if (field.type === "text") {
    return (
      <Input
        defaultValue={typeof value === "string" ? value : ""}
        onBlur={(e) => onChange(e.target.value.trim() || null)}
        className="text-xs"
      />
    );
  }

  if (field.type === "number") {
    return (
      <Input
        type="number"
        defaultValue={typeof value === "number" ? value : ""}
        onBlur={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
        className="text-xs"
      />
    );
  }

  if (field.type === "date") {
    return (
      <Input
        type="date"
        value={typeof value === "string" ? value : ""}
        onChange={(e) => onChange(e.target.value || null)}
        className="text-xs"
      />
    );
  }

  if (field.type === "single_select" || field.type === "iteration") {
    return (
      <Select value={typeof value === "string" ? value : ""} onValueChange={(v) => onChange(v || null)}>
        <SelectTrigger className="w-full text-xs">
          <SelectValue placeholder="None" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="">None</SelectItem>
          {field.options.map((opt) => (
            <SelectItem key={opt.id} value={opt.id}>
              {opt.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    );
  }

  if (field.type === "multi_select") {
    if (field.options.length === 0) {
      // Free-text multi-value field (built-in "tags") — comma-separated.
      const text = Array.isArray(value) ? (value as string[]).join(", ") : "";
      return (
        <Input
          defaultValue={text}
          onBlur={(e) =>
            onChange(
              e.target.value
                .split(",")
                .map((t) => t.trim())
                .filter(Boolean),
            )
          }
          placeholder="value, value"
          className="text-xs"
        />
      );
    }

    const selected = Array.isArray(value) ? (value as string[]) : [];
    function toggle(id: string) {
      const next = selected.includes(id) ? selected.filter((v) => v !== id) : [...selected, id];
      onChange(next);
    }
    return (
      <div className="flex flex-col gap-1.5">
        {field.options.map((opt) => (
          <label key={opt.id} className="flex items-center gap-2 text-xs">
            <Checkbox checked={selected.includes(opt.id)} onCheckedChange={() => toggle(opt.id)} />
            {opt.label}
          </label>
        ))}
      </div>
    );
  }

  return null;
}
