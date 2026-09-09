import SwiftUI
import ZenithData

/// Port of `milestone-form-dialog.tsx` — shared create/edit form, as a
/// native `Form` sheet.
struct MilestoneFormSheet: View {
    enum Mode {
        case create(spaceId: UUID)
        case edit(Milestone)
    }

    let model: SpaceDetailModel
    let mode: Mode
    let onDismiss: () -> Void

    @State private var title: String
    @State private var description: String
    @State private var dueDate: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(model: SpaceDetailModel, mode: Mode, onDismiss: @escaping () -> Void) {
        self.model = model
        self.mode = mode
        self.onDismiss = onDismiss
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _description = State(initialValue: "")
            _dueDate = State(initialValue: "")
        case .edit(let milestone):
            _title = State(initialValue: milestone.title)
            _description = State(initialValue: milestone.description ?? "")
            _dueDate = State(initialValue: milestone.dueDate ?? "")
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Due Date", text: $dueDate, prompt: Text("YYYY-MM-DD, optional"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onDismiss)
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    if isSaving { ProgressView().controlSize(.small) } else { Text("Save") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle(isEditing ? "Edit Milestone" : "New Milestone")
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        let trimmedDue = dueDate.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        do {
            switch mode {
            case .create:
                try await model.createMilestone(
                    title: title, description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    dueDate: trimmedDue.isEmpty ? nil : trimmedDue
                )
            case .edit(let milestone):
                try await model.updateMilestone(
                    milestone.id, title: title, description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    dueDate: trimmedDue.isEmpty ? nil : trimmedDue
                )
            }
            onDismiss()
        } catch {
            errorMessage = error.diagnosticDescription
        }
        isSaving = false
    }
}
