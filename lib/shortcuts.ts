// Shared list of global keyboard shortcuts — the single source of truth for
// both the Settings page and the "?"-triggered shortcuts overlay
// (components/layout/shortcuts-dialog.tsx). Keep in sync with the actual
// keydown handling in components/layout/app-shell.tsx.
export const SHORTCUTS = [
  { keys: "C", desc: "Paste a task from your manager" },
  { keys: "⌥⌥", desc: "Paste a task, from anywhere (desktop app)" },
  { keys: "⌘K", desc: "Open search & commands" },
  { keys: "1", desc: "Go to Milestones" },
  { keys: "2", desc: "Go to Settings" },
  { keys: "?", desc: "Show this list" },
  { keys: "Esc", desc: "Close any open panel" },
];
