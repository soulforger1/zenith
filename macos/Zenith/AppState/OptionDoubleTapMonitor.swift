import AppKit

/// Native port of `electron/main.js`'s `startOptionDoubleTapListener` —
/// double-tapping Option, from anywhere on the system (not just while
/// Zenith is focused, the same "quick capture" convention Raycast/Alfred
/// use), brings the app to the front and pops the paste-task modal open.
///
/// The Electron build needed a third-party raw key hook (`uiohook-napi`)
/// for this, since Electron's own `globalShortcut` API only matches full
/// accelerator combos, not a bare modifier tapped twice. AppKit's
/// `NSEvent` global/local monitors give the same raw `flagsChanged`/
/// `keyDown` stream natively, so no dependency is needed here — but the
/// two monitors below (global *and* local) are both required to fully
/// replace uiohook's behavior:
/// - `addGlobalMonitorForEvents` only delivers events belonging to *other*
///   applications (Apple's own documented behavior) — this is what makes
///   the gesture work while some other app is frontmost.
/// - `addLocalMonitorForEvents` delivers events while *Zenith itself* is
///   key — without it the gesture would stop working the moment the app
///   has focus, unlike uiohook's raw system-wide hook which doesn't care
///   about focus at all.
///
/// Both require the same Accessibility permission Electron's
/// `systemPreferences.isTrustedAccessibilityClient` needed — an OS
/// constraint, not something either implementation can avoid.
@MainActor
final class OptionDoubleTapMonitor {
    private let shell: AppShellModel
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Mirrors `main.js`'s constants exactly.
    private static let doubleTapWindow: TimeInterval = 0.4
    private static let maxTapHold: TimeInterval = 0.35
    private static let optionKeyCodes: Set<UInt16> = [58, 61] // left/right Option

    private var optionDownAt: Date?
    /// Goes false the moment any other key (or other modifier) is pressed
    /// while Option is held — a long Option hold used as a modifier for
    /// something else is not a "tap".
    private var optionHeldCleanly = false
    private var lastCleanTapAt: Date?

    init(shell: AppShellModel) {
        self.shell = shell
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        guard ensureAccessibilityPermission() else { return }

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            // Never swallowed — this only ever observes, never intercepts,
            // so normal typing/shortcuts elsewhere in the app are
            // unaffected. Dispatched onto the actor like the global
            // monitor's handler below rather than called synchronously,
            // since `handle` is main-actor-isolated and this closure isn't.
            Task { @MainActor in self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// Checks without prompting first (mirrors `isTrustedAccessibilityClient(false)`);
    /// only if that fails does it trigger the system's own "Zenith wants to
    /// control this computer" prompt, which also adds the app to System
    /// Settings > Privacy & Security > Accessibility (unchecked). Either
    /// way the feature just stays off until the user enables it there and
    /// relaunches — nothing else in the app depends on it working.
    private func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        // The literal, rather than the `kAXTrustedCheckOptionPrompt`
        // global — that constant is an `Unmanaged<CFString>!`, which
        // Swift 6's strict concurrency checking flags as non-Sendable
        // shared mutable state. Its value is a stable, documented
        // ApplicationServices constant ("AXTrustedCheckOptionPrompt").
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        NSLog(
            "[option-double-tap] Accessibility permission not granted — enable Zenith under "
                + "System Settings > Privacy & Security > Accessibility, then relaunch, to use it.")
        return false
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            optionHeldCleanly = false
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard Self.optionKeyCodes.contains(event.keyCode) else {
            // Some other modifier (Shift/Control/Command/Fn) transitioned
            // while this ran — same "interrupts a clean hold" rule as any
            // other key, mirrors uiohook seeing every keydown regardless
            // of which key it is.
            optionHeldCleanly = false
            return
        }

        if event.modifierFlags.contains(.option) {
            optionDownAt = Date()
            optionHeldCleanly = true
            return
        }

        // Option just went up.
        let wasClean = optionHeldCleanly
        optionHeldCleanly = false
        guard wasClean, let downAt = optionDownAt else { return }

        let now = Date()
        guard now.timeIntervalSince(downAt) <= Self.maxTapHold else {
            lastCleanTapAt = nil
            return
        }

        if let last = lastCleanTapAt, now.timeIntervalSince(last) <= Self.doubleTapWindow {
            lastCleanTapAt = nil // consume the pair so a third tap starts a fresh count
            onDoubleTap()
        } else {
            lastCleanTapAt = now
        }
    }

    private func onDoubleTap() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        shell.openAiModal()
    }
}
