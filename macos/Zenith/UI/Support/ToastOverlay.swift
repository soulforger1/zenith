import SwiftUI

/// Host for `ToastCenter`'s transient cards — a bottom-trailing stack that
/// floats over everything (route content, modals, the task inspector)
/// without intercepting clicks anywhere except on a card itself.
///
/// Styling follows `ModalOverlay.swift`'s `ModalCard`: a `.regularMaterial`
/// rounded rect with a hairline `.separator` border and a soft shadow, and
/// the same `.easeOut(0.16)` timing.
extension View {
    func toastOverlay(_ center: ToastCenter) -> some View {
        overlay(alignment: .bottomTrailing) {
            ToastStack(center: center)
        }
    }
}

private struct ToastStack: View {
    let center: ToastCenter

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.toasts) { toast in
                ToastCard(toast: toast) { center.dismiss(toast.id) }
                    .transition(
                        .move(edge: .trailing).combined(with: .opacity)
                    )
            }
        }
        .padding(20)
        .animation(.easeOut(duration: 0.16), value: center.toasts)
        // Only the cards themselves are hittable; the rest of this overlay
        // never blocks the UI underneath.
        .allowsHitTesting(!center.toasts.isEmpty)
    }
}

private struct ToastCard: View {
    let toast: ToastCenter.Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(toast.message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibilityPrefix): \(toast.message)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to dismiss")
    }

    private var iconName: String {
        switch toast.style {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch toast.style {
        case .success: return .green
        case .error: return .red
        }
    }

    private var accessibilityPrefix: String {
        switch toast.style {
        case .success: return "Success"
        case .error: return "Error"
        }
    }
}
