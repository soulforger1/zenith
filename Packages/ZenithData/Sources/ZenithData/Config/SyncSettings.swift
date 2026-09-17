import Foundation

/// User-configured sync preferences — every target is off by default (sync
/// is opt-in). Phase 1 only needs the shape to exist so `AppConfig` has a
/// stable, forward-compatible place to persist it; the Postgres/iCloud sync
/// engines that actually read these fields land in Phase 2/3.
public struct SyncSettings: Codable, Sendable, Equatable {
    public var postgresEnabled: Bool
    public var iCloudEnabled: Bool
    /// `nil` means the default iCloud Drive location
    /// (`~/Library/Mobile Documents/com~apple~CloudDocs/Zenith`).
    public var iCloudFolderPath: String?
    public var intervalMinutes: Int

    public init(
        postgresEnabled: Bool = false, iCloudEnabled: Bool = false,
        iCloudFolderPath: String? = nil, intervalMinutes: Int = 15
    ) {
        self.postgresEnabled = postgresEnabled
        self.iCloudEnabled = iCloudEnabled
        self.iCloudFolderPath = iCloudFolderPath
        self.intervalMinutes = intervalMinutes
    }
}
