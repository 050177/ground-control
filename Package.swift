// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GroundControl",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Terminal emulator (no tagged releases — pinned by Package.resolved)
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", branch: "main"),
        // Official MCP Swift SDK
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "GCCore",
            path: "Sources/GCCore"
        ),
        .executableTarget(
            name: "GroundControl",
            dependencies: [
                "GCCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/GroundControl"
        ),
        .executableTarget(
            name: "gc-mcp",
            dependencies: [
                "GCCore",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/gc-mcp"
        ),
    ]
)
