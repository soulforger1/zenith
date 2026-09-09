import Foundation
import ZenithData

/// Port of `lib/ai/field-resolver.ts`. Applies the AI's proposed new fields
/// + field values to the space's real custom fields: creates any
/// genuinely-missing field (matched by key, case-insensitive, so a repeat
/// paste never double-creates "Size") and auto-grows select options for
/// values that don't match an existing one.
public enum FieldResolver {
    public struct ResolvedFields: Sendable {
        public let customFieldValues: [String: AnyCodableValue]
        public let fields: [CustomField]
    }

    public static func resolveAiCustomFields(
        _ db: ZenithDatabase, spaceId: UUID, customFields: [CustomField], newFields: [AINewField], fieldValues: [AIFieldValue]
    ) async throws -> ResolvedFields {
        var fields = customFields

        func findByKey(_ key: String) -> CustomField? {
            fields.first { $0.key.lowercased() == key.lowercased() }
        }

        for proposal in newFields.prefix(3) {
            guard !proposal.key.isEmpty, !proposal.name.isEmpty else { continue }
            guard findByKey(proposal.key) == nil else { continue }

            let isSelectType = proposal.type == .singleSelect || proposal.type == .multiSelect
            let options: FieldOptions
            if isSelectType {
                let labels = (proposal.options ?? []).prefix(10)
                let opts = labels.enumerated().map { index, label in
                    FieldOption(id: UUID().uuidString, name: label, color: FieldColors.values[index % FieldColors.values.count].rawValue)
                }
                options = .fields(opts)
            } else {
                options = .fields([])
            }

            // This resolver call site computes its own key preference
            // (proposed key, then name, then a numbered fallback) and talks
            // to `CustomFieldQueries` directly — deliberately bypassing
            // `CustomFieldActions.createCustomField`'s name-only key
            // derivation, matching the TS side's `resolveAiCustomFields`
            // (which imports from `lib/db/queries/custom-fields`, not the
            // actions layer, for exactly this reason).
            let slugifiedKey = Slug.slugify(proposal.key)
            let slugifiedName = Slug.slugify(proposal.name)
            let key = !slugifiedKey.isEmpty ? slugifiedKey : (!slugifiedName.isEmpty ? slugifiedName : "field-\(fields.count + 1)")
            let created = try await CustomFieldQueries.createCustomField(
                db, spaceId: spaceId, key: key, name: proposal.name, type: proposal.type, options: options
            )
            fields.append(created)
        }

        func resolveOrCreateOptionId(field: inout CustomField, label: String) async throws -> String? {
            var options = field.options.fieldOptions
            if let existing = options.first(where: { $0.name.lowercased() == label.lowercased() }) {
                return existing.id
            }
            let newOption = FieldOption(
                id: UUID().uuidString, name: label, color: FieldColors.values[options.count % FieldColors.values.count].rawValue
            )
            options.append(newOption)
            if let updated = try await CustomFieldQueries.updateCustomField(db, id: field.id, name: nil, options: .fields(options), position: nil) {
                field = updated
            }
            return newOption.id
        }

        var result: [String: AnyCodableValue] = [:]

        for entry in fieldValues.prefix(10) {
            guard let fieldIndex = fields.firstIndex(where: { $0.key.lowercased() == entry.fieldKey.lowercased() }) else { continue }
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            var field = fields[fieldIndex]
            defer { fields[fieldIndex] = field }

            switch field.type {
            case .text:
                result[field.id.uuidString] = .string(value)
            case .number:
                if let number = Double(value) { result[field.id.uuidString] = .number(number) }
            case .date:
                if value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                    result[field.id.uuidString] = .string(value)
                }
            case .singleSelect:
                if let id = try await resolveOrCreateOptionId(field: &field, label: value) {
                    result[field.id.uuidString] = .string(id)
                }
            case .multiSelect:
                let labels = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                var ids: [String] = []
                for label in labels {
                    if let id = try await resolveOrCreateOptionId(field: &field, label: label) { ids.append(id) }
                }
                if !ids.isEmpty { result[field.id.uuidString] = .array(ids.map { .string($0) }) }
            case .iteration:
                if let option = field.options.iterationOptions.first(where: { $0.title.lowercased() == value.lowercased() }) {
                    result[field.id.uuidString] = .string(option.id)
                }
            }
        }

        return ResolvedFields(customFieldValues: result, fields: fields)
    }
}
