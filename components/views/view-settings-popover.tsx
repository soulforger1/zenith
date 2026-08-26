"use client";

import { useState } from "react";
import { Settings2 } from "lucide-react";

import type { FieldDef } from "@/lib/fields/registry";
import type { BoardViewConfig, RoadmapViewConfig, TableViewConfig, ViewConfig } from "@/lib/views/types";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

/** The "View" gear button — field visibility, group-by, sort (Table), and
 * start/end date fields + zoom (Roadmap). Built as a Dialog rather than a
 * true anchored popover to avoid nesting interactive Select controls inside
 * a Menu popup (focus-trap conflicts) — a Dialog is more robust here even if
 * less visually "inline" than GitHub's own panel. */
export function ViewSettingsPopover({
  viewType,
  registry,
  config,
  onChange,
}: {
  viewType: "table" | "board" | "roadmap";
  registry: FieldDef[];
  config: ViewConfig;
  onChange: (config: ViewConfig) => void;
}) {
  const [open, setOpen] = useState(false);

  const visibleFieldIds = "visibleFieldIds" in config ? config.visibleFieldIds : [];
  const groupByFieldId = "groupByFieldId" in config ? config.groupByFieldId : null;

  // Board's drag-and-drop grouping only supports scalar fields — a
  // multi-select field (repo, tags, ...) can't be a group-by there since a
  // card could belong to several buckets at once. Table/Roadmap grouping is
  // multi-value-aware (see lib/fields/filter.ts's groupIssuesBy), so no
  // restriction for those.
  const groupableFields = viewType === "board" ? registry.filter((f) => f.type !== "multi_select") : registry;

  function toggleVisible(fieldId: string, checked: boolean) {
    if (!("visibleFieldIds" in config)) return;
    const next = checked
      ? [...config.visibleFieldIds, fieldId]
      : config.visibleFieldIds.filter((id) => id !== fieldId);
    onChange({ ...config, visibleFieldIds: next });
  }

  function setGroupBy(fieldId: string) {
    if (viewType === "board") {
      onChange({ ...(config as BoardViewConfig), groupByFieldId: fieldId });
    } else {
      onChange({ ...(config as TableViewConfig | RoadmapViewConfig), groupByFieldId: fieldId || null });
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button variant="outline" size="sm" className="gap-1.5" />}>
        <Settings2 className="size-3.5" />
        View
      </DialogTrigger>
      <DialogContent className="sm:max-w-[380px]">
        <DialogHeader>
          <DialogTitle>View settings</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div>
            <Label className="mb-1.5 text-[11px] text-muted-foreground">Group by</Label>
            <Select value={groupByFieldId ?? ""} onValueChange={(v) => setGroupBy(v ?? "")}>
              <SelectTrigger className="w-full text-xs">
                <SelectValue placeholder="None" />
              </SelectTrigger>
              <SelectContent>
                {viewType !== "board" ? <SelectItem value="">None</SelectItem> : null}
                {groupableFields.map((f) => (
                  <SelectItem key={f.id} value={f.id}>
                    {f.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {viewType === "table" ? (
            <SortSection config={config as TableViewConfig} registry={registry} onChange={onChange} />
          ) : null}

          {viewType === "roadmap" ? (
            <RoadmapDateFields config={config as RoadmapViewConfig} registry={registry} onChange={onChange} />
          ) : null}

          {"visibleFieldIds" in config ? (
            <div>
              <Label className="mb-1.5 text-[11px] text-muted-foreground">
                {viewType === "board" ? "Fields shown on cards" : "Visible columns"}
              </Label>
              <div className="flex max-h-[200px] flex-col gap-1.5 overflow-y-auto">
                {registry.map((field) => (
                  <label key={field.id} className="flex items-center gap-2 text-[13px]">
                    <Checkbox
                      checked={visibleFieldIds.includes(field.id)}
                      onCheckedChange={(checked) => toggleVisible(field.id, checked === true)}
                    />
                    {field.name}
                  </label>
                ))}
              </div>
            </div>
          ) : null}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function SortSection({
  config,
  registry,
  onChange,
}: {
  config: TableViewConfig;
  registry: FieldDef[];
  onChange: (config: ViewConfig) => void;
}) {
  const current = config.sort[0];
  return (
    <div>
      <Label className="mb-1.5 text-[11px] text-muted-foreground">Sort by</Label>
      <div className="flex gap-1.5">
        <Select
          value={current?.fieldId ?? ""}
          onValueChange={(v) =>
            onChange({ ...config, sort: v ? [{ fieldId: v, direction: current?.direction ?? "asc" }] : [] })
          }
        >
          <SelectTrigger className="flex-1 text-xs">
            <SelectValue placeholder="None" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="">None</SelectItem>
            {registry.map((f) => (
              <SelectItem key={f.id} value={f.id}>
                {f.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {current ? (
          <Select
            value={current.direction}
            onValueChange={(v) =>
              onChange({ ...config, sort: [{ fieldId: current.fieldId, direction: (v ?? "asc") as "asc" | "desc" }] })
            }
          >
            <SelectTrigger className="w-[90px] text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="asc">Asc</SelectItem>
              <SelectItem value="desc">Desc</SelectItem>
            </SelectContent>
          </Select>
        ) : null}
      </div>
    </div>
  );
}

function RoadmapDateFields({
  config,
  registry,
  onChange,
}: {
  config: RoadmapViewConfig;
  registry: FieldDef[];
  onChange: (config: ViewConfig) => void;
}) {
  const dateFields = registry.filter((f) => f.type === "date" || f.type === "iteration");
  return (
    <>
      <div>
        <Label className="mb-1.5 text-[11px] text-muted-foreground">Start field</Label>
        <Select value={config.startFieldId ?? ""} onValueChange={(v) => onChange({ ...config, startFieldId: v || null })}>
          <SelectTrigger className="w-full text-xs">
            <SelectValue placeholder="None" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="">None</SelectItem>
            {dateFields.map((f) => (
              <SelectItem key={f.id} value={f.id}>
                {f.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div>
        <Label className="mb-1.5 text-[11px] text-muted-foreground">End field</Label>
        <Select value={config.endFieldId ?? ""} onValueChange={(v) => onChange({ ...config, endFieldId: v || null })}>
          <SelectTrigger className="w-full text-xs">
            <SelectValue placeholder="None" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="">None</SelectItem>
            {dateFields.map((f) => (
              <SelectItem key={f.id} value={f.id}>
                {f.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div>
        <Label className="mb-1.5 text-[11px] text-muted-foreground">Zoom</Label>
        <Select
          value={config.zoom}
          onValueChange={(v) => onChange({ ...config, zoom: (v ?? "month") as RoadmapViewConfig["zoom"] })}
        >
          <SelectTrigger className="w-full text-xs">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="week">Week</SelectItem>
            <SelectItem value="month">Month</SelectItem>
            <SelectItem value="quarter">Quarter</SelectItem>
          </SelectContent>
        </Select>
      </div>
    </>
  );
}
