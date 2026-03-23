// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DualAudioTranscriber",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "DualAudioTranscriber",
            path: "Sources/DualAudioTranscriber",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Speech"),
            ]
        ),
        .testTarget(
            name: "DualAudioTranscriberTests",
            dependencies: ["DualAudioTranscriber"],
            path: "Tests/DualAudioTranscriberTests"
        ),
    ]
)
