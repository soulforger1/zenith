import SwiftUI
import AppKit
import ZenithData

/// Port of `task-detail-drawer.tsx`, presented as a native `.inspector`
/// (a trailing panel, the platform's own take on the web build's slide-in
/// `Sheet`) rather than a sheet — the inspector stays open and swaps its
/// content as the user clicks between a task and its parent/children, the
/// same "drawer that follows you" feel the web version had via `openTask`.
struct TaskDetailView: View {
    let model: SpaceDetailModel
    let issueId: UUID

    @Environment(AppShellModel.self) private var shell
    @Environment(ToastCenter.self) private var toasts

    @State private var record: IssueRecord?
    @State private var title = ""
    @State private var description = ""
    @State private var priority: IssuePriority = .medium
    @State private var status: IssueStatus = .backlog
    @State private var branch = ""
    @State private var estimate = ""
    @State private var dueDate = ""
    @State private var tagText = ""
    @State private var milestoneId: UUID?
    @State private var repoIds: Set<UUID> = []
    @State private var customValues: [String: AnyCodableValue] = [:]
    @State private var parentId: UUID?
    @State private var parentRecord: IssueRecord?
    @State private var children: [IssueRecord]?
    @State private var newSubtaskTitle = ""
    @State private var isGeneratingSubtasks = false
    @State private var isLinking = false
    @State private var linkQuery = ""
    @State private var linkResults: [(id: UUID, title: String)] = []
    @State private var isDeleting = false

    var body: some View {
        ScrollView {
            if let record {
                content(for: record)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task(id: issueId) { await load() }
        .navigationTitle("Task")
    }

    @ViewBuilder
    private func content(for record: IssueRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let parentId {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.up.left").font(.caption2)
                    Button {
                        shell.openTask(spaceId: model.space.id, issueId: parentId)
                    } label: {
                        Text(parentRecord?.title ?? "Parent task").lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Button {
                        Task { await unlinkFromParent() }
                    } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Unlink from parent task")
                }
                .font(.caption)
            }

            TextField("Title", text: $title, axis: .vertical)
                .font(.title3.weight(.semibold))
                .textFieldStyle(.plain)
                .onSubmit { Task { await saveTitle() } }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Description")
                TextField("Add more context…", text: $description, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.callout)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Priority")
                    Picker("", selection: $priority) {
                        ForEach(IssuePriority.allCases, id: \.self) { Text(PriorityLabel.label(for: $0)).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: priority) { _, newValue in Task { await save(IssueFieldPatch(priority: newValue)) } }
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Status")
                    Picker("", selection: $status) {
                        ForEach(IssueStatus.allCases, id: \.self) { Text(statusLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: status) { _, newValue in Task { await save(IssueFieldPatch(status: newValue)) } }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Branch / PR")
                TextField("feature/my-branch", text: $branch)
                    .font(.callout.monospaced())
                    .onSubmit { Task { await save(IssueFieldPatch(branch: .some(branch.isEmpty ? nil : branch))) } }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Estimate")
                    TextField("2h", text: $estimate)
                        .onSubmit { Task { await save(IssueFieldPatch(estimate: .some(estimate.isEmpty ? nil : estimate))) } }
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Due")
                    OptionalDateField(value: dueDate) { newValue in
                        dueDate = newValue ?? ""
                        Task { await save(IssueFieldPatch(dueDate: .some(newValue))) }
                    }
                }
            }

            if !model.milestones.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Milestone")
                    Picker("", selection: $milestoneId) {
                        Text("None").tag(UUID?.none)
                        ForEach(model.milestones) { milestone in
                            Text(milestone.title).tag(Optional(milestone.id))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: milestoneId) { _, newValue in
                        Task { await save(IssueFieldPatch(milestoneId: .some(newValue))) }
                    }
                }
            }

            if !model.repos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Repos")
                    ForEach(model.repos) { repo in
                        Toggle(repo.name, isOn: Binding(
                            get: { repoIds.contains(repo.id) },
                            set: { isOn in
                                if isOn { repoIds.insert(repo.id) } else { repoIds.remove(repo.id) }
                                Task { await save(IssueFieldPatch(repoIds: Array(repoIds))) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Tags (comma separated)")
                TextField("frontend, bug", text: $tagText)
                    .onSubmit {
                        Task {
                            await save(IssueFieldPatch(tags: tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
                        }
                    }
            }

            subtasksSection

            if !model.customFields.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Custom fields")
                    ForEach(model.customFields.sorted { $0.position < $1.position }) { field in
                        customFieldEditor(field: field)
                    }
                }
            }

            Button(role: .destructive) {
                Task { await delete() }
            } label: {
                if isDeleting { ProgressView().controlSize(.small).frame(maxWidth: .infinity) } else { Text("Delete task").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding(.top, 8)
        }
        .padding(20)
    }

    private var header: some View {
        HStack {
            Text("TASK").font(.caption2.monospaced()).foregroundStyle(.secondary)
            Spacer()
            Button {
                copyPrompt()
            } label: {
                Label("Copy prompt", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Copy an AI prompt for this task to the clipboard")
            Button {
                shell.closeTask()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close")
        }
    }

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel("Subtasks\(subtaskCountSuffix)")
                Spacer()
                Button {
                    Task { await generateSubtasks() }
                } label: {
                    if isGeneratingSubtasks { ProgressView().controlSize(.small) } else { Text("Generate ✦") }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(isGeneratingSubtasks)
            }

            if let children {
                if children.isEmpty {
                    Text("No subtasks.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(children) { child in
                        HStack(spacing: 8) {
                            let isDone = child.status == .done
                            Button {
                                Task { await toggleChildStatus(child) }
                            } label: {
                                Image(systemName: isDone ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(isDone ? "Mark as not done" : "Mark as done")
                            Button {
                                shell.openTask(spaceId: model.space.id, issueId: child.id)
                            } label: {
                                Text(child.title)
                                    .strikethrough(isDone)
                                    .foregroundStyle(isDone ? Color.secondary : Color.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .help("Open subtask")
                            Button {
                                Task { await unlinkChild(child) }
                            } label: {
                                Image(systemName: "xmark").font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Unlink subtask")
                        }
                        .font(.callout)
                    }
                }
            } else {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }

            TextField("+ Add subtask…", text: $newSubtaskTitle)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { Task { await addSubtask() } }

            if isLinking {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Search tasks…", text: $linkQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .onChange(of: linkQuery) { _, newValue in Task { await searchLink(newValue) } }
                    ForEach(linkResults, id: \.id) { result in
                        Button(result.title) { Task { await linkExisting(result) } }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            } else {
                Button("Link existing…") { isLinking = true }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtaskCountSuffix: String {
        guard let children, !children.isEmpty else { return "" }
        return " (\(children.filter { $0.status == .done }.count)/\(children.count))"
    }

    @ViewBuilder
    private func customFieldEditor(field: CustomField) -> some View {
        let key = field.id.uuidString
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(field.name)
            switch field.type {
            case .text, .number:
                TextField(field.name, text: stringBinding(key: key, isNumber: field.type == .number))
                    .onSubmit { Task { await save(IssueFieldPatch(customFieldValues: [key: customValues[key] ?? .null])) } }
            case .date:
                OptionalDateField(value: dateString(key: key)) { newValue in
                    if let newValue { customValues[key] = .string(newValue) }
                    else { customValues.removeValue(forKey: key) }
                    Task { await save(IssueFieldPatch(customFieldValues: [key: customValues[key] ?? .null])) }
                }
            case .singleSelect:
                Picker("", selection: selectBinding(key: key)) {
                    Text("None").tag("")
                    ForEach(field.options.fieldOptions) { option in Text(option.name).tag(option.id) }
                }
                .labelsHidden()
                .onChange(of: customValues[key]) { _, _ in Task { await save(IssueFieldPatch(customFieldValues: [key: customValues[key] ?? .null])) } }
            case .multiSelect:
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(field.options.fieldOptions) { option in
                        let isSelected = multiSelectIds(key: key).contains(option.id)
                        Button {
                            toggleMultiSelect(key: key, optionId: option.id)
                            Task { await save(IssueFieldPatch(customFieldValues: [key: customValues[key] ?? .null])) }
                        } label: {
                            Text(option.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isSelected ? Theme.fieldColor(FieldColors.color(named: option.color)) : Color(nsColor: .quaternaryLabelColor), in: Capsule())
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .iteration:
                Picker("", selection: selectBinding(key: key)) {
                    Text("None").tag("")
                    ForEach(field.options.iterationOptions) { option in Text(option.title).tag(option.id) }
                }
                .labelsHidden()
                .onChange(of: customValues[key]) { _, _ in Task { await save(IssueFieldPatch(customFieldValues: [key: customValues[key] ?? .null])) } }
            }
        }
    }

    private func dateString(key: String) -> String {
        if case .string(let value) = customValues[key] { return value }
        return ""
    }

    private func stringBinding(key: String, isNumber: Bool) -> Binding<String> {
        Binding(
            get: {
                switch customValues[key] {
                case .string(let s): return s
                case .number(let n): return String(n)
                default: return ""
                }
            },
            set: { newValue in
                if newValue.isEmpty { customValues.removeValue(forKey: key) }
                else if isNumber { if let number = Double(newValue) { customValues[key] = .number(number) } }
                else { customValues[key] = .string(newValue) }
            }
        )
    }

    private func selectBinding(key: String) -> Binding<String> {
        Binding(
            get: { if case .string(let s) = customValues[key] { return s }; return "" },
            set: { newValue in customValues[key] = newValue.isEmpty ? nil : .string(newValue) }
        )
    }

    private func multiSelectIds(key: String) -> Set<String> {
        if case .array(let items) = customValues[key] {
            return Set(items.compactMap { if case .string(let s) = $0 { return s }; return nil })
        }
        return []
    }

    private func toggleMultiSelect(key: String, optionId: String) {
        var ids = multiSelectIds(key: key)
        if ids.contains(optionId) { ids.remove(optionId) } else { ids.insert(optionId) }
        customValues[key] = ids.isEmpty ? nil : .array(ids.map { .string($0) })
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func statusLabel(_ status: IssueStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }

    // MARK: - Data

    private func load() async {
        record = nil
        children = nil
        parentRecord = nil
        isLinking = false
        linkQuery = ""
        linkResults = []
        guard let loaded = await model.issueRecord(issueId) else { return }
        apply(loaded)
        async let kids = model.childIssues(issueId)
        if let parentId = loaded.parentId {
            async let parent = model.issueRecord(parentId)
            let (kidsValue, parentValue) = await (kids, parent)
            children = kidsValue
            parentRecord = parentValue
        } else {
            children = await kids
        }
    }

    private func apply(_ loaded: IssueRecord) {
        record = loaded
        title = loaded.title
        description = loaded.description ?? ""
        priority = loaded.priority
        status = loaded.status
        branch = loaded.branch ?? ""
        estimate = loaded.estimate ?? ""
        dueDate = loaded.dueDate ?? ""
        tagText = loaded.tags.joined(separator: ", ")
        milestoneId = loaded.milestoneId
        repoIds = Set(loaded.repoIds)
        customValues = loaded.customFieldValues
        parentId = loaded.parentId
    }

    private func save(_ patch: IssueFieldPatch) async {
        await model.applyPatch(issueId, patch: patch)
    }

    private func saveTitle() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != record?.title else { return }
        await save(IssueFieldPatch(title: trimmed))
    }

    private func toggleChildStatus(_ child: IssueRecord) async {
        let next: IssueStatus = child.status == .done ? .todo : .done
        children = children?.map { $0.id == child.id ? withStatus(next, $0) : $0 }
        await model.applyPatch(child.id, patch: IssueFieldPatch(status: next))
    }

    private func withStatus(_ status: IssueStatus, _ record: IssueRecord) -> IssueRecord {
        var updated = record
        updated.status = status
        return updated
    }

    private func addSubtask() async {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newSubtaskTitle = ""
        guard !trimmed.isEmpty else { return }
        if let created = await model.createSubtask(parentId: issueId, title: trimmed) {
            children = (children ?? []) + [created]
        }
    }

    private func unlinkChild(_ child: IssueRecord) async {
        children = children?.filter { $0.id != child.id }
        _ = await model.setParent(child.id, parentId: nil)
    }

    private func unlinkFromParent() async {
        let oldParentId = parentId
        parentId = nil
        parentRecord = nil
        _ = await model.setParent(issueId, parentId: nil)
        _ = oldParentId
    }

    private func searchLink(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            linkResults = []
            return
        }
        linkResults = await model.searchIssuesForSubtask(taskId: issueId, query: query)
    }

    private func linkExisting(_ result: (id: UUID, title: String)) async {
        isLinking = false
        linkQuery = ""
        linkResults = []
        if let error = await model.setParent(result.id, parentId: issueId) {
            _ = error
            return
        }
        if let linked = await model.issueRecord(result.id) {
            children = (children ?? []) + [linked]
        }
    }

    private func generateSubtasks() async {
        isGeneratingSubtasks = true
        do {
            let titles = try await model.generateSubtasks(
                title: title, description: description.isEmpty ? nil : description)
            let created = await model.createSubtasksFromTitles(parentId: issueId, titles: titles)
            children = (children ?? []) + created
        } catch {
            toasts.error(error.diagnosticDescription)
        }
        isGeneratingSubtasks = false
    }

    private func delete() async {
        isDeleting = true
        await model.deleteIssue(issueId)
        shell.closeTask()
    }

    private func copyPrompt() {
        let subtasks = (children ?? []).map {
            TaskPromptInput.Subtask(title: $0.title, done: $0.status == .done)
        }
        let prompt = ClaudePromptBuilder.buildTaskPrompt(
            TaskPromptInput(title: title, description: description.isEmpty ? nil : description, subtasks: subtasks))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }
}

/// A `DatePicker` for an optional `YYYY-MM-DD` value — the task
/// inspector's date fields (built-in "Due" plus `date`-type custom
/// fields) used to be free-text `YYYY-MM-DD` boxes. Shows a "Set date"
/// affordance while unset, then the picker plus a clear button once a
/// date is chosen. `onChange(nil)` clears the value.
private struct OptionalDateField: View {
    /// Current value as `YYYY-MM-DD`, or "" when unset.
    let value: String
    let onChange: (String?) -> Void

    var body: some View {
        if value.isEmpty {
            Button("Set date") { onChange(ISODate.today()) }
                .buttonStyle(.link)
                .font(.callout)
        } else {
            HStack(spacing: 6) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { ISODate.parse(value) },
                        set: { onChange(ISODate.string(from: $0)) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Button { onChange(nil) } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear date")
            }
        }
    }
}
