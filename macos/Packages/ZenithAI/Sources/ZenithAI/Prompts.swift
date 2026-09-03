import Foundation
import ZenithData

/// Port of `lib/ai/prompts.ts`.
public enum Prompts {
    // MARK: - JSON schemas sent to the CLI's `--json-schema`

    /// Shared per-task shape: used both as the top-level schema for the
    /// single-task flow and as the `items` schema of the array for the
    /// bulk-list flow. `fieldValues`/`newFields` are fixed-shape (all-
    /// string) regardless of which custom fields actually exist in the
    /// space — a JSON schema can't vary its shape per request, so the
    /// per-space field *list* only ever appears in the prompt text
    /// (`buildCustomFieldsBlock` below), and `FieldResolver` coerces these
    /// generic string values to each field's real type afterward.
    /// A computed property (not a stored `static let`) so Swift 6 strict
    /// concurrency doesn't need to reason about shared mutable global
    /// state for a `[String: Any]` — each access just builds a fresh,
    /// unshared dictionary.
    static var parseTaskJSONSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "description": ["type": "string"],
                "priority": ["type": "string", "enum": ["low", "medium", "high"]],
                "tags": ["type": "array", "items": ["type": "string"]],
                "branch": ["type": "string"],
                "estimate": ["type": "string"],
                "dueDate": ["type": "string"],
                "repos": ["type": "array", "items": ["type": "string"]],
                "milestone": ["type": "string"],
                "fieldValues": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": ["fieldKey": ["type": "string"], "value": ["type": "string"]],
                        "required": ["fieldKey", "value"],
                    ],
                ],
                "newFields": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "key": ["type": "string"],
                            "name": ["type": "string"],
                            "type": ["type": "string", "enum": ["text", "number", "date", "single_select", "multi_select", "iteration"]],
                            "options": ["type": "array", "items": ["type": "string"]],
                        ],
                        "required": ["key", "name", "type"],
                    ],
                ],
            ],
            "required": ["title", "priority", "tags"],
        ]
    }

    /// The Messages API requires a structured-output schema to be
    /// `type: "object"` at the root — a bare array gets rejected — so
    /// array-shaped results are wrapped in an object and unwrapped again
    /// via `unwrapKey` after the call.
    static var parseTasksJSONSchema: [String: Any] {
        [
            "type": "object",
            "properties": ["tasks": ["type": "array", "items": parseTaskJSONSchema]],
            "required": ["tasks"],
        ]
    }

    static var generatedSubtasksJSONSchema: [String: Any] {
        [
            "type": "object",
            "properties": ["subtasks": ["type": "array", "items": ["type": "string"]]],
            "required": ["subtasks"],
        ]
    }

    // MARK: - Prompt context blocks

    /// A space's linked repos, as fed into a parse prompt — cached
    /// summaries only, never live repo content.
    public struct RepoContext: Sendable { public let name: String; public let context: String? }
    /// A space's milestones, as fed into a parse prompt.
    public struct MilestoneContext: Sendable { public let title: String; public let description: String? }
    /// A space's custom field definitions, as fed into a parse prompt.
    /// `options` is the current option *labels* only.
    public struct CustomFieldContext: Sendable { public let key: String; public let name: String; public let type: String; public let options: [String] }

    private static func buildReposBlock(_ repos: [RepoContext]) -> [String] {
        guard !repos.isEmpty else { return [] }
        return [
            "",
            "This space has these linked repos. Add each one clearly named (or obviously",
            "synonymous) to `repos` by its exact name below — a task can span more than one,",
            "so include all that clearly apply. Use their context to inform tags/branch/priority.",
            "If no repo is clearly named, leave `repos` empty; don't guess:",
        ] + repos.map { "- \($0.name)\($0.context.map { ": \($0)" } ?? "")" }
    }

    private static func buildMilestonesBlock(_ milestones: [MilestoneContext]) -> [String] {
        guard !milestones.isEmpty else { return [] }
        return [
            "",
            "This space has these milestones (goals). Unlike repos, this doesn't require an",
            "explicit name mention — if the task's content clearly fits one milestone's stated",
            "scope (by name, or by what it covers), set `milestone` to its exact title below.",
            "If nothing clearly fits, omit `milestone` entirely — don't force a task into a",
            "milestone it doesn't clearly belong to:",
        ] + milestones.map { "- \($0.title)\($0.description.map { ": \($0)" } ?? "")" }
    }

    private static func buildCustomFieldsBlock(_ fields: [CustomFieldContext]) -> [String] {
        var lines = [
            "",
            "This space has custom fields (beyond the built-in ones above). If the message",
            "clearly gives a value for one, add it to `fieldValues` as `{ fieldKey, value }`",
            "(value always as plain text — e.g. \"L\", \"3\", \"2026-09-01\", or \"alice, bob\" for a",
            "multi-value field — never invent a value that isn't stated or clearly implied).",
        ]
        if !fields.isEmpty {
            lines.append("Existing fields (fieldKey — type — options if any):")
            lines += fields.map { "- \($0.key) — \($0.type)\($0.options.isEmpty ? "" : " — options: \($0.options.joined(separator: ", "))")" }
        } else {
            lines.append("This space has no custom fields yet.")
        }
        lines += [
            "",
            "If the message clearly implies a field that doesn't exist yet (e.g. \"Size: L\" with",
            "no Size field above), you may propose up to 3 new ones via `newFields` — each",
            "`{ key, name, type, options? }` (type one of text/number/date/single_select/",
            "multi_select/iteration; include a short `options` list of labels only for",
            "single_select/multi_select) — and also add its value to `fieldValues` using that",
            "same `key`. Don't propose a field for something the built-in fields already cover",
            "(priority, tags, due date, branch, estimate, repos, milestone).",
        ]
        return lines
    }

    /// Field-extraction rules shared by the single-task and bulk-list prompts.
    private static let taskFieldRules = [
        "- title: a short, actionable summary (rewrite it if the source is rambly).",
        "- description: a short 1-4 sentence elaboration ONLY if the source has real detail",
        "  beyond the title worth preserving (context, repro steps, acceptance criteria);",
        "  omit entirely if the title already says it all — don't pad for the sake of it.",
        "- priority: \"high\" if urgent/ASAP/blocker language is present, \"low\" if",
        "  explicitly deprioritized (\"no rush\", \"whenever\"), otherwise \"medium\".",
        "- tags: short lowercase keywords (e.g. bug, frontend, backend, security, infra,",
        "  docs, payments, design) — infer from context, don't invent unrelated ones.",
        "- branch: a git branch name only if one is mentioned or clearly implied",
        "  (e.g. \"fix/checkout-500\"); omit otherwise.",
        "- estimate: a short effort estimate like \"2h\" or \"1d\" only if the text gives one;",
        "  omit otherwise, don't guess.",
        "- dueDate: resolve relative dates (\"by Friday\", \"end of week\") to an absolute",
        "  ISO date (YYYY-MM-DD) using today's date above; omit if no due date is implied.",
    ]

    private static func todayISODate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    public static func parseTaskFromText(
        text: String, spaceContext: String?, spaceImages: [AttachedImage] = [], attachedImage: AttachedImage? = nil,
        repos: [RepoContext] = [], milestones: [MilestoneContext] = [], customFields: [CustomFieldContext] = []
    ) async throws -> ParsedTask {
        var instructions = [
            "You extract a single structured task from a raw message someone pasted from a",
            "chat/ticket/manager (Slack, email, standup notes, etc), and/or a screenshot they",
            "attached (e.g. a bug, an error dialog, a design mockup). Today's date is",
            "\(todayISODate()).",
            "",
        ]
        instructions += taskFieldRules
        instructions += buildReposBlock(repos)
        instructions += buildMilestonesBlock(milestones)
        instructions += buildCustomFieldsBlock(customFields)

        if let spaceContext, !spaceContext.isEmpty {
            instructions += [
                "",
                "Project context for this space (use it to pick better-fitting tags, branch names,",
                "and priority — e.g. known services, tech stack, conventions):",
                "\"\"\"\n\(spaceContext)\n\"\"\"",
            ]
        }

        instructions += ["", "Message:", "\"\"\"\n\(text.isEmpty ? "(no text — see attached image)" : text)\n\"\"\""]

        let hasImages = !spaceImages.isEmpty || attachedImage != nil
        var blocks: [ClaudeCLIClient.ContentBlock] = [.text(instructions.joined(separator: "\n"))]
        if hasImages {
            for image in spaceImages {
                blocks.append(try ClaudeCLIClient.imageBlock(mimeType: image.mimeType, data: image.data))
            }
            if let attachedImage {
                blocks.append(.text("Screenshot attached with this task:"))
                blocks.append(try ClaudeCLIClient.imageBlock(mimeType: attachedImage.mimeType, data: attachedImage.data))
            }
        }

        return try await ClaudeCLIClient.shared.runJSON(
            blocks: blocks, jsonSchema: parseTaskJSONSchema, timeout: hasImages ? 120 : 90
        ) { raw in
            let data = try JSONSerialization.data(withJSONObject: raw)
            return try JSONDecoder().decode(ParsedTask.self, from: data).validate()
        }
    }

    /// Bulk "paste a list" flow: splits a pasted list into many structured tasks.
    public static func parseTasksFromText(
        text: String, spaceContext: String?, repos: [RepoContext] = [], milestones: [MilestoneContext] = [],
        customFields: [CustomFieldContext] = []
    ) async throws -> [ParsedTask] {
        var instructions = [
            "You extract a list of structured tasks from a raw list someone pasted from a",
            "chat/ticket/manager/notes app (Slack, email, standup notes, a backlog dump, etc).",
            "Split it into one task per distinct bullet, numbered item, or line — ignore section",
            "headers and blank lines, and don't merge unrelated items together. Different items",
            "may belong to different repos/milestones (see below) — decide those independently",
            "per item. Today's date is",
            "\(todayISODate()).",
            "",
            "For each task, apply these rules:",
        ]
        instructions += taskFieldRules
        instructions += buildReposBlock(repos)
        instructions += buildMilestonesBlock(milestones)
        instructions += buildCustomFieldsBlock(customFields)

        if let spaceContext, !spaceContext.isEmpty {
            instructions += [
                "",
                "Project context for this space (use it to pick better-fitting tags, branch names,",
                "and priority — e.g. known services, tech stack, conventions):",
                "\"\"\"\n\(spaceContext)\n\"\"\"",
            ]
        }
        instructions += ["", "List:", "\"\"\"\n\(text)\n\"\"\""]

        return try await ClaudeCLIClient.shared.runJSON(
            prompt: instructions.joined(separator: "\n"), jsonSchema: parseTasksJSONSchema, unwrapKey: "tasks", timeout: 180
        ) { raw in
            guard let array = raw as? [Any] else { throw AISchemaError.invalid("expected an array of tasks") }
            let data = try JSONSerialization.data(withJSONObject: array)
            let tasks = try JSONDecoder().decode([ParsedTask].self, from: data)
            return try ParsedTasksValidator.validate(tasks)
        }
    }

    /// One-off "Sync" summary: turns a curated repo snapshot into a short
    /// paragraph cached on the repo and reused.
    public static func summarizeRepoContext(_ snapshot: GitHubClient.RepoSnapshot) async throws -> String {
        var lines = [
            "Summarize the GitHub repo \"\(snapshot.fullName)\" in about 150-300 words of plain",
            "prose, for use as background context fed to another AI whenever someone pastes a",
            "task for this repo — not for a human reader. Cover: the stack/framework, key",
            "services or modules, and any conventions implied by the file layout (branch",
            "naming, folder structure, etc). Be concrete and specific, skip filler like",
            "\"this repo contains...\". Output only the summary, no headings or markdown.",
            "",
        ]
        if let description = snapshot.description { lines.append("Description: \(description)") }
        if let language = snapshot.language { lines.append("Primary language: \(language)") }
        if !snapshot.topics.isEmpty { lines.append("Topics: \(snapshot.topics.joined(separator: ", "))") }
        if !snapshot.tree.isEmpty { lines.append("Top-level files/dirs: \(snapshot.tree.joined(separator: ", "))") }
        lines.append("")
        lines.append(snapshot.readme.map { "README:\n\"\"\"\n\($0)\n\"\"\"" } ?? "(no README found)")
        lines.append("")
        if let packageJson = snapshot.packageJson { lines.append("package.json:\n\"\"\"\n\(packageJson)\n\"\"\"") }

        return try await ClaudeCLIClient.shared.runText(
            lines.filter { !$0.isEmpty }.joined(separator: "\n"), timeout: 90
        )
    }

    /// "Generate ✦" in the task detail drawer: breaks a task down into a
    /// handful of concrete subtask checklist items.
    public static func generateSubtasks(title: String, description: String?) async throws -> [String] {
        var lines = [
            "Break the following task down into 3-8 concrete, actionable subtasks — short",
            "checklist items a developer would tick off one by one. Order them in the sequence",
            "they'd actually be done in. Don't restate the task title as a single subtask, and",
            "don't invent scope that isn't implied by the task.",
            "",
            "Title: \(title)",
        ]
        if let description, !description.isEmpty {
            lines.append("Description:\n\"\"\"\n\(description)\n\"\"\"")
        }

        return try await ClaudeCLIClient.shared.runJSON(
            prompt: lines.joined(separator: "\n"), jsonSchema: generatedSubtasksJSONSchema, unwrapKey: "subtasks", timeout: 60
        ) { raw in
            guard let array = raw as? [String] else { throw AISchemaError.invalid("expected an array of strings") }
            return try GeneratedSubtasksValidator.validate(array)
        }
    }
}
