// Fixed palette for custom-field select options (and a couple of built-in
// field values) — same idea as the CSS-token-backed PRIORITY_DOT_CLASS in
// lib/priority.ts, but plain Tailwind color utilities since these are
// user-picked per option rather than a fixed design-system accent.
export const fieldColorValues = ["gray", "blue", "green", "purple", "red", "yellow", "pink", "orange"] as const;
export type FieldColor = (typeof fieldColorValues)[number];

export const FIELD_COLOR_CHIP_CLASS: Record<FieldColor, string> = {
  gray: "bg-muted text-muted-foreground",
  blue: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  green: "bg-green-500/15 text-green-600 dark:text-green-400",
  purple: "bg-purple-500/15 text-purple-600 dark:text-purple-400",
  red: "bg-red-500/15 text-red-600 dark:text-red-400",
  yellow: "bg-yellow-500/15 text-yellow-700 dark:text-yellow-400",
  pink: "bg-pink-500/15 text-pink-600 dark:text-pink-400",
  orange: "bg-orange-500/15 text-orange-600 dark:text-orange-400",
};

export const FIELD_COLOR_DOT_CLASS: Record<FieldColor, string> = {
  gray: "bg-muted-foreground",
  blue: "bg-blue-500",
  green: "bg-green-500",
  purple: "bg-purple-500",
  red: "bg-red-500",
  yellow: "bg-yellow-500",
  pink: "bg-pink-500",
  orange: "bg-orange-500",
};

export function fieldColorChipClass(color: string | undefined): string {
  return FIELD_COLOR_CHIP_CLASS[color as FieldColor] ?? FIELD_COLOR_CHIP_CLASS.gray;
}

export function fieldColorDotClass(color: string | undefined): string {
  return FIELD_COLOR_DOT_CLASS[color as FieldColor] ?? FIELD_COLOR_DOT_CLASS.gray;
}
