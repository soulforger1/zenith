import SwiftUI
import ZenithData
import UniformTypeIdentifiers

/// Port of `app/(app)/spaces/[spaceSlug]/settings/page.tsx` — a single
/// native `Form` (System-Settings-pane look) covering everything the web
/// page split across `SpaceContextForm`/`FieldManager`/`RepoManager`/
/// `SpaceImageGallery`: AI context, custom fields, GitHub repos, reference
/// images. The web page's standalone "Spaces" quick-list and static
/// keyboard-shortcuts table aren't ported — the sidebar already covers
/// space switching and there's no command-palette-driven shortcuts sheet
/// yet for a reference table to document.
struct SettingsView: View {
    let model: SpaceDetailModel

    @State private var context: String = ""
    @State private var isSavingContext = false
    @State private var editingField: CustomField?
    @State private var isCreatingField = false
    @State private var newRepoName = ""
    @State private var newRepoUrl = ""
    @State private var isAddingRepo = false
    @State private var repoError: String?
    @State private var syncingRepoId: UUID?
    @State private var isImportingImage = false
    @State private var imageError: String?

    var body: some View {
        Form {
            Section {
                TextField("Context", text: $context, prompt: Text("Notes the AI should know about this space…"), axis: .vertical)
                    .lineLimit(4...10)
                    .onChange(of: context) { _, _ in isSavingContext = true }
                    .onSubmit { Task { await saveContext() } }
                if isSavingContext {
                    Text("Press ⏎ or click away to save").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("AI Context")
            } footer: {
                Text("Prepended to every AI paste-task prompt for this space.")
            }
            .onDisappear { Task { await saveContext() } }

            customFieldsSection
            reposSection
            imagesSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task(id: model.space.id) { context = model.space.context ?? "" }
        .sheet(item: $editingField) { field in
            CustomFieldFormSheet(model: model, mode: .edit(field)) { editingField = nil }
        }
        .sheet(isPresented: $isCreatingField) {
            CustomFieldFormSheet(model: model, mode: .create) { isCreatingField = false }
        }
    }

    private func saveContext() async {
        guard isSavingContext else { return }
        isSavingContext = false
        await model.updateContext(context)
    }

    // MARK: - Custom fields

    private var customFieldsSection: some View {
        Section {
            if model.customFields.isEmpty {
                Text("No custom fields yet").foregroundStyle(.secondary)
            } else {
                ForEach(model.customFields.sorted { $0.position < $1.position }) { field in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.name)
                            Text(typeLabel(field.type)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            editingField = field
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            Task { await model.deleteCustomField(field.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                isCreatingField = true
            } label: {
                Label("Add field", systemImage: "plus")
            }
        } header: {
            Text("Custom Fields")
        }
    }

    private func typeLabel(_ type: CustomFieldType) -> String {
        switch type {
        case .text: return "Text"
        case .number: return "Number"
        case .date: return "Date"
        case .singleSelect: return "Single select"
        case .multiSelect: return "Multi select"
        case .iteration: return "Iteration"
        }
    }

    // MARK: - GitHub repos

    private var reposSection: some View {
        Section {
            if model.repos.isEmpty {
                Text("No repos linked yet").foregroundStyle(.secondary)
            } else {
                ForEach(model.repos) { repo in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.name)
                            Text(repo.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let cachedAt = repo.cachedAt {
                                Text("Synced \(cachedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            } else {
                                Text("Not synced").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if syncingRepoId == repo.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Sync") { Task { await sync(repo.id) } }
                                .buttonStyle(.bordered)
                        }
                        Button(role: .destructive) {
                            Task { await model.deleteRepo(repo.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField("Name", text: $newRepoName)
                TextField("owner/repo or URL", text: $newRepoUrl)
                Button("Add") { Task { await addRepo() } }
                    .disabled(newRepoName.trimmingCharacters(in: .whitespaces).isEmpty
                        || newRepoUrl.trimmingCharacters(in: .whitespaces).isEmpty || isAddingRepo)
            }
            if let repoError {
                Text(repoError).foregroundStyle(.red).font(.caption)
            }
        } header: {
            Text("GitHub Repos")
        } footer: {
            Text("Linked repos are summarized by AI (on manual Sync) and included as context when parsing tasks.")
        }
    }

    private func addRepo() async {
        isAddingRepo = true
        repoError = nil
        if let error = await model.createRepo(name: newRepoName, url: newRepoUrl) {
            repoError = error
        } else {
            newRepoName = ""
            newRepoUrl = ""
        }
        isAddingRepo = false
    }

    private func sync(_ id: UUID) async {
        syncingRepoId = id
        repoError = await model.syncRepo(id)
        syncingRepoId = nil
    }

    // MARK: - Reference images

    private var imagesSection: some View {
        Section {
            let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(model.images) { image in
                    ImageThumbnail(image: image) {
                        Task { await model.deleteImage(image.id) }
                    }
                }
                Button {
                    isImportingImage = true
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.tertiary)
                        .frame(width: 80, height: 80)
                        .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            if let imageError {
                Text(imageError).foregroundStyle(.red).font(.caption)
            }
        } header: {
            Text("Reference Images")
        } footer: {
            Text("Sent as visual context alongside this space's text context on every AI paste-task parse.")
        }
        .fileImporter(isPresented: $isImportingImage, allowedContentTypes: [.image]) { result in
            Task { await importImage(result) }
        }
    }

    private func importImage(_ result: Result<URL, Error>) async {
        imageError = nil
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                imageError = "Couldn't access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            if let error = await model.addImage(data: data, mimeType: mimeType, label: url.lastPathComponent) {
                imageError = error
            }
        } catch {
            imageError = error.localizedDescription
        }
    }
}

private struct ImageThumbnail: View {
    let image: SpaceImage
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let nsImage = decodedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 80, height: 80)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(3)
            }
        }
        .onHover { isHovering = $0 }
    }

    private var decodedImage: NSImage? {
        guard let (_, base64) = DataURLDecoding.parse(image.dataUrl),
            let data = Data(base64Encoded: base64)
        else { return nil }
        return NSImage(data: data)
    }
}

/// Local mirror of `ZenithAI.DataURL.parse` — the app target doesn't
/// import `ZenithAI` just for this one thumbnail-decoding helper.
private enum DataURLDecoding {
    static func parse(_ dataUrl: String) -> (mimeType: String, data: String)? {
        guard let commaIndex = dataUrl.firstIndex(of: ","), dataUrl.hasPrefix("data:") else { return nil }
        let header = dataUrl[dataUrl.index(dataUrl.startIndex, offsetBy: 5)..<commaIndex]
        guard header.hasSuffix(";base64") else { return nil }
        let mimeType = String(header.dropLast(";base64".count))
        let data = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard !mimeType.isEmpty, !data.isEmpty else { return nil }
        return (mimeType, data)
    }
}
