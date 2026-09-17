import Foundation
import Security

/// Stores the optional GitHub token in the macOS Keychain instead of
/// alongside the DB URL in plaintext `config.json` — see
/// docs/native-rewrite-audit.md §6, decision 7.
public enum KeychainStore {
    private static let githubService = "com.zolboo.zenith.github-token"
    private static let githubAccount = "github-token"

    /// The Postgres sync target's connection string — moved here (out of
    /// plaintext `config.json`) now that it's an opt-in sync credential
    /// rather than something the app needs at every launch.
    private static let postgresService = "com.zolboo.zenith.postgres-url"
    private static let postgresAccount = "postgres-url"

    public static func githubToken() -> String? {
        read(service: githubService, account: githubAccount)
    }

    public static func setGithubToken(_ token: String?) {
        write(token, service: githubService, account: githubAccount)
    }

    public static func postgresConnectionString() -> String? {
        read(service: postgresService, account: postgresAccount)
    }

    public static func setPostgresConnectionString(_ value: String?) {
        write(value, service: postgresService, account: postgresAccount)
    }

    private static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String?, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        guard let value, !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = Data(value.utf8)
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
