// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FamilyMediaClient",
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
            path: "Shared/FamilyMediaCore/Sources/FamilyMediaCore"
        ),
        .testTarget(
            name: "FamilyMediaCoreTests",
            dependencies: ["FamilyMediaCore"],
            path: "Shared/FamilyMediaCore/Tests/FamilyMediaCoreTests"
        )
    ]
)
