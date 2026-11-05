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
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
        ),
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
            dependencies: ["CNVMeSMART", "ChargeProtectionCore", "Sparkle"],
            path: "Sources/DriveBatteryHealthViewer",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
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
