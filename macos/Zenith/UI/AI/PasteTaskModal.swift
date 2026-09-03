import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ZenithAI
import ZenithData

/// Port of `paste-task-modal.tsx`. Single-task mode: paste text (+ optional
/// screenshot) -> "Parse ✦" -> editable draft -> "Add to Backlog". List
/// mode: paste text -> "Parse ✦" -> checkable list of drafts -> "Create N
/// tasks". Operates on one `SpaceDetailModel` (the space the sidebar's
/// "Paste task" button was invoked from), calling straight through to
/// `AIOrchestration`/`IssueActions` the same way the route handlers +
/// server actions did on the web side.
///
/// Known simplification vs. the web build: list-mode rows don't expose a
/// per-row repo picker (single-task mode's full repo/milestone/custom-field
/// editing is unaffected) — the AI's own repo resolution still applies, it
/// just isn't user-editable per row before committing a bulk paste.
struct PasteTaskModal: View {
    let model: SpaceDetailModel
    let onDismiss: () -> Void

    private enum Mode: String, CaseIterable {
        case single = "Single task"
        case list = "List of tasks"
    }

    @State private var mode: Mode = .single
    @State private var text = ""
    @State private var attachedImageData: Data?
    @State private var attachedImageMimeType = "image/png"
    @State private var isParsing = false
    @State private var isCommitting = false
    @State private var errorMessage: String?
    @State private var isImportingImage = false

    @State private var draft: EditableDraft?
    @State private var listDrafts: [EditableListDraft] = []
    @State private var hasParsedList = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == .single {
                        singleModeBody
                    } else {
                        listModeBody
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.callout)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: mode == .list ? 640 : 560)
        .frame(minHeight: 320, maxHeight: 640)
        .fileImporter(isPresented: $isImportingImage, allowedContentTypes: [.image]) { result in
            importImage(result)
        }
        // The modal can be opened straight from the Dashboard (no
        // `SpaceDetailContainer` around to have already triggered a load),
        // so it ensures its own target space's repos/milestones/custom
        // fields are loaded before the user gets to the draft-editing step.
        .task { if model.views.isEmpty { await model.load() } }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Paste from manager").font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if inputPhase {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in resetAll() }
            } else {
                Text("Adding to \(model.space.name)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var inputPhase: Bool {
        draft == nil && !hasParsedList
    }

    // MARK: - Single mode

    @ViewBuilder
    private var singleModeBody: some View {
        if let draft {
            singleDraftForm(Binding(get: { draft }, set: { self.draft = $0 }))
        } else {
            singleInputForm
        }
    }

    private var singleInputForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 140)
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                if text.isEmpty {
                    Text("Paste a task description, ticket text, or a screenshot…")
                        .foregroundStyle(.tertiary)
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                Button {
                    isImportingImage = true
                } label: {
                    Label("Attach file…", systemImage: "paperclip")
                }
                Button {
                    pasteImageFromClipboard()
                } label: {
                    Label("Paste screenshot", systemImage: "photo.on.rectangle")
                }
                if let attachedImageData, let nsImage = NSImage(data: attachedImageData) {
                    HStack(spacing: 4) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Button {
                            self.attachedImageData = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func singleDraftForm(_ draft: Binding<EditableDraft>) -> some View {
        Form {
            Section {
                TextField("Title", text: draft.title)
                TextField("Description", text: draft.description, axis: .vertical).lineLimit(2...5)
                Picker("Priority", selection: draft.priority) {
                    ForEach(IssuePriority.allCases, id: \.self) { Text(priorityLabel($0)).tag($0) }
                }
                TextField("Estimate", text: draft.estimate, prompt: Text("Optional"))
                TextField("Branch", text: draft.branch, prompt: Text("Optional"))
                TextField("Due date", text: draft.dueDate, prompt: Text("YYYY-MM-DD, optional"))
                TextField("Tags", text: draft.tagText, prompt: Text("comma, separated"))
            }

            if !model.repos.isEmpty {
                Section("Repos") {
                    ForEach(model.repos) { repo in
                        Toggle(repo.name, isOn: repoBinding(draft, repo.id))
                    }
                }
            }

            if !model.milestones.isEmpty {
                Section("Milestone") {
                    Picker("Milestone", selection: draft.milestoneId) {
                        Text("None").tag(UUID?.none)
                        ForEach(model.milestones) { milestone in
                            Text(milestone.title).tag(Optional(milestone.id))
                        }
                    }
                    .labelsHidden()
                }
            }

            if !model.customFields.isEmpty {
                Section("Custom Fields") {
                    ForEach(model.customFields.sorted { $0.position < $1.position }) { field in
                        customFieldEditor(field: field, draft: draft)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func repoBinding(_ draft: Binding<EditableDraft>, _ repoId: UUID) -> Binding<Bool> {
        Binding(
            get: { draft.wrappedValue.repoIds.contains(repoId) },
            set: { isOn in
                if isOn { draft.wrappedValue.repoIds.insert(repoId) } else { draft.wrappedValue.repoIds.remove(repoId) }
            }
        )
    }

    @ViewBuilder
    private func customFieldEditor(field: CustomField, draft: Binding<EditableDraft>) -> some View {
        let key = field.id.uuidString
        switch field.type {
        case .text, .number, .date:
            TextField(field.name, text: stringBinding(draft, key: key, isNumber: field.type == .number))
        case .singleSelect:
            Picker(field.name, selection: selectBinding(draft, key: key)) {
                Text("None").tag("")
                ForEach(field.options.fieldOptions) { option in
                    Text(option.name).tag(option.id)
                }
            }
        case .multiSelect:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.name)
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(field.options.fieldOptions) { option in
                        let isSelected = multiSelectIds(draft, key: key).contains(option.id)
                        Button {
                            toggleMultiSelect(draft, key: key, optionId: option.id)
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
            }
        case .iteration:
            Picker(field.name, selection: selectBinding(draft, key: key)) {
                Text("None").tag("")
                ForEach(field.options.iterationOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
        }
    }

    private func stringBinding(_ draft: Binding<EditableDraft>, key: String, isNumber: Bool) -> Binding<String> {
        Binding(
            get: {
                switch draft.wrappedValue.customFieldValues[key] {
                case .string(let s): return s
                case .number(let n): return String(n)
                default: return ""
                }
            },
            set: { newValue in
                if newValue.isEmpty {
                    draft.wrappedValue.customFieldValues.removeValue(forKey: key)
                } else if isNumber {
                    if let number = Double(newValue) { draft.wrappedValue.customFieldValues[key] = .number(number) }
                } else {
                    draft.wrappedValue.customFieldValues[key] = .string(newValue)
                }
            }
        )
    }

    private func selectBinding(_ draft: Binding<EditableDraft>, key: String) -> Binding<String> {
        Binding(
            get: {
                if case .string(let s) = draft.wrappedValue.customFieldValues[key] { return s }
                return ""
            },
            set: { newValue in
                if newValue.isEmpty { draft.wrappedValue.customFieldValues.removeValue(forKey: key) }
                else { draft.wrappedValue.customFieldValues[key] = .string(newValue) }
            }
        )
    }

    private func multiSelectIds(_ draft: Binding<EditableDraft>, key: String) -> Set<String> {
        if case .array(let items) = draft.wrappedValue.customFieldValues[key] {
            return Set(items.compactMap { if case .string(let s) = $0 { return s }; return nil })
        }
        return []
    }

    private func toggleMultiSelect(_ draft: Binding<EditableDraft>, key: String, optionId: String) {
        var ids = multiSelectIds(draft, key: key)
        if ids.contains(optionId) { ids.remove(optionId) } else { ids.insert(optionId) }
        draft.wrappedValue.customFieldValues[key] = ids.isEmpty ? nil : .array(ids.map { .string($0) })
    }

    // MARK: - List mode

    @ViewBuilder
    private var listModeBody: some View {
        if hasParsedList {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($listDrafts) { $row in
                    listDraftRow($row)
                }
                if listDrafts.isEmpty {
                    Text("No tasks parsed.").foregroundStyle(.secondary)
                }
            }
        } else {
            listInputForm
        }
    }

    private var listInputForm: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 180)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            if text.isEmpty {
                Text("Paste a list of tasks, one per line or a longer note…")
                    .foregroundStyle(.tertiary)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
    }

    private func listDraftRow(_ row: Binding<EditableListDraft>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: row.include).labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: row.title).textFieldStyle(.plain).font(.body.weight(.medium))
                TextField("Description", text: row.description, prompt: Text("Optional"))
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("", selection: row.priority) {
                ForEach(IssuePriority.allCases, id: \.self) { Text(priorityLabel($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
            if !model.milestones.isEmpty {
                Picker("", selection: row.milestoneId) {
                    Text("No milestone").tag(UUID?.none)
                    ForEach(model.milestones) { milestone in
                        Text(milestone.title).tag(Optional(milestone.id))
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            Button {
                listDrafts.removeAll { $0.id == row.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("Cancel", action: onDismiss)
            Spacer()
            if mode == .single {
                if draft == nil {
                    Button {
                        Task { await parseSingle() }
                    } label: {
                        if isParsing { ProgressView().controlSize(.small) } else { Label("Parse", systemImage: "sparkles") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                } else {
                    Button {
                        Task { await commitSingle() }
                    } label: {
                        if isCommitting { ProgressView().controlSize(.small) } else { Text("Add to Backlog") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft?.title.trimmingCharacters(in: .whitespaces).isEmpty ?? true || isCommitting)
                }
            } else {
                if !hasParsedList {
                    Button {
                        Task { await parseList() }
                    } label: {
                        if isParsing { ProgressView().controlSize(.small) } else { Label("Parse", systemImage: "sparkles") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                } else {
                    Button {
                        Task { await commitList() }
                    } label: {
                        if isCommitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Create \(includedCount) task\(includedCount == 1 ? "" : "s")")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(includedCount == 0 || isCommitting)
                }
            }
        }
        .padding(16)
    }

    private var includedCount: Int {
        listDrafts.filter { $0.include && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    // MARK: - Actions

    private func resetAll() {
        text = ""
        attachedImageData = nil
        draft = nil
        listDrafts = []
        hasParsedList = false
        errorMessage = nil
    }

    private func parseSingle() async {
        isParsing = true
        errorMessage = nil
        let attachedImage = attachedImageData.map { AttachedImage(mimeType: attachedImageMimeType, data: $0.base64EncodedString()) }
        do {
            let resolved = try await model.parseTask(text: text, attachedImage: attachedImage)
            await model.refreshCustomFields()
            draft = EditableDraft(
                title: resolved.task.title,
                description: resolved.task.description ?? "",
                priority: resolved.task.priority,
                tagText: resolved.task.tags.joined(separator: ", "),
                branch: resolved.task.branch ?? "",
                estimate: resolved.task.estimate ?? "",
                dueDate: resolved.task.dueDate ?? "",
                repoIds: Set(resolved.repoIds),
                milestoneId: resolved.milestoneId,
                customFieldValues: resolved.customFieldValues
            )
        } catch {
            errorMessage = error.diagnosticDescription
        }
        isParsing = false
    }

    private func commitSingle() async {
        guard let draft else { return }
        isCommitting = true
        let taskDraft = IssueActions.TaskDraft(
            title: draft.title,
            description: draft.description.isEmpty ? nil : draft.description,
            priority: draft.priority,
            tags: draft.tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            branch: draft.branch.isEmpty ? nil : draft.branch,
            estimate: draft.estimate.isEmpty ? nil : draft.estimate,
            dueDate: draft.dueDate.isEmpty ? nil : draft.dueDate,
            repoIds: Array(draft.repoIds),
            milestoneId: draft.milestoneId,
            customFieldValues: draft.customFieldValues
        )
        if let error = await model.createIssueFromDraft(taskDraft) {
            errorMessage = error
        } else {
            onDismiss()
        }
        isCommitting = false
    }

    private func parseList() async {
        isParsing = true
        errorMessage = nil
        do {
            let resolved = try await model.parseTasks(text: text)
            await model.refreshCustomFields()
            listDrafts = resolved.map { item in
                EditableListDraft(
                    include: true,
                    title: item.task.title,
                    description: item.task.description ?? "",
                    priority: item.task.priority,
                    tags: item.task.tags,
                    branch: item.task.branch ?? "",
                    estimate: item.task.estimate ?? "",
                    dueDate: item.task.dueDate ?? "",
                    repoIds: item.repoIds,
                    milestoneId: item.milestoneId,
                    customFieldValues: item.customFieldValues
                )
            }
            hasParsedList = true
        } catch {
            errorMessage = error.diagnosticDescription
        }
        isParsing = false
    }

    private func commitList() async {
        let included = listDrafts.filter { $0.include && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !included.isEmpty else { return }
        isCommitting = true
        let drafts = included.map { row in
            IssueActions.TaskDraft(
                title: row.title,
                description: row.description.isEmpty ? nil : row.description,
                priority: row.priority,
                tags: row.tags,
                branch: row.branch.isEmpty ? nil : row.branch,
                estimate: row.estimate.isEmpty ? nil : row.estimate,
                dueDate: row.dueDate.isEmpty ? nil : row.dueDate,
                repoIds: row.repoIds,
                milestoneId: row.milestoneId,
                customFieldValues: row.customFieldValues
            )
        }
        if let error = await model.createIssuesFromDrafts(drafts) {
            errorMessage = error
        } else {
            onDismiss()
        }
        isCommitting = false
    }

    private func priorityLabel(_ priority: IssuePriority) -> String {
        switch priority {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    private func pasteImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) {
            attachedImageData = data
            attachedImageMimeType = "image/png"
        } else if let tiffData = pasteboard.data(forType: .tiff),
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        {
            attachedImageData = pngData
            attachedImageMimeType = "image/png"
        }
    }

    private func importImage(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            attachedImageData = try Data(contentsOf: url)
            attachedImageMimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditableDraft {
    var title: String
    var description: String
    var priority: IssuePriority
    var tagText: String
    var branch: String
    var estimate: String
    var dueDate: String
    var repoIds: Set<UUID>
    var milestoneId: UUID?
    var customFieldValues: [String: AnyCodableValue]
}

private struct EditableListDraft: Identifiable {
    let id = UUID()
    var include: Bool
    var title: String
    var description: String
    var priority: IssuePriority
    var tags: [String]
    var branch: String
    var estimate: String
    var dueDate: String
    var repoIds: [UUID]
    var milestoneId: UUID?
    var customFieldValues: [String: AnyCodableValue]
}
