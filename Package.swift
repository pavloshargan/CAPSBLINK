// swift-tools-version: 5.10
import PackageDescription

// NOTE: the `llama` binary target points at Vendor/llama.xcframework, which is
// not checked into git. Run `make deps` (or scripts/fetch-llama.sh) once before
// building — it downloads a pinned, checksum-verified prebuilt llama.cpp
// xcframework from the official llama.cpp GitHub releases.
let package = Package(
    name: "CapsBlink",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Reusable core: polling, extraction, change detection, LED notification.
        // Depend on this from other tools if you want the machinery without the app.
        .library(name: "CapsBlinkKit", targets: ["CapsBlinkKit"]),
        // Local LLM classification built on llama.cpp.
        .library(name: "CapsBlinkLlama", targets: ["CapsBlinkLlama"]),
        // Local coding-agent (Claude Code / Codex CLI) activity monitoring.
        .library(name: "CapsBlinkAgentKit", targets: ["CapsBlinkAgentKit"]),
        // Menu bar app #1: watches a webpage, LLM decides when to blink.
        .executable(name: "CapsBlink", targets: ["CapsBlink"]),
        // Menu bar app #2: watches local coding agents, blinks when they finish.
        .executable(name: "CapsBlinkAgents", targets: ["CapsBlinkAgents"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            path: "Vendor/llama.xcframework"
        ),
        .target(
            name: "CapsBlinkKit"
        ),
        .target(
            name: "CapsBlinkLlama",
            dependencies: ["CapsBlinkKit", "llama"]
        ),
        .target(
            name: "CapsBlinkAgentKit",
            dependencies: ["CapsBlinkKit"]
        ),
        .executableTarget(
            name: "CapsBlink",
            dependencies: ["CapsBlinkKit", "CapsBlinkLlama"]
        ),
        .executableTarget(
            name: "CapsBlinkAgents",
            dependencies: ["CapsBlinkKit", "CapsBlinkAgentKit"]
        ),
        .testTarget(
            name: "CapsBlinkKitTests",
            dependencies: ["CapsBlinkKit"]
        ),
        .testTarget(
            name: "CapsBlinkLlamaTests",
            dependencies: ["CapsBlinkLlama"]
        ),
        .testTarget(
            name: "CapsBlinkAgentKitTests",
            dependencies: ["CapsBlinkAgentKit"]
        ),
    ]
)
