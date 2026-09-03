/// Thrown by every `Actions/*.validate()` — one case per zod-style
/// constraint violation, carrying a user-facing message the way
/// `parsed.error.issues[0]?.message` did on the TypeScript side.
public struct ValidationError: Error, CustomStringConvertible, Sendable {
    public let field: String
    public let message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }

    public var description: String { message }
}
