// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhostPin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GhostPin",
            path: "Sources/GhostPin",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
