// swift-tools-version: 6.0
import PackageDescription

/// Native AI + GitHub integration layer — replaces `lib/ai/claude.ts`,
/// `lib/ai/prompts.ts`, `lib/ai/field-resolver.ts`, `lib/github/client.ts`,
/// and `lib/name-match.ts`. See docs/native-rewrite-audit.md §4 and §6 for
/// the CLI-spawn contract this must replicate.
let package = Package(
    name: "ZenithAI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZenithAI", targets: ["ZenithAI"])
    ],
    dependencies: [
        .package(path: "../ZenithData")
    ],
    targets: [
        .target(
            name: "ZenithAI",
            dependencies: ["ZenithData"]
        ),
        .testTarget(
            name: "ZenithAITests",
            dependencies: ["ZenithAI"]
        ),
    ]
)
