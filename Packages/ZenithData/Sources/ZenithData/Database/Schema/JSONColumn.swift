import Foundation

/// Helpers for the columns the app stores as JSON text in SQLite —
/// `issues.custom_field_values`, `issues.tags`, `custom_fields.options`,
/// `views.config`. (Postgres held these as `jsonb` / `text[]`.)
enum JSONColumn {
    static func decodeMap(_ text: String?) throws -> [String: AnyCodableValue] {
        guard let text, !text.isEmpty else { return [:] }
        return try JSONDecoder().decode([String: AnyCodableValue].self, from: Data(text.utf8))
    }

    static func encodeMap(_ map: [String: AnyCodableValue]) throws -> String {
        String(decoding: try JSONEncoder().encode(map), as: UTF8.self)
    }

    static func decodeStringArray(_ text: String?) throws -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return try JSONDecoder().decode([String].self, from: Data(text.utf8))
    }

    static func encodeStringArray(_ values: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }
}

extension FieldOptions {
    /// JSON text for the `custom_fields.options` column.
    func jsonText() throws -> String {
        String(decoding: try encoded(), as: UTF8.self)
    }

    static func fromJSONText(_ text: String?, type: CustomFieldType) throws -> FieldOptions {
        let raw = (text?.isEmpty == false) ? text! : "[]"
        return try decode(jsonData: Data(raw.utf8), type: type)
    }
}

extension ViewConfig {
    /// JSON text for the `views.config` column.
    func jsonText() throws -> String {
        String(decoding: try encoded(), as: UTF8.self)
    }

    static func fromJSONText(_ text: String?, type: ViewType) throws -> ViewConfig {
        let raw = (text?.isEmpty == false) ? text! : "{}"
        return try decode(jsonData: Data(raw.utf8), type: type)
    }
}
