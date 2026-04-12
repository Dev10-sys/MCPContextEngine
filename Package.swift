// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCPContextEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MCPContextEngineCore",
            targets: ["MCPContextEngineCore"]
        ),
        .library(
            name: "MCPContextEngineMCP",
            targets: ["MCPContextEngineMCP"]
        ),
        .library(
            name: "MCPContextEngineFoundationModels",
            targets: ["MCPContextEngineFoundationModels"]
        ),
        .executable(
            name: "MCPContextEngineDemo",
            targets: ["MCPContextEngineDemo"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0")
    ],
    targets: [
        .target(
            name: "MCPContextEngineCore",
            dependencies: [],
            path: "Sources/MCPContextEngineCore"
        ),
        .target(
            name: "MCPContextEngineMCP",
            dependencies: [
                "MCPContextEngineCore",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/MCPContextEngineMCP"
        ),
        .target(
            name: "MCPContextEngineFoundationModels",
            dependencies: [
                "MCPContextEngineCore"
            ],
            path: "Sources/MCPContextEngineFoundationModels"
        ),
        .executableTarget(
            name: "MCPContextEngineDemo",
            dependencies: [
                "MCPContextEngineCore",
                "MCPContextEngineMCP",
                "MCPContextEngineFoundationModels"
            ],
            path: "Sources/MCPContextEngineDemo"
        ),
        .testTarget(
            name: "MCPContextEngineCoreTests",
            dependencies: ["MCPContextEngineCore"],
            path: "Tests/MCPContextEngineCoreTests"
        ),
        .testTarget(
            name: "MCPContextEngineMCPTests",
            dependencies: [
                "MCPContextEngineMCP",
                "MCPContextEngineCore"
            ],
            path: "Tests/MCPContextEngineMCPTests"
        ),
        .testTarget(
            name: "MCPContextEngineFoundationModelsTests",
            dependencies: [
                "MCPContextEngineFoundationModels",
                "MCPContextEngineCore"
            ],
            path: "Tests/MCPContextEngineFoundationModelsTests"
        ),
        .testTarget(
            name: "BenchmarkTests",
            dependencies: [
                "MCPContextEngineCore",
                "MCPContextEngineMCP"
            ],
            path: "Tests/BenchmarkTests"
        )
    ]
)
