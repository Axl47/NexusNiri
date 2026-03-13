// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Nexus",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "NexusApp", targets: ["NexusApp"]),
    ],
    targets: [
        .target(name: "SharedTypes"),
        .target(
            name: "WorkspaceEngine",
            dependencies: ["SharedTypes"]
        ),
        .target(
            name: "WindowRegistry",
            dependencies: ["SharedTypes"]
        ),
        .target(
            name: "LayoutEngine",
            dependencies: ["SharedTypes"]
        ),
        .target(
            name: "VisibilityEngine",
            dependencies: ["SharedTypes", "LayoutEngine"]
        ),
        .target(
            name: "AdapterBus",
            dependencies: ["SharedTypes"]
        ),
        .target(
            name: "Diagnostics",
            dependencies: ["SharedTypes"]
        ),
        .target(
            name: "GenericAXAdapter",
            dependencies: ["SharedTypes", "AdapterBus"]
        ),
        .target(
            name: "TetherAdapter",
            dependencies: ["SharedTypes", "AdapterBus"]
        ),
        .target(
            name: "StageChrome",
            dependencies: ["SharedTypes", "WorkspaceEngine", "LayoutEngine"]
        ),
        .executableTarget(
            name: "NexusApp",
            dependencies: [
                "SharedTypes",
                "WorkspaceEngine",
                "WindowRegistry",
                "LayoutEngine",
                "VisibilityEngine",
                "AdapterBus",
                "Diagnostics",
                "GenericAXAdapter",
                "TetherAdapter",
                "StageChrome",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SharedTypesTests",
            dependencies: ["SharedTypes"]
        ),
        .testTarget(
            name: "WorkspaceEngineTests",
            dependencies: ["WorkspaceEngine", "SharedTypes"]
        ),
        .testTarget(
            name: "LayoutEngineTests",
            dependencies: ["LayoutEngine", "SharedTypes"]
        ),
        .testTarget(
            name: "TetherAdapterTests",
            dependencies: ["TetherAdapter", "SharedTypes", "AdapterBus"]
        ),
        .testTarget(
            name: "StageChromeTests",
            dependencies: ["StageChrome"]
        ),
        .testTarget(
            name: "VisibilityEngineTests",
            dependencies: ["VisibilityEngine", "SharedTypes"]
        ),
        .testTarget(
            name: "DiagnosticsTests",
            dependencies: ["Diagnostics", "SharedTypes"]
        ),
        .testTarget(
            name: "WindowRegistryTests",
            dependencies: ["WindowRegistry", "SharedTypes"]
        ),
        .testTarget(
            name: "NexusAppTests",
            dependencies: ["NexusApp", "SharedTypes", "AdapterBus", "VisibilityEngine", "LayoutEngine", "WorkspaceEngine"]
        ),
    ]
)
