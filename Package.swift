// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftDictation",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "SwiftDictation",
            targets: ["SwiftDictation"]
        ),
    ],
    dependencies: [
        // WebRTC dependencies would go here if using RNNoise/VAD
        // For now, we'll use AVAudioUnit-based solutions
    ],
    targets: [
        .target(
            name: "SwiftDictation",
            dependencies: [],
            path: "Sources/SwiftDictation"
        ),
        .testTarget(
            name: "SwiftDictationTests",
            dependencies: ["SwiftDictation"],
            path: "Tests/SwiftDictationTests"
        ),
    ]
)

