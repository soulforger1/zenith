import SwiftUI
import ZenithData

/// Read-only rendering of a `FieldDisplayValue` — port of `FieldBadge`,
/// reused wherever a Table cell (or, later, any other read-only field
/// display) needs to show an arbitrary field's value without knowing its
/// concrete type ahead of time.
struct FieldDisplayValueView: View {
    let value: FieldDisplayValue

    var body: some View {
        switch value {
        case .empty:
            Text("—").foregroundStyle(.secondary)
        case .text(let text):
            Text(text).font(.callout).lineLimit(1)
        case .branch(let branch):
            Text("⎇ \(branch)").font(.caption.monospaced()).foregroundStyle(.blue)
        case .date(let iso):
            Text(formattedDate(iso)).font(.caption.monospaced()).foregroundStyle(.secondary)
        case .option(let option):
            OptionChipView(option: option)
        case .options(let options):
            FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(options) { OptionChipView(option: $0) }
            }
        case .rawTags(let tags):
            FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedDate(_ iso: String) -> String {
        ISODate.parse(iso).formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct OptionChipView: View {
    let option: NormalizedOption

    var body: some View {
        let color = Theme.fieldColor(FieldColors.color(named: option.color))
        Text(option.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }
}
