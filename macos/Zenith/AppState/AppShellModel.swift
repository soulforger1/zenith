import Foundation
import Observation

/// Identifies the task the detail inspector shows — a bare issue id isn't
/// enough (unlike the web build's `DrawerContext`, which bundled the
/// task's whole space context alongside it), since the inspector needs to
/// know which cached `SpaceDetailModel` to read/write through.
public struct TaskDetailTarget: Equatable, Sendable {
    public let spaceId: UUID
    public let issueId: UUID
}

/// Replaces `AppShellContext` (`components/layout/app-shell-context.tsx`) —
/// cross-cutting shell UI state (task drawer, AI paste-task modal, command
/// palette) that deeply-nested views need to reach without prop-drilling.
/// Injected via `.environment()`; consumers read it with `@Environment`
/// instead of React's `useAppShell()`.
@Observable
@MainActor
public final class AppShellModel {
    public var taskDetailTarget: TaskDetailTarget?
    public var isAiModalPresented: Bool = false
    public var isCommandPalettePresented: Bool = false
    public var isShortcutsDialogPresented: Bool = false
    /// Which content the detail pane shows — see `ShellRoute`. Lives here
    /// (not a separate model) since it's exactly the kind of cross-cutting
    /// shell state `AppShellContext` used to own on the web side.
    var route: ShellRoute = .dashboard

    public init() {}

    public func openTask(spaceId: UUID, issueId: UUID) {
        taskDetailTarget = TaskDetailTarget(spaceId: spaceId, issueId: issueId)
    }

    public func closeTask() {
        taskDetailTarget = nil
    }

    public func openAiModal() {
        isAiModalPresented = true
    }

    public func openCommandPalette() {
        isCommandPalettePresented = true
    }

    /// Mirrors the Electron build's `Escape` shortcut: close every
    /// shell-level overlay at once.
    public func closeAll() {
        taskDetailTarget = nil
        isAiModalPresented = false
        isCommandPalettePresented = false
        isShortcutsDialogPresented = false
    }
}
