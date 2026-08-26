import type { IssuePriority } from "@/lib/db/schema";

// Tailwind color-utility class names, backed by the --priority-* tokens in
// globals.css (bg-priority-high etc, via @theme inline).
export const PRIORITY_DOT_CLASS: Record<IssuePriority, string> = {
  high: "bg-priority-high",
  medium: "bg-priority-medium",
  low: "bg-priority-low",
};

export const PRIORITY_TEXT_CLASS: Record<IssuePriority, string> = {
  high: "text-priority-high",
  medium: "text-priority-medium",
  low: "text-priority-low",
};

export const PRIORITY_LABEL: Record<IssuePriority, string> = {
  high: "High",
  medium: "Medium",
  low: "Low",
};
