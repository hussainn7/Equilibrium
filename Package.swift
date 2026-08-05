// swift-tools-version:5.9
// Dev-only manifest: compiles the platform-neutral Core layer on macOS
// and runs the Self-Test-Runner. The iOS app is built via project.yml
// (xcodegen) and directly includes the same Core sources.
import PackageDescription

let package = Package(
    name: "PulseCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    targets: [
        .target(
            name: "PulseCore",
            path: "Core"
        ),
        .executableTarget(
            name: "pulse-selftest",
            dependencies: ["PulseCore"],
            path: "SelfTest"
        ),
    ]
)
