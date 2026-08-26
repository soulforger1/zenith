// Shapes stored in `views.config` (a jsonb blob whose structure depends on
// `views.type`) plus the shared filter/sort types every view speaks. Kept
// separate from lib/fields/registry.ts to avoid a cycle: the registry is
// built from issues+customFields and doesn't need to know about views, while
// views (and the filter bar / settings popover) consume the registry.

export type FilterOperator = "is" | "is_not" | "contains" | "is_empty" | "is_not_empty" | "before" | "after";

export type FilterRule = {
  fieldId: string;
  operator: FilterOperator;
  value?: unknown;
};

export type SortRule = {
  fieldId: string;
  direction: "asc" | "desc";
};

export type TableViewConfig = {
  visibleFieldIds: string[];
  sort: SortRule[];
  groupByFieldId: string | null;
  filters: FilterRule[];
};

export type BoardViewConfig = {
  groupByFieldId: string;
  visibleFieldIds: string[];
  filters: FilterRule[];
};

export type RoadmapViewConfig = {
  startFieldId: string | null;
  endFieldId: string | null;
  groupByFieldId: string | null;
  filters: FilterRule[];
  zoom: "week" | "month" | "quarter";
};

export type ViewConfig = TableViewConfig | BoardViewConfig | RoadmapViewConfig;
