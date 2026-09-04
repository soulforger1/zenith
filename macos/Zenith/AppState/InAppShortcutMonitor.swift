import AppKit

/// Bare-key in-app shortcuts that can't be expressed as SwiftUI
/// `.keyboardShortcut` values — a modifier-less letter attached to a menu
/// command (or a `.keyboardShortcut("c", modifiers: [])`) is swallowed out
/// of every text field in the app. This is a local `NSEvent` monitor with
/// the same explicit "not currently typing" guard that
/// `components/layout/app-shell.tsx`'s `keydown` listener uses on the web.
///
/// Currently handled: `c` → open the paste-task modal (matches
/// `lib/shortcuts.ts`' "C"). Modified combos stay as menu commands in
/// `ZenithApp` (⌘K search, ⌘⇧V nothing anymore, ⌘N new space); the
/// system-wide ⌥⌥ quick-capture gesture stays in `OptionDoubleTapMonitor`.
@MainActor
final class InAppShortcutMonitor {
    private let shell: AppShellModel
    private var monitor: Any?

    init(shell: AppShellModel) {
        self.shell = shell
    }

    func start() {
        guard monitor == nil else { return }
        // Local only — this fires just while Zenith is key, and returning
        // `nil` swallows the event so the key doesn't also fall through to
        // whatever control has focus.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns `true` when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        // Only unmodified presses — ⌘/⌥/⌃/⇧ combos are the menu commands'
        // territory. (Caps Lock, Fn and numeric-pad flags are ignored.)
        let blocking: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(blocking).isEmpty else { return false }
        guard !isEditingText else { return false }

        switch event.charactersIgnoringModifiers {
        case "c":
            shell.openAiModal()
            return true
        default:
            return false
        }
    }

    /// True when a text field / editor holds focus — `NSTextView` (the
    /// field editor SwiftUI `TextField`/`TextEditor` use) is an `NSText`
    /// subclass, so this one check covers both.
    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }
}
