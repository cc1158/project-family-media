// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FamilyMediaCore",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FamilyMediaCore",
            targets: ["FamilyMediaCore"]
        )
    ],
    targets: [
        .target(
            name: "FamilyMediaCore",
            path: "Sources/FamilyMediaCore"
        ),
        .testTarget(
            name: "FamilyMediaCoreTests",
            dependencies: ["FamilyMediaCore"],
            path: "Tests/FamilyMediaCoreTests"
        )
    ]
)
