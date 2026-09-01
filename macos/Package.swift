// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DriveBatteryHealthViewer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DriveBatteryHealthViewer", targets: ["DriveBatteryHealthViewer"]),
        .executable(name: "DriveBatteryChargeHelper", targets: ["DriveBatteryChargeHelper"]),
        .executable(name: "DriveBatteryChargeLimitAgent", targets: ["DriveBatteryChargeLimitAgent"])
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
        .target(
            name: "ChargeProtectionCore",
            path: "Sources/ChargeProtectionCore"
        ),
        .target(
            name: "CPowerUIBridge",
            path: "Sources/CPowerUIBridge",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("Foundation")]
        ),
        .executableTarget(
            name: "DriveBatteryHealthViewer",
            dependencies: ["CNVMeSMART", "ChargeProtectionCore"],
            path: "Sources/DriveBatteryHealthViewer"
        ),
        .executableTarget(
            name: "DriveBatteryChargeHelper",
            dependencies: ["ChargeProtectionCore", "CPowerUIBridge"],
            path: "Sources/DriveBatteryChargeHelper",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "DriveBatteryChargeLimitAgent",
            dependencies: ["ChargeProtectionCore"],
            path: "Sources/DriveBatteryChargeLimitAgent"
        ),
        .testTarget(
            name: "DriveBatteryHealthViewerTests",
            dependencies: ["DriveBatteryHealthViewer", "DriveBatteryChargeLimitAgent", "ChargeProtectionCore"],
            path: "Tests/DriveBatteryHealthViewerTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
