import SwiftUI

/// Offered once, on first launch after upgrading from the pre-local-first
/// app: a chance to copy an existing Postgres database's data into the new
/// local SQLite store, which is now the single source of truth. Reachable
/// again later (Phase 2) from Settings → Sync via the same
/// `AppEnvironment.runPostgresImport` entry point. Replaces `SetupView`,
/// which used to gate the whole app on this same connection string; now
/// it's purely optional and layered over an already-usable app.
struct ImportFromPostgresView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State var connectionString: String
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Text("Import Your Data")
                    .font(.title2.bold())
                Text("Zenith found a previous Postgres database connection. Import its spaces and tasks into the new local database?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            .padding(.bottom, 20)
            .padding(.horizontal, 24)

            Form {
                Section {
                    TextField("Database URL", text: $connectionString, prompt: Text("postgres://user:password@host:5432/database"))
                        .disableAutocorrection(true)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Skip") {
                    environment.dismissPostgresImportOffer()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(isImporting)

                Spacer()

                Button {
                    Task { await runImport() }
                } label: {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Import")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(connectionString.trimmingCharacters(in: .whitespaces).isEmpty || isImporting)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(isImporting)
    }

    private func runImport() async {
        isImporting = true
        errorMessage = nil
        let error = await environment.runPostgresImport(connectionString: connectionString)
        isImporting = false
        if let error {
            errorMessage = error
        } else {
            dismiss()
        }
    }
}

#Preview {
    ImportFromPostgresView(connectionString: "postgres://user:password@host:5432/database")
        .environment(AppEnvironment())
}
