"use client";

import { createContext, useContext } from "react";

import type { IssueRecord } from "@/lib/issue-types";
import type { FieldDef } from "@/lib/fields/registry";

export type DrawerTask = IssueRecord;

export type DrawerContext = {
  spaceSlug: string;
  milestones: { id: string; title: string }[];
  repos: { id: string; name: string }[];
  // Full field registry (built-ins + custom fields) for this task's space —
  // optional since the milestone detail page's legacy row list doesn't wire
  // it through; the drawer just skips the custom-fields section when absent.
  registry?: FieldDef[];
};

export type AppShellContextValue = {
  openTask: (task: DrawerTask, ctx: DrawerContext) => void;
  openAiModal: () => void;
  openCommandPalette: () => void;
};

export const AppShellContext = createContext<AppShellContextValue | null>(null);

export function useAppShell(): AppShellContextValue {
  const ctx = useContext(AppShellContext);
  if (!ctx) throw new Error("useAppShell must be used within <AppShell>");
  return ctx;
}
