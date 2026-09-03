// swift-tools-version: 6.0
import PackageDescription

/// Native data + business-logic layer — replaces `lib/db/` and
/// `lib/actions/` (Drizzle + zod-validated Server Actions). See
/// docs/native-rewrite-audit.md §6 for the PostgresNIO decision.
let package = Package(
    name: "ZenithData",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZenithData", targets: ["ZenithData"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0")
    ],
    targets: [
        .target(
            name: "ZenithData",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio")
            ]
        ),
        .testTarget(
            name: "ZenithDataTests",
            dependencies: ["ZenithData"]
        ),
    ]
)
