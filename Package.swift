// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Task",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Task", targets: ["Task"])
    ],
    targets: [
        .executableTarget(
            name: "Task",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
