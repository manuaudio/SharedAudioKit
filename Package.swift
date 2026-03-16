// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedAudioKit",
    platforms: [.macOS(.v14)],
    products: [
        // Foundational
        .library(name: "TimecodeKit", targets: ["TimecodeKit"]),
        .library(name: "RealTimeKit", targets: ["RealTimeKit"]),
        .library(name: "CoreMIDIKit", targets: ["CoreMIDIKit"]),
        .library(name: "AudioDeviceKit", targets: ["AudioDeviceKit"]),
        // Higher-level (depend on foundational)
        .library(name: "LTCKit", targets: ["LTCKit"]),
        .library(name: "MTCKit", targets: ["MTCKit"]),
        .library(name: "TriggerKit", targets: ["TriggerKit"]),
        .library(name: "MeterKit", targets: ["MeterKit"]),
    ],
    targets: [
        // MARK: - Foundational targets
        .target(name: "TimecodeKit"),
        .target(name: "RealTimeKit"),
        .target(name: "CoreMIDIKit"),
        .target(name: "AudioDeviceKit"),

        // MARK: - Higher-level targets
        .target(name: "LTCKit", dependencies: ["TimecodeKit"]),
        .target(name: "MTCKit", dependencies: ["TimecodeKit"]),
        .target(name: "TriggerKit", dependencies: ["TimecodeKit"]),
        .target(
            name: "MeterKit",
            dependencies: ["RealTimeKit"],
            resources: [.process("Resources")]
        ),

        // MARK: - Tests
        .testTarget(name: "TimecodeKitTests", dependencies: ["TimecodeKit"]),
        .testTarget(name: "RealTimeKitTests", dependencies: ["RealTimeKit"]),
        .testTarget(name: "CoreMIDIKitTests", dependencies: ["CoreMIDIKit"]),
        .testTarget(name: "AudioDeviceKitTests", dependencies: ["AudioDeviceKit"]),
        .testTarget(name: "LTCKitTests", dependencies: ["LTCKit"]),
        .testTarget(name: "MTCKitTests", dependencies: ["MTCKit"]),
        .testTarget(name: "TriggerKitTests", dependencies: ["TriggerKit"]),
        .testTarget(name: "MeterKitTests", dependencies: ["MeterKit"]),
    ]
)
