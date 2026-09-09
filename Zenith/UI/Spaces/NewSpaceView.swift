import SwiftUI
import ZenithData

/// Port of `app/(app)/spaces/new/page.tsx` + `space-form.tsx`, as a native
/// `Form` (`.formStyle(.grouped)` — the same look as System Settings
/// panes) instead of a hand-rolled field stack.
struct NewSpaceView: View {
    @Environment(AppShellModel.self) private var shell
    let model: SpacesListModel

    @State private var name = ""
    @State private var description = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("e.g. Work, Side Projects"))
                TextField("Description", text: $description, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(3...6)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Space")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { shell.route = .dashboard }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await submit() }
                } label: {
                    if isSaving { ProgressView().controlSize(.small) } else { Text("Create") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        do {
            let space = try await model.createSpace(
                name: name, description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description
            )
            shell.route = .space(space)
        } catch {
            errorMessage = error.diagnosticDescription
        }
        isSaving = false
    }
}
