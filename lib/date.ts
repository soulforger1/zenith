import { addDays, differenceInCalendarDays, format, isBefore, startOfDay } from "date-fns";

import type { IssueStatus } from "@/lib/db/schema";

/** A task is overdue if it has a due date in the past and isn't done yet —
 * "done" is deliberately excluded so completed tasks never show as overdue,
 * matching how the app already treats `status` as the single source of
 * truth for closed-ness (no separate isClosed toggle in the UI). */
export function isOverdue(dueDate: string | null, status: IssueStatus): boolean {
  if (!dueDate || status === "done") return false;
  return isBefore(new Date(dueDate), startOfDay(new Date()));
}

/** Parses a `YYYY-MM-DD` string as a local-timezone date (avoids the
 * off-by-one-day shift `new Date("2026-08-23")` gets in non-UTC timezones,
 * since that form is parsed as UTC midnight). */
export function parseISODate(value: string): Date {
  const [y, m, d] = value.split("-").map(Number);
  return new Date(y ?? 1970, (m ?? 1) - 1, d ?? 1);
}

/** Day offset from `from` to `to` (both `YYYY-MM-DD`) — used to position
 * Roadmap bars in a day-pixel-width grid. */
export function daysBetweenISO(from: string, to: string): number {
  return differenceInCalendarDays(parseISODate(to), parseISODate(from));
}

export function addDaysISO(value: string, days: number): string {
  return format(addDays(parseISODate(value), days), "yyyy-MM-dd");
}

export function todayISO(): string {
  return format(new Date(), "yyyy-MM-dd");
}
