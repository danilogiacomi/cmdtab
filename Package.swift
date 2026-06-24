// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CmdTab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CGSPrivate"),
        .target(name: "CmdTabCore"),
        .executableTarget(
            name: "CmdTabApp",
            dependencies: ["CmdTabCore", "CGSPrivate"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(name: "CmdTabCoreTests", dependencies: ["CmdTabCore"]),
    ]
)
