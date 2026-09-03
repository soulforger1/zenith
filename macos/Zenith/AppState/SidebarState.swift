import SwiftUI

/// Replaces the one `localStorage` key the web app used
/// (`zenith:sidebar-collapsed`, `components/layout/app-sidebar.tsx`) —
/// `@AppStorage` is `UserDefaults`-backed, the direct native equivalent.
/// A thin property-wrapper alias so call sites read the same everywhere
/// rather than repeating the raw key string.
@propertyWrapper
public struct SidebarCollapsedStorage: DynamicProperty {
    @AppStorage("zenith.sidebarCollapsed") private var value: Bool = false

    public init() {}

    public var wrappedValue: Bool {
        get { value }
        nonmutating set { value = newValue }
    }

    public var projectedValue: Binding<Bool> {
        Binding(get: { value }, set: { value = $0 })
    }
}
