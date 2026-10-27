// swift-tools-version:5.9
import PackageDescription

// CleanStartCore holds every piece of CleanStart logic that does not depend on
// Apple-only frameworks (NetworkExtension, FamilyControls, ManagedSettings,
// DeviceActivity, SwiftUI). Keeping it platform-independent lets the logic be
// compiled and unit-tested on macOS *and* Linux.
let package = Package(
    name: "CleanStartCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "CleanStartCore", targets: ["CleanStartCore"]),
    ],
    targets: [
        .target(name: "CleanStartCore"),
        .testTarget(name: "CleanStartCoreTests", dependencies: ["CleanStartCore"]),
    ]
)
