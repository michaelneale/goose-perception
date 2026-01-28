// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GoosePerception",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GoosePerception", targets: ["GoosePerception"]),
    ],
    dependencies: [
        // Database
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        // LLM Runtime - in-process, using proper Task.detached pattern
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        // WhisperKit for local speech recognition
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "GoosePerception",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "GoosePerception"
        ),
    ]
)
