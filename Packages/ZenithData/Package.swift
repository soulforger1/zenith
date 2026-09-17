// swift-tools-version: 6.0
import PackageDescription

/// Native data + business-logic layer. Local-first: the single source of
/// truth is a local SQLite database (GRDB), created and migrated in-process
/// (`Database/Schema/Migrations.swift`). Optional sync to a remote Postgres
/// database or a synced folder lives in the separate `ZenithSync` package,
/// which keeps the PostgresNIO / SwiftNIO dependency graph out of here.
let package = Package(
    name: "ZenithData",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZenithData", targets: ["ZenithData"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "ZenithData",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "ZenithDataTests",
            dependencies: ["ZenithData"]
        ),
    ]
)
