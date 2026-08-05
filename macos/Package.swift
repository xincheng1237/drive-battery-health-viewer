// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DriveBatteryHealthViewer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DriveBatteryHealthViewer", targets: ["DriveBatteryHealthViewer"])
    ],
    targets: [
        .target(
            name: "CNVMeSMART",
            path: "Sources/CNVMeSMART",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "DriveBatteryHealthViewer",
            dependencies: ["CNVMeSMART"],
            path: "Sources/DriveBatteryHealthViewer"
        ),
        .testTarget(
            name: "DriveBatteryHealthViewerTests",
            dependencies: ["DriveBatteryHealthViewer"],
            path: "Tests/DriveBatteryHealthViewerTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
