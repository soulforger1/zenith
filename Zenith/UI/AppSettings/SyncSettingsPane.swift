import SwiftUI
import ZenithData
import ZenithSync

/// Postgres sync configuration — opt-in, off by default. The connection
/// string lives in Keychain (`KeychainStore.postgresConnectionString`),
/// same as the GitHub token; everything else (`postgresEnabled`,
/// `intervalMinutes`) persists via `AppEnvironment.saveSyncSettings` into
/// `config.json`.
struct SyncSettingsPane: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SyncCoordinator.self) private var syncCoordinator

    @State private var postgresEnabled = false
    @State private var connectionString = ""
    @State private var intervalMinutes = 15
    @State private var isTestingConnection = false
    @State private var testResult: String?
    @State private var isImporting = false
    @State private var importResult: String?

    // Sync always runs on demand via "Sync Now" regardless of this — the
    // interval is just the background cadence, so it's fine to default
    // toward infrequent (daily) rather than aggressive.
    private static let intervalOptions = [15, 30, 60, 180, 360, 720, 1440]

    private static func label(forMinutes minutes: Int) -> String {
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return days == 1 ? "1 day" : "\(days) days"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes) minutes"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Sync to Postgres", isOn: $postgresEnabled)
                SecureField("Connection URL", text: $connectionString, prompt: Text("postgres://user:password@host:5432/database"))
                    .disableAutocorrection(true)

                HStack {
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(connectionString.trimmingCharacters(in: .whitespaces).isEmpty || isTestingConnection)

                    if isTestingConnection {
                        ProgressView().controlSize(.small)
                    } else if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                    }
                }

                Button {
                    Task { await runImport() }
                } label: {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Import from Postgres Now…")
                    }
                }
                .disabled(connectionString.trimmingCharacters(in: .whitespaces).isEmpty || isImporting)

                if let importResult {
                    Text(importResult).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Postgres")
            } footer: {
                Text("Merges both ways on an interval — the most recently edited copy of each task wins. Importing copies the whole database in once; it doesn't need syncing to be on.")
            }

            Section {
                Picker("Sync every", selection: $intervalMinutes) {
                    ForEach(Self.intervalOptions, id: \.self) { minutes in
                        Text(Self.label(forMinutes: minutes)).tag(minutes)
                    }
                }

                HStack {
                    Button("Sync Now") {
                        Task { await syncCoordinator.syncNow() }
                    }
                    .disabled(!postgresEnabled)

                    Spacer()

                    statusView
                }
            } header: {
                Text("Schedule")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadFromSettings)
        .onChange(of: postgresEnabled) { _, _ in persist() }
        .onChange(of: connectionString) { _, _ in persist() }
        .onChange(of: intervalMinutes) { _, _ in persist() }
    }

    @ViewBuilder
    private var statusView: some View {
        switch syncCoordinator.status {
        case .idle:
            if let lastSyncedAt = syncCoordinator.lastSyncedAt {
                Text("Last synced \(lastSyncedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Never synced").font(.caption).foregroundStyle(.secondary)
            }
        case .syncing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Syncing…").font(.caption).foregroundStyle(.secondary)
            }
        case .error(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    private func loadFromSettings() {
        let settings = environment.syncSettings
        postgresEnabled = settings.postgresEnabled
        intervalMinutes = settings.intervalMinutes
        connectionString = KeychainStore.postgresConnectionString() ?? ""
    }

    private func persist() {
        KeychainStore.setPostgresConnectionString(connectionString.isEmpty ? nil : connectionString)
        var settings = environment.syncSettings
        settings.postgresEnabled = postgresEnabled
        settings.intervalMinutes = intervalMinutes
        environment.saveSyncSettings(settings)
        syncCoordinator.updateSettings(settings)
    }

    private func testConnection() async {
        isTestingConnection = true
        testResult = nil
        do {
            try await PostgresGateway.testConnection(connectionString: connectionString)
            testResult = "✓ Connected"
        } catch {
            testResult = "✗ \(error.diagnosticDescription)"
        }
        isTestingConnection = false
    }

    private func runImport() async {
        isImporting = true
        importResult = nil
        let error = await environment.runPostgresImport(connectionString: connectionString)
        isImporting = false
        importResult = error ?? "Import complete."
    }
}

#Preview {
    SyncSettingsPane()
        .environment(AppEnvironment())
        .environment(SyncCoordinator())
        .formStyle(.grouped)
        .frame(width: 480)
}
