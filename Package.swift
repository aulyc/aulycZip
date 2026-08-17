// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "aulycZip",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ZipCore", targets: ["ZipCore"]),
        .executable(name: "aulycZip", targets: ["aulycZip"]),
    ],
    targets: [
        .target(
            name: "ZipCore",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "aulycZipAppSupport",
            dependencies: ["ZipCore"],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "aulycZip",
            dependencies: ["ZipCore", "aulycZipAppSupport"],
            resources: [
                .copy("Resources/MenuBarIcon.svg"),
            ]
        ),
        .testTarget(
            name: "ZipCoreTests",
            dependencies: ["ZipCore"]
        ),
        .testTarget(
            name: "aulycZipAppSupportTests",
            dependencies: ["aulycZipAppSupport", "ZipCore"]
        ),
    ]
)
