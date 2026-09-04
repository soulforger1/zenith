import Foundation
import Observation

/// App-wide transient feedback queue — the native stand-in for the web
/// build's `sonner` toasts (which went away with the Electron/Next shell).
/// Structured and injected exactly like `AppShellModel`: owned by
/// `ZenithApp`, handed down via `.environment()`, read with
/// `@Environment(ToastCenter.self)`.
///
/// Mutations funnel through `SpaceDetailModel` / `SpacesListModel`, so
/// those view models hold a reference and call `success(_:)` / `error(_:)`
/// from each CRUD path rather than every view wiring its own feedback.
@Observable
@MainActor
public final class ToastCenter {
    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        public var message: String
        public var style: Style

        public enum Style: Equatable {
            case success
            case error
        }
    }

    /// At most `maxVisible` cards on screen at once — a burst of actions
    /// drops the oldest rather than stacking indefinitely.
    private static let maxVisible = 3

    public private(set) var toasts: [Toast] = []

    /// Per-toast auto-dismiss timers, so a coalesced repeat or a manual
    /// dismiss can cancel the pending one instead of racing it.
    @ObservationIgnored
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    public func success(_ message: String) { post(message, style: .success) }
    public func error(_ message: String) { post(message, style: .error) }

    /// Errors linger longer than confirmations — the user may want to read
    /// the diagnostic text.
    private func lifetime(for style: Toast.Style) -> Duration {
        style == .error ? .seconds(5) : .seconds(2.5)
    }

    private func post(_ message: String, style: Toast.Style) {
        // Coalesce: a repeated identical message (rapid field autosaves,
        // repeated board drags all reading "Saved") just restarts the
        // existing card's dismiss timer instead of piling up.
        if let last = toasts.last, last.message == message, last.style == style {
            scheduleDismiss(id: last.id, style: style)
            return
        }

        let toast = Toast(message: message, style: style)
        toasts.append(toast)
        while toasts.count > Self.maxVisible {
            dismiss(toasts[0].id)
        }
        scheduleDismiss(id: toast.id, style: style)
    }

    private func scheduleDismiss(id: UUID, style: Toast.Style) {
        dismissTasks[id]?.cancel()
        let lifetime = lifetime(for: style)
        dismissTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    public func dismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        toasts.removeAll { $0.id == id }
    }
}
