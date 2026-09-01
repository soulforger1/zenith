export type TaskPromptInput = {
  title: string;
  description: string;
  subtasks: { title: string; done: boolean }[];
};

/** Builds a ready-to-paste prompt summarizing a task, for kicking off work on
 * it in Claude Code / claude.ai — just the task text itself (title,
 * description, subtasks), not the surrounding tracker metadata (priority,
 * status, branch, dates, repo, milestone, tags) — none of that helps Claude
 * decide what to do. Assembled from whatever the caller currently has in
 * local edit state, not the last-saved task, so it always matches what's on
 * screen even before an in-progress edit has been blurred/saved. */
export function buildTaskPrompt(task: TaskPromptInput): string {
  const lines = [task.title || "(untitled task)"];

  if (task.description) lines.push("", task.description);

  if (task.subtasks.length > 0) {
    lines.push("", "Subtasks:");
    for (const st of task.subtasks) lines.push(`- [${st.done ? "x" : " "}] ${st.title}`);
  }

  lines.push("", "Please implement this.");

  return lines.join("\n");
}
