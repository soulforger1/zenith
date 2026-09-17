// swift-tools-version: 6.0
import PackageDescription

/// Sync layer — everything that talks to a *remote* store. Keeps the
/// PostgresNIO / SwiftNIO dependency graph out of `ZenithData` (the
/// local-first core), so the core data layer builds and tests with no
/// external services.
///
/// Phase 1 uses only `Import/PostgresImporter` (one-time copy of an
/// existing Postgres database into the fresh local SQLite store). The
/// bidirectional sync engine + targets land in later phases.
let package = Package(
    name: "ZenithSync",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZenithSync", targets: ["ZenithSync"])
    ],
    dependencies: [
        .package(path: "../ZenithData"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .target(
            name: "ZenithSync",
            dependencies: [
                "ZenithData",
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
        .testTarget(
            name: "ZenithSyncTests",
            dependencies: ["ZenithSync"]
        ),
    ]
)
