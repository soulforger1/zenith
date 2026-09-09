import SwiftUI

/// First-run setup — replaces Electron's separate setup `BrowserWindow`
/// (`electron/main.js`'s `runSetupWindow`, `electron/setup/index.html`).
/// Collects a Postgres connection string (required) and an optional GitHub
/// token, validates the DB connection before saving anything (real `SELECT
/// 1`, not just a well-formed-URL check), and persists via
/// `AppEnvironment.completeSetup`. Native `Form` (`.formStyle(.grouped)`)
/// — the same look as a System Settings pane — instead of a hand-rolled
/// field stack.
struct SetupView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var databaseUrl = ""
    @State private var githubToken = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Text("Set Up Zenith")
                    .font(.title2.bold())
                Text("Connect to your Postgres database to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 20)

            Form {
                Section {
                    TextField("Database URL", text: $databaseUrl, prompt: Text("postgres://user:password@host:5432/database"))
                        .disableAutocorrection(true)
                    SecureField("GitHub Token", text: $githubToken, prompt: Text("Optional"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    if isValidating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(databaseUrl.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func submit() async {
        isValidating = true
        errorMessage = nil
        let error = await environment.completeSetup(databaseUrl: databaseUrl, githubToken: githubToken)
        isValidating = false
        errorMessage = error
    }
}

#Preview {
    SetupView().environment(AppEnvironment())
}
