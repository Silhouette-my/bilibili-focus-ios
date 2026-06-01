// swift-tools-version: 6.0
import Foundation
import PackageDescription

var targets: [Target] = [
    .target(
        name: "FocusCore",
        resources: [
            .process("Resources"),
        ]
    ),
    .executableTarget(
        name: "FocusVerifier",
        dependencies: ["FocusCore"]
    ),
]

if ProcessInfo.processInfo.environment["FOCUS_INCLUDE_TESTS"] == "1" {
    targets.append(
        .testTarget(
            name: "FocusCoreTests",
            dependencies: ["FocusCore"],
            resources: [
                .process("Fixtures"),
            ]
        )
    )
}

let package = Package(
    name: "BilibiliFocus",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "FocusCore",
            targets: ["FocusCore"]
        ),
        .executable(
            name: "FocusVerifier",
            targets: ["FocusVerifier"]
        ),
    ],
    targets: targets
)
