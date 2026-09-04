import SwiftUI
import ZenithData

/// Port of `space-tabs.tsx`'s `NewViewButton` dialog — name + type, then
/// `ViewActions.createView` (via `SpaceDetailModel.createView`). The caller
/// navigates to the returned view; `onFinish(nil)` means the user cancelled.
struct NewViewSheet: View {
    let model: SpaceDetailModel
    let onFinish: (ZView?) -> Void

    @State private var name = ""
    @State private var type: ViewType = .table
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g. Sprint board"))
                    Picker("Type", selection: $type) {
                        ForEach(ViewType.allCases, id: \.self) { type in
                            Text(typeLabel(type)).tag(type)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onFinish(nil) }
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    if isSaving { ProgressView().controlSize(.small) } else { Text("Create View") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle("New View")
    }

    private func typeLabel(_ type: ViewType) -> String {
        switch type {
        case .table: return "Table"
        case .board: return "Board"
        case .roadmap: return "Roadmap"
        }
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        do {
            let view = try await model.createView(name: name, type: type)
            onFinish(view)
        } catch {
            errorMessage = error.diagnosticDescription
        }
        isSaving = false
    }
}
