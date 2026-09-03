public extension Error {
    /// User-facing diagnostic description for errors surfaced in the UI.
    /// `String(describing:)` gives PostgresNIO's `PSQLError` a
    /// deliberately generic, redacted placeholder ("prevent accidental
    /// leakage of sensitive data") — the library's own message points
    /// callers at `String(reflecting:)` for the real detail instead. Safe
    /// here since this is a single-user local app showing errors to its
    /// own owner, never sent anywhere. `String(reflecting:)` works fine
    /// for any error type, not just `PSQLError`, so this is the one
    /// diagnostic-message helper every call site should use.
    var diagnosticDescription: String {
        String(reflecting: self)
    }
}
