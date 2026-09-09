/// Port of `lib/claude-prompt.ts`. Builds a ready-to-paste prompt
/// summarizing a task, for kicking off work on it in Claude Code /
/// claude.ai — just the task text itself (title, description, subtasks),
/// not surrounding tracker metadata (priority, status, branch, dates, repo,
/// milestone, tags) — none of that helps Claude decide what to do.
public struct TaskPromptInput {
    public struct Subtask {
        public let title: String
        public let done: Bool

        public init(title: String, done: Bool) {
            self.title = title
            self.done = done
        }
    }

    public let title: String
    public let description: String?
    public let subtasks: [Subtask]

    public init(title: String, description: String?, subtasks: [Subtask]) {
        self.title = title
        self.description = description
        self.subtasks = subtasks
    }
}

public enum ClaudePromptBuilder {
    public static func buildTaskPrompt(_ task: TaskPromptInput) -> String {
        var lines = [task.title.isEmpty ? "(untitled task)" : task.title]

        if let description = task.description, !description.isEmpty {
            lines.append("")
            lines.append(description)
        }

        if !task.subtasks.isEmpty {
            lines.append("")
            lines.append("Subtasks:")
            for subtask in task.subtasks {
                lines.append("- [\(subtask.done ? "x" : " ")] \(subtask.title)")
            }
        }

        lines.append("")
        lines.append("Please implement this.")

        return lines.joined(separator: "\n")
    }
}
