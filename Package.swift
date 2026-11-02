// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnTrans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EnTrans", targets: ["EnTrans"])
    ],
    targets: [
        .target(
            name: "EnTransCore",
            path: "Sources/EnTrans",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "EnTrans",
            dependencies: ["EnTransCore"],
            path: "Sources/EnTransApp"
        ),
        .executableTarget(
            name: "EnTransCheck",
            dependencies: ["EnTransCore"],
            path: "Sources/EnTransCheck"
        ),
    ]
)
