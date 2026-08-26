"use client";

import { Search } from "lucide-react";

import type { FieldDef } from "@/lib/fields/registry";
import type { FilterRule } from "@/lib/views/types";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

/** Generic filter bar driven by the field registry — one dropdown per
 * select-type field with defined options (built-ins like status/priority, or
 * a custom single_select/multi_select field), plus a keyword search box
 * across the title and any text-type fields. This is a deliberately
 * simplified stand-in for GitHub's typed filter-query syntax ("status:Done
 * label:bug") — dropdowns instead of a query parser. */
export function ViewFilterBar({
  registry,
  filters,
  onFiltersChange,
  keyword,
  onKeywordChange,
}: {
  registry: FieldDef[];
  filters: FilterRule[];
  onFiltersChange: (filters: FilterRule[]) => void;
  keyword: string;
  onKeywordChange: (value: string) => void;
}) {
  const filterableFields = registry.filter(
    (f) => (f.type === "single_select" || f.type === "multi_select") && f.options.length > 0,
  );

  function valueFor(fieldId: string): string {
    const rule = filters.find((f) => f.fieldId === fieldId);
    return rule ? String(rule.value ?? "") : "";
  }

  function setValue(fieldId: string, value: string) {
    const next = filters.filter((f) => f.fieldId !== fieldId);
    if (value) next.push({ fieldId, operator: "is", value });
    onFiltersChange(next);
  }

  const hasFilters = filters.length > 0 || keyword.trim().length > 0;

  return (
    <div className="flex flex-wrap items-center gap-2">
      <div className="relative">
        <Search className="pointer-events-none absolute top-1/2 left-2 size-3.5 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={keyword}
          onChange={(e) => onKeywordChange(e.target.value)}
          placeholder="Filter by keyword"
          className="w-[170px] pl-7 text-xs"
        />
      </div>
      {filterableFields.map((field) => (
        <Select key={field.id} value={valueFor(field.id)} onValueChange={(v) => setValue(field.id, v ?? "")}>
          <SelectTrigger className="w-[140px] text-xs">
            <SelectValue placeholder={`All ${field.name.toLowerCase()}`} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="">{`All ${field.name.toLowerCase()}`}</SelectItem>
            {field.options.map((opt) => (
              <SelectItem key={opt.id} value={opt.id}>
                {opt.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      ))}
      {hasFilters ? (
        <button
          type="button"
          onClick={() => {
            onFiltersChange([]);
            onKeywordChange("");
          }}
          className="text-xs text-muted-foreground underline-offset-2 hover:text-foreground hover:underline"
        >
          Clear filters
        </button>
      ) : null}
    </div>
  );
}
