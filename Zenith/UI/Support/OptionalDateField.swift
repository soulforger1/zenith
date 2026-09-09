import SwiftUI
import ZenithData

/// A `DatePicker` for an optional `YYYY-MM-DD` value — used everywhere a
/// due date (built-in or `date`-type custom field) is edited, so it's
/// never a free-text `YYYY-MM-DD` box the user has to type by hand. Shows
/// a "Set date" affordance while unset, then the picker plus a clear
/// button once a date is chosen. `onChange(nil)` clears the value.
struct OptionalDateField: View {
    /// Current value as `YYYY-MM-DD`, or "" when unset.
    let value: String
    let onChange: (String?) -> Void

    var body: some View {
        if value.isEmpty {
            Button("Set date") { onChange(ISODate.today()) }
                .buttonStyle(.link)
                .font(.callout)
        } else {
            HStack(spacing: 6) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { ISODate.parse(value) },
                        set: { onChange(ISODate.string(from: $0)) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Button { onChange(nil) } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear date")
            }
        }
    }
}
