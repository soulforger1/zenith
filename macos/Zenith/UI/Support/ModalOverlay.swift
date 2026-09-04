import SwiftUI

/// A centered modal card over a dimmed, click-to-dismiss backdrop.
///
/// macOS's native `.sheet` is window-modal — it slides out of the titlebar
/// and there is no "outside" to click, so a sheet can only be closed from a
/// control inside it. The web build's dialogs (`components/ui/dialog.tsx`)
/// close on a backdrop press or Escape, and that's the behaviour these
/// modifiers restore: tap anywhere outside the card, or press Escape, to
/// dismiss. Controls inside the card work normally; the card itself swallows
/// clicks so they never reach the backdrop.
extension View {
    /// `alignment` positions the card in the window — `.center` (default)
    /// for forms, `.top` for a Spotlight-style command palette.
    func modalOverlay<Modal: View>(
        isPresented: Binding<Bool>,
        alignment: Alignment = .center,
        @ViewBuilder content: @escaping () -> Modal
    ) -> some View {
        overlay {
            ModalOverlay(isPresented: isPresented, alignment: alignment, content: content)
        }
    }

    /// `item`-driven variant, mirroring `.sheet(item:)`. The last non-nil
    /// value is held for the duration of the dismiss animation so the card
    /// fades out with its content intact rather than blanking.
    func modalOverlay<Item: Identifiable, Modal: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Modal
    ) -> some View {
        overlay {
            ModalItemOverlay(item: item, content: content)
        }
    }
}

private extension AnyTransition {
    static var modalCard: AnyTransition { .opacity.combined(with: .scale(scale: 0.97)) }
}

private extension Animation {
    static var modal: Animation { .easeOut(duration: 0.16) }
}

private struct ModalBackdrop: View {
    let onDismiss: () -> Void

    var body: some View {
        Rectangle()
            .fill(.black.opacity(0.3))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Dismiss")
            .transition(.opacity)
    }
}

private struct ModalCard<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.separator, lineWidth: 1)
            )
            // Make the whole card rect hittable so a click on a gap between
            // its controls is caught here, not passed through to the
            // backdrop's dismiss gesture. (ZStack layering already blocks
            // fall-through everywhere the card paints an opaque pixel.)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            // Escape-to-close, matching the web dialog. A hidden
            // `.cancelAction` button fires regardless of which control holds
            // focus; `.onExitCommand` covers the no-focus case.
            .background(
                Button("", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .accessibilityHidden(true)
            )
            .onExitCommand(perform: onDismiss)
            .padding(24)
            .transition(AnyTransition.modalCard)
    }
}

private struct ModalOverlay<Modal: View>: View {
    @Binding var isPresented: Bool
    var alignment: Alignment = .center
    @ViewBuilder let content: () -> Modal

    var body: some View {
        ZStack(alignment: alignment) {
            if isPresented {
                ModalBackdrop { isPresented = false }
                ModalCard(onDismiss: { isPresented = false }) { content() }
                    .padding(.top, alignment == .top ? 48 : 0)
            }
        }
        .animation(Animation.modal, value: isPresented)
    }
}

private struct ModalItemOverlay<Item: Identifiable, Modal: View>: View {
    @Binding var item: Item?
    @ViewBuilder let content: (Item) -> Modal

    @State private var shown: Item?

    var body: some View {
        ZStack {
            if let shown {
                ModalBackdrop { item = nil }
                ModalCard(onDismiss: { item = nil }) { content(shown) }
            }
        }
        .animation(Animation.modal, value: shown?.id)
        .onChange(of: item?.id) { _, _ in
            // Keep rendering the outgoing value through the fade-out.
            if let item { shown = item } else { shown = nil }
        }
        .onAppear { shown = item }
    }
}
