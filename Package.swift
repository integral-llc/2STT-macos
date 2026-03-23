// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DualSTT",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DualSTT", targets: ["DualSTT"])
    ],
    targets: [
        .target(
            name: "DualSTT",
            path: "Sources/DualSTT",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Speech")
            ]
        ),
        .executableTarget(
            name: "DualSTTApp",
            dependencies: ["DualSTT"],
            path: "Sources/DualSTTApp"
        ),
        .testTarget(
            name: "DualSTTTests",
            dependencies: ["DualSTT"],
            path: "Tests/DualSTTTests"
        )
    ]
)
