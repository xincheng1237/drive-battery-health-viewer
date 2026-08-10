import AppKit
import CNVMeSMART
import Foundation
import Testing
@testable import DriveBatteryHealthViewer

@Suite("Drive & Battery Health Viewer core")
struct CoreTests {
    @Test
    func testHealthStateThresholdsAndSMARTStatus() {
        #expect(healthState(forPercent: 100) == .good)
        #expect(healthState(forPercent: 80) == .good)
        #expect(healthState(forPercent: 79.9) == .warning)
        #expect(healthState(forPercent: 59.9) == .warning)
        #expect(healthState(forPercent: nil) == .unknown)
        #expect(healthState(forSMARTStatus: "Verified") == .good)
        #expect(healthState(forSMARTStatus: "Failing") == .critical)
        #expect(healthState(forSMARTStatus: "Not OK") == .critical)
        #expect(healthState(forSMARTStatus: "Not Verified") == .critical)
        #expect(healthState(forSMARTStatus: "Not Supported") == .unknown)
        #expect(healthState(forSMARTStatus: "Unknown") == .unknown)
    }

    @Test
    func testReportRedactsSerialNumbers() {
        let snapshot = sampleSnapshot()
        let visible = ReportRenderer.render(snapshot: snapshot, language: .english, hideSerials: false)
        let hidden = ReportRenderer.render(snapshot: snapshot, language: .english, hideSerials: true)
        #expect(visible.contains("DRIVE-SERIAL"))
        #expect(visible.contains("BATTERY-SERIAL"))
        #expect(!hidden.contains("DRIVE-SERIAL"))
        #expect(!hidden.contains("BATTERY-SERIAL"))
        #expect(hidden.contains("••••••••"))
    }

    @Test
    func testHistoryRoundTripAndDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(directory: root)
        let record = try store.save(snapshot: sampleSnapshot(), source: .refresh, hideSerials: true)
        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == record.id)
        #expect(loaded.first?.snapshot.drives.first?.serialNumber == "••••••••")
        try store.delete(record)
        #expect(try store.load().isEmpty)
    }

    @Test
    func testDiskAndBatteryPropertyListsAreParsed() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk0", "Size": 1_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk0", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "APPLE SSD", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "PCI-Express", "SMARTStatus": "Verified", "SolidState": true, "Internal": true
        ])
        let battery = plist([[
            "DeviceName": "Mac Battery", "BatterySerialNumber": "BAT-1",
            "DesignCapacity": 5000, "AppleRawMaxCapacity": 4500, "CurrentCapacity": 77,
            "CycleCount": 234, "IsCharging": false, "ExternalConnected": true,
            "Voltage": 12_000,
            "BatteryData": [
                "Chemistry": "Li-ion",
                "MfgData": Data([0, 0, 4, 49, 57, 49, 52, 3, 65, 84, 76, 0])
            ]
        ]])
        let power = json([
            "SPPowerDataType": [["sppower_battery_health_info": ["sppower_battery_health_maximum_capacity": "80%"]]]
        ])
        let storageProfile = json([
            "SPNVMeDataType": [[
                "_name": "Apple SSD Controller",
                "_items": [[
                    "_name": "APPLE SSD",
                    "device_model": "APPLE SSD",
                    "device_revision": "561.100.",
                    "device_serial": "SSD-1"
                ]]
            ]]
        ])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk0"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", ["SPNVMeDataType", "SPSerialATADataType", "SPUSBDataType", "SPThunderboltDataType", "SPStorageDataType", "-json", "-detailLevel", "full"]): .success(storageProfile),
            FixtureRunner.key("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery", "-a"]): .success(battery),
            FixtureRunner.key("/usr/sbin/system_profiler", ["SPPowerDataType", "-json", "-detailLevel", "full"]): .success(power)
        ])
        let scanner = HardwareScanner(runner: runner)
        let drives = try scanner.scanDrives()
        let batteries = try scanner.scanBatteries()
        #expect(drives.first?.model == "APPLE SSD")
        #expect(drives.first?.healthState == .good)
        #expect(drives.first?.capacityBytes == 1_000_000_000_000)
        #expect(drives.first?.serialNumber == "SSD-1")
        #expect(drives.first?.firmware == "561.100.")
        #expect(batteries.first?.healthPercent == 80)
        #expect(batteries.first?.capacityRatioPercent == 90)
        #expect(batteries.first?.manufacturer == "ATL")
        #expect(batteries.first?.chemistry == "Li-ion")
        #expect(batteries.first?.cycleCount == 234)
        let capacity = formattedBatteryCapacity(5000, voltageMillivolts: 12_000, language: .english)
        #expect(capacity == "5,000 mAh / 60.00 Wh")
        #expect(!capacity.contains("·"))
        #expect(!capacity.contains("≈"))
    }

    @Test
    func testExternalUSBMetadataIsMatchedFromSystemProfiler() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk2", "Size": 2_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk2", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "Portable SSD", "TotalSize": 2_000_000_000_000 as UInt64,
            "BusProtocol": "USB", "SolidState": true, "Internal": false
        ])
        let profile = json([
            "SPUSBDataType": [[
                "_name": "USB 3.1 Bus",
                "_items": [[
                    "_name": "Portable SSD",
                    "bsd_name": "disk2",
                    "serial_num": "EXT-SSD-123",
                    "Product Revision Level": "2.10"
                ]]
            ]]
        ])
        let profilerArguments = [
            "SPNVMeDataType", "SPSerialATADataType", "SPUSBDataType",
            "SPThunderboltDataType", "SPStorageDataType", "-json", "-detailLevel", "full"
        ]
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk2"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", profilerArguments): .success(profile)
        ])

        let drive = try #require(HardwareScanner(runner: runner, smartctlPaths: []).scanDrives().first)
        #expect(drive.deviceIdentifier == "disk2")
        #expect(drive.protocolName == "USB")
        #expect(drive.isInternal == false)
        #expect(drive.serialNumber == "EXT-SSD-123")
        #expect(drive.firmware == "2.10")
    }

    @Test
    func testExternalSATSMARTAttributesAreParsedWithoutUnitEstimates() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk3", "Size": 1_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk3", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "SAT SSD", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "USB", "SolidState": true, "Internal": false
        ])
        let profilerArguments = [
            "SPNVMeDataType", "SPSerialATADataType", "SPUSBDataType",
            "SPThunderboltDataType", "SPStorageDataType", "-json", "-detailLevel", "full"
        ]
        let smart = json([
            "model_name": "SAT SSD Detailed",
            "serial_number": "SAT-456",
            "firmware_version": "FW12",
            "smart_status": ["passed": true],
            "ata_smart_attributes": ["table": [
                ["name": "Power_On_Hours", "value": 99, "raw": ["value": 4321]],
                ["name": "Power_Cycle_Count", "value": 99, "raw": ["value": 321]],
                ["name": "Temperature_Celsius", "value": 68, "raw": ["value": 34]],
                ["name": "Unsafe_Shutdown_Count", "value": 100, "raw": ["value": 7]],
                ["name": "Percent_Lifetime_Remain", "value": 91, "raw": ["value": 91]]
            ]]
        ])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk3"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", profilerArguments): .success(json([:])),
            FixtureRunner.key("/usr/bin/true", ["--version"]): .success(Data()),
            FixtureRunner.key("/usr/bin/true", ["-a", "-j", "/dev/disk3"]): .success(smart)
        ])

        let drive = try #require(HardwareScanner(runner: runner, smartctlPaths: ["/usr/bin/true"]).scanDrives().first)
        #expect(drive.model == "SAT SSD Detailed")
        #expect(drive.serialNumber == "SAT-456")
        #expect(drive.firmware == "FW12")
        #expect(drive.healthState == .good)
        #expect(drive.powerOnHours == 4321)
        #expect(drive.powerCycles == 321)
        #expect(drive.temperatureCelsius == 34)
        #expect(drive.unsafeShutdowns == 7)
        #expect(drive.lifeRemainingPercent == 91)
        #expect(drive.bytesRead == nil)
        #expect(drive.bytesWritten == nil)
    }

    @Test
    func testSmartctlNormalizedFieldsWinOverVendorRawAttributes() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk3", "Size": 1_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk3", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "SAT SSD", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "USB", "SolidState": true, "Internal": false
        ])
        let smart = json([
            "model_name": "SAT SSD",
            "serial_number": "SAT-NORMALIZED",
            "firmware_version": "FW1",
            "smart_status": ["passed": true],
            "temperature": ["current": 39],
            "power_on_time": ["hours": 120],
            "power_cycle_count": 44,
            "ata_smart_attributes": ["table": [
                ["name": "Power_On_Hours", "value": 99, "raw": ["value": 9_999]],
                ["name": "Power_Cycle_Count", "value": 99, "raw": ["value": 8_888]],
                ["name": "Temperature_Celsius", "value": 68, "raw": ["value": 77]],
                ["name": "Percent_Lifetime_Remain", "value": 5, "raw": ["value": 5]]
            ]]
        ])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk3"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", storageProfilerTestArguments): .success(json([:])),
            FixtureRunner.key("/usr/bin/true", ["--version"]): .success(Data()),
            FixtureRunner.key("/usr/bin/true", ["-a", "-j", "/dev/disk3"]): .success(smart)
        ])

        let drive = try #require(HardwareScanner(runner: runner, smartctlPaths: ["/usr/bin/true"]).scanDrives().first)
        #expect(drive.powerOnHours == 120)
        #expect(drive.powerCycles == 44)
        #expect(drive.temperatureCelsius == 39)
        #expect(drive.lifeRemainingPercent == 5)
        #expect(drive.healthState == .critical)
    }

    @Test
    func testSmartctlUsesOnlyDarwinSupportedAutomaticMode() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk4", "Size": 2_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk4", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "Bridge SSD", "TotalSize": 2_000_000_000_000 as UInt64,
            "BusProtocol": "USB", "SolidState": true, "Internal": false
        ])
        let smart = json([
            "model_name": "Bridge SSD Detailed", "serial_number": "BRIDGE-4",
            "firmware_version": "3.0", "smart_status": ["passed": true],
            "temperature": ["current": 32]
        ])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk4"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", storageProfilerTestArguments): .success(json([:])),
            FixtureRunner.key("/usr/bin/true", ["--version"]): .success(Data()),
            FixtureRunner.key("/usr/bin/true", ["-a", "-j", "/dev/disk4"]): .success(smart)
        ])

        let drive = try #require(HardwareScanner(runner: runner, smartctlPaths: ["/usr/bin/true"]).scanDrives().first)
        #expect(drive.model == "Bridge SSD Detailed")
        #expect(drive.serialNumber == "BRIDGE-4")
        #expect(drive.temperatureCelsius == 32)
    }

    @Test
    func testSmartctlNeverUsesUnsafeGuessedBridgeType() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk5", "Size": 1_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk5", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "Unknown Bridge", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "USB", "SolidState": true, "Internal": false
        ])
        let scan = json(["devices": [["name": "/dev/disk5", "type": "jmb39x", "protocol": "ATA"]]])
        let unsafePayload = json([
            "model_name": "SHOULD NOT BE USED", "serial_number": "UNSAFE",
            "smart_status": ["passed": true]
        ])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk5"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", storageProfilerTestArguments): .success(json([:])),
            FixtureRunner.key("/usr/bin/true", ["--version"]): .success(Data()),
            FixtureRunner.key("/usr/bin/true", ["--scan-open", "-j"]): .success(scan),
            FixtureRunner.key("/usr/bin/true", ["-a", "-j", "-d", "jmb39x", "/dev/disk5"]): .success(unsafePayload)
        ])

        let drive = try #require(HardwareScanner(runner: runner, smartctlPaths: ["/usr/bin/true"]).scanDrives().first)
        #expect(drive.model == "Unknown Bridge")
        #expect(drive.serialNumber == nil)
        #expect(drive.healthState == .unknown)
    }

    @Test
    func testIdenticalExternalModelsDoNotShareWeakProfileIdentity() throws {
        let list = plist(["AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk2", "Size": 1_000_000_000_000 as UInt64],
            ["DeviceIdentifier": "disk3", "Size": 1_000_000_000_000 as UInt64]
        ]])
        let info2 = plist([
            "DeviceIdentifier": "disk2", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "Same Portable SSD", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "USB", "SolidState": true, "Internal": false
        ])
        let info3 = plist([
            "DeviceIdentifier": "disk3", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "Same Portable SSD", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "USB", "SolidState": true, "Internal": false
        ])
        let profile = json(["SPUSBDataType": [[
            "_name": "Same Portable SSD", "serial_num": "MUST-NOT-BE-SHARED"
        ]]])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk2"]): .success(info2),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk3"]): .success(info3),
            FixtureRunner.key("/usr/sbin/system_profiler", storageProfilerTestArguments): .success(profile)
        ])

        let drives = try HardwareScanner(runner: runner, smartctlPaths: []).scanDrives()
        #expect(drives.count == 2)
        #expect(drives.allSatisfy { $0.serialNumber == nil })
    }

    @Test
    func testPartitionBSDNameSafelyMatchesWholeExternalDisk() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk2", "Size": 1_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk2", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "Partition Named SSD", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "USB", "SolidState": true, "Internal": false
        ])
        let profile = json(["SPUSBDataType": [[
            "_name": "Partition Named SSD", "bsd_name": "disk2s1", "serial_num": "PARTITION-2"
        ]]])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk2"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", storageProfilerTestArguments): .success(profile)
        ])

        let drive = try #require(HardwareScanner(runner: runner, smartctlPaths: []).scanDrives().first)
        #expect(drive.serialNumber == "PARTITION-2")
    }

    @Test
    func testStorageVolumeNameDoesNotReplacePhysicalDriveModel() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk2", "Size": 1_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk2", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "Samsung T7", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "USB", "SolidState": true, "Internal": false
        ])
        let profile = json(["SPStorageDataType": [[
            "_name": "Backup", "bsd_name": "disk2s1",
            "physical_drive": ["device_name": "Samsung T7", "device_serial": "T7-2"]
        ]]])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk2"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", storageProfilerTestArguments): .success(profile)
        ])

        let drive = try #require(HardwareScanner(runner: runner, smartctlPaths: []).scanDrives().first)
        #expect(drive.model == "Samsung T7")
        #expect(drive.model != "Backup")
        #expect(drive.serialNumber == "T7-2")
    }

    @Test
    func testNativeNVMeReaderRemainsAvailableAcrossRepeatedReadsWhenAvailable() {
        guard let first = nativeNVMeSMART(for: "disk0") else { return }
        #expect(first.percentageUsed <= 100)
        #expect(first.temperatureCelsius.map { (-30...150).contains($0) } ?? true)
        for _ in 0..<20 {
            let repeated = nativeNVMeSMART(for: "disk0")
            #expect(repeated != nil)
            #expect((repeated?.percentageUsed ?? 101) <= 100)
        }
        DBHVResetNVMeSMARTInterfaces()
        let afterReset = nativeNVMeSMART(for: "disk0")
        #expect(afterReset != nil)
        #expect((afterReset?.percentageUsed ?? 101) <= 100)
    }

    @Test
    func testLastSuccessfulHardwareValuesSurviveTransientRefreshFailure() {
        let previous = sampleSnapshot()
        var fresh = previous
        fresh.generatedAt = previous.generatedAt.addingTimeInterval(60)
        fresh.drives[0].serialNumber = nil
        fresh.drives[0].firmware = nil
        fresh.drives[0].temperatureCelsius = nil
        fresh.drives[0].bytesRead = nil
        fresh.drives[0].bytesWritten = nil
        fresh.batteries[0].manufacturer = nil
        fresh.batteries[0].serialNumber = nil
        fresh.batteries[0].chemistry = nil
        fresh.batteries[0].temperatureCelsius = nil

        let merged = fresh.preservingUnavailableValues(from: previous)
        #expect(merged.generatedAt == fresh.generatedAt)
        #expect(merged.drives[0].serialNumber == "DRIVE-SERIAL")
        #expect(merged.drives[0].firmware == "1.0")
        #expect(merged.drives[0].temperatureCelsius == 35)
        #expect(merged.drives[0].bytesRead == 2_000_000_000)
        #expect(merged.drives[0].bytesWritten == 3_000_000_000)
        #expect(merged.batteries[0].manufacturer == "Apple")
        #expect(merged.batteries[0].serialNumber == "BATTERY-SERIAL")
        #expect(merged.batteries[0].chemistry == "Li-ion")
        #expect(merged.batteries[0].temperatureCelsius == 31)
    }

    @Test
    func testHotPluggedDriveReusingBSDNameDoesNotInheritPreviousDeviceData() {
        var previous = sampleSnapshot()
        previous.drives = [DriveInfo(
            deviceIdentifier: "disk2", model: "Portable SSD", serialNumber: "OLD-SERIAL", firmware: "OLD-FW",
            protocolName: "USB", capacityBytes: 1_000_000_000_000, smartStatus: "Verified", healthState: .good,
            lifeRemainingPercent: 91, temperatureCelsius: 33, powerOnHours: 4_000, powerCycles: 800,
            bytesRead: 8_000, bytesWritten: 9_000, unsafeShutdowns: 4, mediaErrors: 0,
            isSolidState: true, isInternal: false, notes: []
        )]
        var fresh = previous
        fresh.generatedAt = previous.generatedAt.addingTimeInterval(60)
        fresh.drives = [DriveInfo(
            deviceIdentifier: "disk2", model: "Portable SSD", serialNumber: "NEW-SERIAL", firmware: nil,
            protocolName: "USB", capacityBytes: 1_000_000_000_000, smartStatus: nil, healthState: .unknown,
            lifeRemainingPercent: nil, temperatureCelsius: nil, powerOnHours: nil, powerCycles: nil,
            bytesRead: nil, bytesWritten: nil, unsafeShutdowns: nil, mediaErrors: nil,
            isSolidState: true, isInternal: false, notes: []
        )]

        let merged = fresh.preservingUnavailableValues(from: previous)
        #expect(merged.drives[0].serialNumber == "NEW-SERIAL")
        #expect(merged.drives[0].firmware == nil)
        #expect(merged.drives[0].powerOnHours == nil)
        #expect(merged.drives[0].healthState == .unknown)
    }

    @Test
    func testExternalDriveWithoutFreshSerialDoesNotInheritOldTelemetry() {
        var previous = sampleSnapshot()
        previous.drives[0].isInternal = false
        previous.drives[0].protocolName = "USB"
        var fresh = previous
        fresh.drives[0].serialNumber = nil
        fresh.drives[0].firmware = nil
        fresh.drives[0].powerOnHours = nil
        fresh.drives[0].temperatureCelsius = nil

        let merged = fresh.preservingUnavailableValues(from: previous)
        #expect(merged.drives[0].serialNumber == nil)
        #expect(merged.drives[0].firmware == nil)
        #expect(merged.drives[0].powerOnHours == nil)
        #expect(merged.drives[0].temperatureCelsius == nil)
    }

    @Test
    func testMatchingInternalSerialSurvivesRefinedModelLabel() {
        let previous = sampleSnapshot()
        var fresh = previous
        fresh.drives[0].model = "Test SSD Detailed Model"
        fresh.drives[0].firmware = nil
        let merged = fresh.preservingUnavailableValues(from: previous)
        #expect(merged.drives[0].model == "Test SSD Detailed Model")
        #expect(merged.drives[0].firmware == "1.0")
    }

    @Test
    func testFailedDriveRootScanKeepsPreviousConnectedDrives() {
        let previous = sampleSnapshot()
        let failed = HealthSnapshot(
            generatedAt: previous.generatedAt.addingTimeInterval(60),
            computerName: previous.computerName,
            drives: [],
            batteries: previous.batteries,
            warnings: ["Drive information: diskutil timed out"]
        )
        let merged = failed.preservingUnavailableValues(from: previous)
        #expect(merged.drives == previous.drives)
        #expect(merged.generatedAt == failed.generatedAt)
        #expect(merged.warnings == failed.warnings)
    }

    @Test
    func testPerDiskFailureAndMalformedRootAreReportedAsDomainFailures() {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk2", "Size": 1_000_000_000_000 as UInt64]]
        ])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk2"]): CommandOutput(
                data: Data(), errorText: "Command timed out", status: 124
            )
        ])
        let failed = HardwareScanner(runner: runner, smartctlPaths: []).scanSynchronously()
        #expect(failed.drives.isEmpty)
        #expect(failed.warnings.contains { $0.hasPrefix("Drive information:") })
        #expect(failed.preservingUnavailableValues(from: sampleSnapshot()).drives == sampleSnapshot().drives)

        let malformedRunner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(plist(["Unexpected": []]))
        ])
        let malformed = HardwareScanner(runner: malformedRunner, smartctlPaths: []).scanSynchronously()
        #expect(malformed.drives.isEmpty)
        #expect(malformed.warnings.contains { $0.hasPrefix("Drive information:") })
    }

    @Test
    func testNewUnsupportedSMARTStatusDoesNotKeepStaleGoodBadge() {
        let previous = sampleSnapshot()
        var fresh = previous
        fresh.drives[0].smartStatus = "Not Supported"
        fresh.drives[0].healthState = .unknown
        let merged = fresh.preservingUnavailableValues(from: previous)
        #expect(merged.drives[0].smartStatus == "Not Supported")
        #expect(merged.drives[0].healthState == .unknown)
    }

    @Test
    func testOnlyNativeNVMeTransportsArePolledLive() {
        let nvme = sampleSnapshot().drives[0]
        var usb = nvme
        usb.protocolName = "USB"
        usb.isInternal = false
        var thunderbolt = usb
        thunderbolt.protocolName = "Thunderbolt"
        #expect(nvme.supportsNativeNVMeLiveReading)
        #expect(!usb.supportsNativeNVMeLiveReading)
        #expect(thunderbolt.supportsNativeNVMeLiveReading)
    }

    @Test
    func testSystemCommandRunnerDrainsBothPipesAndTimesOut() throws {
        let runner = SystemCommandRunner(timeout: 3)
        let script = "dd if=/dev/zero bs=1024 count=256 2>/dev/null; dd if=/dev/zero bs=1024 count=256 1>&2 2>/dev/null"
        let output = try runner.run("/bin/sh", arguments: ["-c", script])
        #expect(output.status == 0)
        #expect(output.data.count == 256 * 1024)
        #expect(output.errorText.utf8.count == 256 * 1024)

        let timeoutRunner = SystemCommandRunner(timeout: 0.05)
        let startedAt = Date()
        let timedOut = try timeoutRunner.run("/bin/sleep", arguments: ["2"])
        #expect(timedOut.status == 124)
        #expect(timedOut.errorText.contains("timed out"))
        #expect(Date().timeIntervalSince(startedAt) < 1.5)

        let inheritedPipeStartedAt = Date()
        let inheritedPipe = try SystemCommandRunner(timeout: 1).run(
            "/bin/sh", arguments: ["-c", "sleep 2 & exit 0"]
        )
        #expect(inheritedPipe.status == 0)
        #expect(Date().timeIntervalSince(inheritedPipeStartedAt) < 1)
    }

    @Test
    func testSystemCommandRunnerCancellationIsPrompt() async throws {
        let runner = SystemCommandRunner(timeout: 5)
        let startedAt = Date()
        let command = Task.detached { () -> Bool in
            do {
                _ = try runner.run("/bin/sleep", arguments: ["3"])
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        command.cancel()
        #expect(await command.value)
        #expect(Date().timeIntervalSince(startedAt) < 1.5)
    }

    @Test
    func testBundledSmartctlIsUniversalAndIncludesCorrespondingSource() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let smartctl = macosRoot.appendingPathComponent("Resources/Tools/smartctl")
        let thirdParty = macosRoot.appendingPathComponent("Resources/ThirdParty/smartmontools", isDirectory: true)
        let source = thirdParty.appendingPathComponent("smartmontools-7.5.tar.gz")
        #expect(FileManager.default.isExecutableFile(atPath: smartctl.path))
        #expect(FileManager.default.fileExists(atPath: thirdParty.appendingPathComponent("COPYING").path))
        #expect(FileManager.default.fileExists(atPath: thirdParty.appendingPathComponent("NOTICE.md").path))
        #expect(try sha256(of: smartctl) == "5d8a03980cba1799a94f7f9740827a6d058062aa78805c8c29c22918b34257a8")
        #expect(try sha256(of: source) == "690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e")
        #expect(try sha256(of: thirdParty.appendingPathComponent("COPYING")) == "8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643")

        let architectures = try SystemCommandRunner(timeout: 3).run(
            "/usr/bin/lipo", arguments: ["-archs", smartctl.path]
        )
        let text = String(data: architectures.data, encoding: .utf8) ?? ""
        #expect(architectures.status == 0)
        #expect(text.contains("arm64"))
        #expect(text.contains("x86_64"))
    }

    /// Opt-in integration coverage for a real Mac. The normal test suite stays
    /// deterministic, while release verification can explicitly exercise
    /// diskutil, IOKit, system_profiler, and the bundled smartctl together.
    @Test
    func testRealHardwareScanWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["DBHV_RUN_HARDWARE_INTEGRATION"] == "1" else { return }

        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let smartctl = macosRoot.appendingPathComponent("Resources/Tools/smartctl").path
        let startedAt = Date()
        let snapshot = HardwareScanner(smartctlPaths: [smartctl]).scanSynchronously()

        #expect(!snapshot.drives.isEmpty)
        #expect(Date().timeIntervalSince(startedAt) < 75)
        #expect(!snapshot.warnings.contains { $0.localizedCaseInsensitiveContains("timed out") })
        for drive in snapshot.drives {
            #expect(drive.deviceIdentifier.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil)
            #expect(drive.capacityBytes > 0)
            #expect(drive.temperatureCelsius.map { (-30...150).contains($0) } ?? true)
            #expect(drive.lifeRemainingPercent.map { (0...100).contains($0) } ?? true)
        }
        for battery in snapshot.batteries {
            #expect(battery.currentCapacityPercent.map { (0...100).contains($0) } ?? true)
            #expect(battery.healthPercent.map { (0...100).contains($0) } ?? true)
            #expect(battery.temperatureCelsius.map { (-30...120).contains($0) } ?? true)
        }
    }

    @Test
    func testReleaseVersionSourcesStayInSync() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistData = try Data(contentsOf: macosRoot.appendingPathComponent("Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any])
        #expect(plist["CFBundleShortVersionString"] as? String == applicationVersion)
        #expect(plist["CFBundleVersion"] as? String == "7")
        for script in ["build-universal.sh", "build-dmg.sh"] {
            let text = try String(contentsOf: macosRoot.appendingPathComponent("scripts/\(script)"), encoding: .utf8)
            #expect(text.contains("version=\"\(applicationVersion)\""))
        }
    }

    @Test
    func testLiveHardwareUpdateChangesOnlyDynamicFields() {
        let snapshot = sampleSnapshot()
        let updated = snapshot.updatingLiveHardwareState(LiveHardwareState(
            battery: BatteryLiveState(
                chargePercent: 42,
                isCharging: true,
                externalConnected: false,
                temperatureCelsius: 29.5
            ),
            driveTemperatures: ["disk0": 44.5]
        ))
        #expect(updated.generatedAt == snapshot.generatedAt)
        #expect(updated.batteries[0].currentCapacityPercent == 42)
        #expect(updated.batteries[0].isCharging == true)
        #expect(updated.batteries[0].externalConnected == false)
        #expect(updated.batteries[0].healthPercent == snapshot.batteries[0].healthPercent)
        #expect(updated.batteries[0].temperatureCelsius == 29.5)
        #expect(updated.drives[0].temperatureCelsius == 44.5)
        #expect(updated.drives[0].bytesRead == snapshot.drives[0].bytesRead)
        #expect(updated.drives[0].bytesWritten == snapshot.drives[0].bytesWritten)
    }

    @Test @MainActor
    func testCriticalStringsAreLocalizedInEverySupportedLanguage() {
        let languages: [AppLanguage] = [.simplifiedChinese, .russian, .french, .german, .korean, .japanese]
        for language in languages {
            #expect(L10n.missingTranslationKeys(for: language).isEmpty)
            #expect(L10n.text("batteryVoltage", language) != "Battery voltage")
            #expect(L10n.text("changelog", language) != "What’s New")
            #expect(L10n.text("license", language) != "GNU GPL v3 License")
            #expect(L10n.text("selectAll", language) != "Select All")
            #expect(L10n.text("exportSelected", language) != "Export Selected")
            for key in MainMenuLocalizer.menuKeys {
                #expect(L10n.text(key, language) != key)
            }

            let report = ReportRenderer.render(snapshot: sampleSnapshot(), language: language, hideSerials: true)
            #expect(report.contains("v1.0.6"))
            #expect(report.contains("mAh /"))
            #expect(report.contains("••••••••"))
        }
        #expect(L10n.text("powerOnHours", .simplifiedChinese) == "工作时间")
        #expect(L10n.text("driveWorkingTimeExplanation", .simplifiedChinese) == "硬盘工作时间由硬盘固件统计，可能不包含控制器处于低功耗状态的时间，不等同于电脑开机或实际使用时长。")
        #expect(L10n.text("batteryHealthExplanation", .simplifiedChinese) == "电池健康度以 macOS 校准后的最大容量为准，受温度、充电管理、系统校准和取整影响，它与“满充容量÷设计容量”的直接计算结果可能存在细微差异。")
        #expect(L10n.text("powerConnectedNotCharging", .simplifiedChinese) == "已连接电源；当前电池已充满，或 macOS 根据当前状态暂时采用直接供电。")
    }

    @Test @MainActor
    func testSystemLanguageDetectionWorksOnCleanFirstLaunch() {
        #expect(AppLanguage.detected(preferredLanguages: ["zh-Hans-CN", "en-US"]) == .simplifiedChinese)
        #expect(AppLanguage.detected(preferredLanguages: ["en-US", "zh-Hans-CN"]) == .english)
        #expect(AppLanguage.detected(preferredLanguages: ["ja-JP"]) == .japanese)
        #expect(AppLanguage.detected(preferredLanguages: []) == .english)

        let suiteName = "DriveBatteryHealthViewerTests.first-launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let model = AppModel(defaults: defaults)
        #expect(model.language == .system)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func testBundleApplicationNamesCoverEverySupportedLanguage() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let macOSDirectory = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expectedNames: [AppLanguage: String] = [
            .english: "Drive & Battery Health Viewer",
            .simplifiedChinese: "硬盘与电池健康查看器",
            .russian: "Состояние накопителей и батареи",
            .french: "État des disques et de la batterie",
            .german: "Laufwerks- und Akkuzustand",
            .korean: "드라이브 및 배터리 상태 보기",
            .japanese: "ドライブとバッテリーの状態"
        ]
        for (language, expectedName) in expectedNames {
            let url = macOSDirectory
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(language.rawValue).lproj")
                .appendingPathComponent("InfoPlist.strings")
            let values = NSDictionary(contentsOf: url) as? [String: String]
            #expect(values?["CFBundleDisplayName"] == expectedName)
            #expect(values?["CFBundleName"] == expectedName)
            #expect(expectedName == L10n.text("appName", language))
        }
    }

    @Test @MainActor
    func testMainMenuTitlesRelocalizeImmediately() {
        let menu = NSMenu()
        for title in ["Drive & Battery Health Viewer", "File", "View", "Health Report", "Window", "Help"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: title)
            item.submenu = NSMenu(title: title)
            if title == "Health Report" {
                item.submenu?.addItem(NSMenuItem(title: "Refresh", action: nil, keyEquivalent: "r"))
                item.submenu?.addItem(NSMenuItem(title: "Copy Report", action: nil, keyEquivalent: "c"))
            }
            menu.addItem(item)
        }

        MainMenuLocalizer.apply(to: menu, language: .simplifiedChinese)
        #expect(menu.items.map(\.title) == ["硬盘与电池健康查看器", "文件", "显示", "健康检测报告", "窗口", "帮助"])
        #expect(menu.items.map { $0.attributedTitle?.string ?? $0.title } == ["硬盘与电池健康查看器", "文件", "显示", "健康检测报告", "窗口", "帮助"])
        #expect(menu.items[3].submenu?.items.map(\.title) == ["刷新", "复制报告"])

        MainMenuLocalizer.apply(to: menu, language: .english)
        #expect(menu.items.map(\.title) == ["Drive & Battery Health Viewer", "File", "View", "Health Report", "Window", "Help"])
        #expect(menu.items[3].submenu?.items.map(\.title) == ["Refresh", "Copy Report"])
    }

    @Test @MainActor
    func testMenuDefinitionsAreIdempotentAndOrdered() {
        let expectedOrder = ["menuFile", "menuView", "report", "menuWindow", "menuHelp"]
        let first = MainMenuLocalizer.definitions(for: .simplifiedChinese)
        #expect(first.map(\.key) == expectedOrder)
        #expect(MainMenuLocalizer.menuOrder(for: .simplifiedChinese) == expectedOrder)
        for _ in 0..<20 {
            #expect(MainMenuLocalizer.definitions(for: .simplifiedChinese) == first)
            #expect(MainMenuLocalizer.menuOrder(for: .english) == expectedOrder)
        }
    }

    @Test @MainActor
    func testMenuLanguageRoundTripDoesNotRetainOldTitles() {
        let menu = NSMenu()
        let appItem = NSMenuItem(title: L10n.text("appName", .english), action: nil, keyEquivalent: "")
        appItem.submenu = NSMenu(title: appItem.title)
        menu.addItem(appItem)
        for definition in MainMenuLocalizer.definitions(for: .english) {
            let item = NSMenuItem(title: definition.title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: definition.title)
            menu.addItem(item)
        }

        for language in [AppLanguage.simplifiedChinese, .japanese, .german, .english, .simplifiedChinese] {
            MainMenuLocalizer.apply(to: menu, language: language)
            #expect(menu.items.map(\.title) == [L10n.text("appName", language)] + MainMenuLocalizer.definitions(for: language).map(\.title))
        }
    }

    @Test @MainActor
    func testNoProductionMenuDefinitionCanExposeInternalMarker() {
        for language in AppLanguage.allCases {
            #expect(MainMenuLocalizer.definitions(for: language).allSatisfy {
                !$0.title.hasPrefix("__DBHV_STANDARD_MENU_")
            })
        }
        let menu = NSMenu(title: "Main")
        for definition in MainMenuLocalizer.definitions(for: .english) {
            menu.addItem(NSMenuItem(title: definition.title, action: nil, keyEquivalent: ""))
        }
        #expect(!MainMenuLocalizer.containsInternalMarker(in: menu))
    }

    @Test @MainActor
    func testRepeatedMenuLocalizationPreservesSubmenusAndActions() {
        let menu = NSMenu(title: "Main")
        let help = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpSubmenu = NSMenu(title: "Help")
        let action = #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        let about = NSMenuItem(title: "About", action: action, keyEquivalent: "")
        helpSubmenu.addItem(about)
        help.submenu = helpSubmenu
        menu.addItem(help)

        for _ in 0..<20 { MainMenuLocalizer.apply(to: menu, language: .simplifiedChinese) }

        #expect(menu.items.count == 1)
        #expect(menu.items[0].submenu?.items.count == 1)
        #expect(menu.items[0].submenu?.items[0].action == action)
        #expect(menu.items[0].submenu?.items[0].title == "关于“硬盘与电池健康查看器”")
    }

    @Test @MainActor
    func testCompleteStandardMenuRoundTripPreservesIdentityAndStructure() {
        let menu = representativeMainMenu()
        let itemIdentities = menuTreeItems(menu).map(ObjectIdentifier.init)
        let submenuIdentities = menuTreeSubmenus(menu).map(ObjectIdentifier.init)
        let actionSelectors = menuTreeItems(menu).map { $0.action.map(NSStringFromSelector) }
        let itemCounts = menuTreeSubmenus(menu).map { $0.items.count }

        let languages: [AppLanguage] = [.simplifiedChinese, .russian, .french, .german, .korean, .japanese, .english]
        for language in languages {
            for _ in 0..<20 { MainMenuLocalizer.apply(to: menu, language: language) }
            #expect(menuTreeItems(menu).map(ObjectIdentifier.init) == itemIdentities)
            #expect(menuTreeSubmenus(menu).map(ObjectIdentifier.init) == submenuIdentities)
            #expect(menuTreeItems(menu).map { $0.action.map(NSStringFromSelector) } == actionSelectors)
            #expect(menuTreeSubmenus(menu).map { $0.items.count } == itemCounts)
            #expect(!MainMenuLocalizer.containsInternalMarker(in: menu))
            #expect(menu.items.count == 6)
            #expect(menu.items[4].submenu?.items.count == 8)
            let windowTitles = menu.items[4].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
            #expect(Set(windowTitles).count == windowTitles.count)
        }

        MainMenuLocalizer.apply(to: menu, language: .russian)
        #expect(menu.items.map(\.title) == ["Состояние накопителей и батареи", "Файл", "Вид", "Отчёт о состоянии", "Окно", "Справка"])
        #expect(menu.items[1].submenu?.items[0].title == "Экспортировать текущий отчёт")
        #expect(menu.items[2].submenu?.items[0].title == "Показать боковую панель")
        #expect(menu.items[4].submenu?.items[0].title == "Свернуть")
        #expect(menu.items[4].submenu?.items[4].title == "Перемещение и изменение размера")
        #expect(menu.items[5].submenu?.items[0].title == "Страница проекта")
    }

    @Test @MainActor
    func testProductionMenuTreeIsStableLocalizedAndFreeOfInjectedDuplicates() {
        let menu = MainMenuLocalizer.makeMenuForTesting(language: .english)
        let itemIdentities = menuTreeItems(menu).map(ObjectIdentifier.init)
        let submenuIdentities = menuTreeSubmenus(menu).map(ObjectIdentifier.init)
        let itemCounts = menuTreeSubmenus(menu).map { $0.items.count }
        let actionSelectors = menuTreeItems(menu).map { $0.action.map(NSStringFromSelector) }

        #expect(menu.items.map(\.title) == [
            "Drive & Battery Health Viewer", "File", "View",
            "Health Report", "Window", "Help"
        ])
        #expect(menu.items[4].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) == [
            "Minimize", "Zoom", "Enter/Exit Full Screen", "Bring All to Front"
        ])

        for language in [AppLanguage.simplifiedChinese, .english, .russian, .japanese, .german, .simplifiedChinese] {
            for _ in 0..<20 { MainMenuLocalizer.apply(to: menu, language: language) }
            #expect(menuTreeItems(menu).map(ObjectIdentifier.init) == itemIdentities)
            #expect(menuTreeSubmenus(menu).map(ObjectIdentifier.init) == submenuIdentities)
            #expect(menuTreeSubmenus(menu).map { $0.items.count } == itemCounts)
            #expect(menuTreeItems(menu).map { $0.action.map(NSStringFromSelector) } == actionSelectors)
            #expect(!MainMenuLocalizer.containsInternalMarker(in: menu))
            let windowTitles = menu.items[4].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
            #expect(windowTitles.count == Set(windowTitles).count)
        }

        #expect(menu.items.map(\.title) == [
            "硬盘与电池健康查看器", "文件", "显示",
            "健康检测报告", "窗口", "帮助"
        ])
        #expect(menu.items[1].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) == ["导出当前报告", "打开报告文件夹", "关闭窗口"])
        #expect(menu.items[5].submenu?.items.map(\.title) == ["项目主页", "反馈问题", "查看更新日志"])
    }

    @Test @MainActor
    func testChangelogMerges1051Into106WithoutChangingOlderReleases() {
        for language in AppLanguage.allCases {
            let releases = ChangelogRelease.localized(for: language)
            #expect(releases.map(\.version) == ["1.0.6", "1.0.5", "1.0.4", "1.0.0"])
            #expect(releases[0].sections.map(\.kind) == [.feature, .fix])
            #expect(releases[0].sections[0].kind.symbol == "checkmark.circle.fill")
            #expect(releases[0].sections[1].kind.symbol == "wrench.and.screwdriver.fill")
            #expect(releases[0].sections[0].items.count == 2)
            #expect(releases[0].sections[1].items.count == 5)
            #expect(releases[0].sections.flatMap(\.items).allSatisfy { !$0.isEmpty })
            #expect(releases[1].sections.map(\.kind) == [.feature, .fix])
            #expect(releases[2].sections.map(\.kind) == [.feature, .fix])
            #expect(releases[2].sections[0].items.count == 2)
            #expect(releases[2].sections[1].items.count == 2)
            #expect(releases[3].sections.map(\.kind) == [.historical])
        }
        let chinese = ChangelogRelease.localized(for: .simplifiedChinese)
        #expect(chinese[0].sections[1].items.allSatisfy { $0.hasPrefix("修复了") && $0.hasSuffix("的问题。") })
        #expect(chinese[0].sections[0].items.contains("增强外接 USB、Thunderbolt 以及支持 SAT 透传的硬盘详细信息读取能力。"))
        #expect(chinese[0].sections[1].items.contains("修复了首次启动并跟随系统语言时，顶部应用菜单名称可能显示为英文的问题。"))
        #expect(chinese[1].sections[0].items.contains("新增对 macOS 26 及以上版本 Liquid Glass 界面效果的支持。"))
        #expect(chinese[1].sections[0].items.contains("新增检查更新功能。"))
        #expect(chinese[1].sections[1].items.allSatisfy { $0.hasPrefix("修复了") && $0.hasSuffix("的问题。") })
        #expect(chinese[2].sections[0].items == [
            "电量、充电状态、电源连接状态以及硬盘与电池温度改为自动实时更新。",
            "统一硬盘与电池字段顺序，容量改用 mAh / Wh，并完善健康度说明。"
        ])
        #expect(chinese[2].sections[1].items == [
            "修复重复刷新后 NVMe S.M.A.R.T. 数据消失的问题。",
            "调整应用图标安全边距。"
        ])
    }

    @Test
    func testReportsAndLiveUpdatesSupportDesktopMacWithoutBattery() {
        var desktop = sampleSnapshot()
        desktop.batteries = []
        for language in AppLanguage.allCases {
            let report = ReportRenderer.render(snapshot: desktop, language: language, hideSerials: true)
            #expect(report.contains("v1.0.6"))
            #expect(report.contains(desktop.computerName))
        }
        let updated = desktop.updatingLiveHardwareState(LiveHardwareState(
            battery: nil,
            driveTemperatures: ["disk0": 41]
        ))
        #expect(updated.batteries.isEmpty)
        #expect(updated.drives[0].temperatureCelsius == 41)
    }

    @Test @MainActor
    func testWindowAndHelpDefinitionsHaveUniqueStableEntries() {
        let definitions = MainMenuLocalizer.definitions(for: .english)
        #expect(Set(definitions.map(\.key)).count == definitions.count)
        #expect(definitions.filter(\.isSystemOwned).map(\.key) == MainMenuLocalizer.standardMenuKeys)
        #expect(definitions.filter { !$0.isSystemOwned }.map(\.key) == ["report"])
    }

    @Test @MainActor
    func testRequestedMenuCommandsAreLocalizedBoundAndEditableMenuIsAbsent() {
        let menu = MainMenuLocalizer.makeMenuForTesting(language: .simplifiedChinese)
        #expect(menu.items.map(\.title) == ["硬盘与电池健康查看器", "文件", "显示", "健康检测报告", "窗口", "帮助"])
        #expect(!menu.items.map(\.title).contains("编辑"))

        let fileItems = menu.items[1].submenu?.items.filter { !$0.isSeparatorItem } ?? []
        #expect(fileItems.map(\.title) == ["导出当前报告", "打开报告文件夹", "关闭窗口"])
        #expect(fileItems[0].action.map(NSStringFromSelector) == "exportCurrentReport:")
        #expect(fileItems[1].action.map(NSStringFromSelector) == "openReportFolder:")

        let viewItems = menu.items[2].submenu?.items.filter { !$0.isSeparatorItem } ?? []
        #expect(viewItems.map(\.title).contains("增大报告文字"))
        #expect(viewItems.map(\.title).contains("减小报告文字"))
        #expect(viewItems.map(\.title).contains("恢复默认文字大小"))

        let helpItems = menu.items[5].submenu?.items.filter { !$0.isSeparatorItem } ?? []
        #expect(helpItems.map(\.title) == ["项目主页", "反馈问题", "查看更新日志"])
        #expect(helpItems.map { $0.action.map(NSStringFromSelector) } == ["openProjectHome:", "openIssueFeedback:", "showChangelog:"])

        let appItems = menu.items[0].submenu?.items.filter { !$0.isSeparatorItem } ?? []
        #expect(appItems.map(\.title).contains("检查更新…"))
        #expect(appItems.first(where: { $0.title == "检查更新…" })?.action.map(NSStringFromSelector) == "checkForUpdates:")
    }

    @Test
    func testUpdateVersionComparisonAndStableReleaseDecoding() throws {
        #expect(AppVersion("v1.0.6")! > AppVersion("1.0.5")!)
        #expect(AppVersion("1.0.5.1")! > AppVersion("1.0.5")!)
        #expect(AppVersion("1.0.6")! > AppVersion("1.0.5.1")!)
        #expect(AppVersion("1.0.10")! > AppVersion("1.0.9")!)
        #expect(AppVersion("1.0.5")! == AppVersion("1.0.5.0")!)
        #expect(AppVersion("1.0.5-beta")! == AppVersion("1.0.5")!)

        let data = Data(#"{"tag_name":"v1.0.6","html_url":"https://github.com/xincheng1237/drive-battery-health-viewer/releases/tag/v1.0.6","draft":false,"prerelease":false}"#.utf8)
        let release = try GitHubReleaseChecker.decodeRelease(from: data)
        #expect(release.version == "1.0.6")
        #expect(release.pageURL.absoluteString.hasSuffix("/releases/tag/v1.0.6"))
    }

    @Test @MainActor
    func testUpdateCheckPresentsNewReleaseAndRecognizesCurrentVersion() async {
        let suiteName = "DriveBatteryHealthViewerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppLanguage.english.rawValue, forKey: "language")
        let release = AppReleaseInfo(
            version: "1.0.6",
            pageURL: URL(string: "https://github.com/xincheng1237/drive-battery-health-viewer/releases/tag/v1.0.6")!
        )

        let updateModel = AppModel(
            defaults: defaults,
            releaseChecker: StubReleaseChecker(release: release),
            currentAppVersion: "1.0.5"
        )
        await updateModel.checkForUpdatesNow()
        #expect(updateModel.availableUpdate?.version == "1.0.6")
        #expect(updateModel.availableUpdate?.currentVersion == "1.0.5")
        #expect(updateModel.alertMessage == nil)

        let currentModel = AppModel(
            defaults: defaults,
            releaseChecker: StubReleaseChecker(release: release),
            currentAppVersion: "1.0.6"
        )
        await currentModel.checkForUpdatesNow()
        #expect(currentModel.availableUpdate == nil)
        #expect(currentModel.alertMessage == "You’re using the latest version (v1.0.6).")
    }

    @Test @MainActor
    func testReportTextMenuAdjustmentsClampAndReset() {
        let suiteName = "DriveBatteryHealthViewerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(defaults: defaults)
        model.reportTextSize = 22
        model.increaseReportTextSize()
        #expect(model.reportTextSize == 22)
        model.reportTextSize = 11
        model.decreaseReportTextSize()
        #expect(model.reportTextSize == 11)
        model.resetReportTextSize()
        #expect(model.reportTextSize == 13)
    }

    @Test @MainActor
    func testBatchHistoryExportAndDeleteOperateOnSelectedRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "DriveBatteryHealthViewerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        defaults.set(root.path, forKey: "historyDirectory")
        let store = HistoryStore(directory: root)
        let first = try store.save(snapshot: sampleSnapshot(), source: .refresh, hideSerials: true)
        var secondSnapshot = sampleSnapshot()
        secondSnapshot.generatedAt.addTimeInterval(60)
        _ = try store.save(snapshot: secondSnapshot, source: .refresh, hideSerials: true)

        let model = AppModel(defaults: defaults)
        #expect(model.history.count == 2)
        model.selectAllHistory()
        #expect(model.selectedHistoryIDs.count == 2)
        model.exportSelectedHistory(to: destination)

        let folders = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
        #expect(folders.count == 1)
        let exported = try FileManager.default.contentsOfDirectory(at: folders[0], includingPropertiesForKeys: nil)
        #expect(exported.filter { $0.pathExtension == "txt" }.count == 2)

        model.deleteSelectedHistory(ids: model.selectedHistoryIDs)
        #expect(model.history.isEmpty)
        #expect(try store.load().isEmpty)
        _ = first
    }

    @Test
    func testLiveBatteryReaderReturnsSaneValuesWhenAvailable() {
        guard let state = readBatteryLiveState() else { return }
        #expect((0...100).contains(state.chargePercent))
        #expect(state.temperatureCelsius.map { (-30...120).contains($0) } ?? true)
    }

    @Test
    func testNativeBatteryStatusSymbolsAreAvailable() {
        #expect(ControlCenterBatteryAssets.hasAssets(for: "plug"))
        #expect(ControlCenterBatteryAssets.hasAssets(for: "bolt"))
        #expect(ControlCenterBatteryAssets.image(named: "battery-outline")?.size == NSSize(width: 23, height: 12))
        #expect(ControlCenterBatteryAssets.image(named: "battery-cap")?.size == NSSize(width: 2, height: 12))
        #expect(ControlCenterBatteryAssets.image(named: "battery-plug")?.size == NSSize(width: 11, height: 14))
        #expect(ControlCenterBatteryAssets.image(named: "battery-plug-mask")?.size == NSSize(width: 11, height: 14))
        #expect(NSImage(
            systemSymbolName: "battery.100percent.bolt",
            variableValue: 0.72,
            accessibilityDescription: nil
        ) != nil)
        #expect(NSImage(systemSymbolName: "battery.100", accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: "battery.75", accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) != nil)
    }

    private func sampleSnapshot() -> HealthSnapshot {
        HealthSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            computerName: "Test Mac",
            drives: [DriveInfo(
                deviceIdentifier: "disk0", model: "Test SSD", serialNumber: "DRIVE-SERIAL", firmware: "1.0",
                protocolName: "NVMe", capacityBytes: 1_000_000_000_000, smartStatus: "Verified", healthState: .good,
                lifeRemainingPercent: 98, temperatureCelsius: 35, powerOnHours: 100, powerCycles: 20,
                bytesRead: 2_000_000_000, bytesWritten: 3_000_000_000, unsafeShutdowns: 1, mediaErrors: 0,
                isSolidState: true, isInternal: true, notes: []
            )],
            batteries: [BatteryInfo(
                name: "Battery", manufacturer: "Apple", serialNumber: "BATTERY-SERIAL", chemistry: "Li-ion",
                designCapacityMAh: 5000, fullChargeCapacityMAh: 4500, currentCapacityPercent: 75, cycleCount: 120,
                healthPercent: 90, capacityRatioPercent: 90, voltageMillivolts: 12_000, designVoltageMillivolts: 11_400,
                temperatureCelsius: 31, isCharging: false, externalConnected: true,
                healthState: .good, notes: []
            )]
        )
    }

    @MainActor
    private func representativeMainMenu() -> NSMenu {
        func top(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        }

        func command(_ title: String, _ action: Selector? = nil, key: String = "") -> NSMenuItem {
            NSMenuItem(title: title, action: action, keyEquivalent: key)
        }

        let move = command("Move & Resize")
        move.submenu = NSMenu(title: "Move & Resize")
        ["Left", "Right", "Top", "Bottom", "Top Left", "Top Right", "Bottom Left", "Bottom Right", "Return to Previous Size"]
            .map { command($0) }
            .forEach(move.submenu!.addItem)

        let main = NSMenu(title: "Main")
        main.addItem(top("Drive & Battery Health Viewer", [
            command("About Drive & Battery Health Viewer", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            command("Settings…"), command("Services"), command("Hide Drive & Battery Health Viewer"),
            command("Hide Others"), command("Show All"), command("Quit Drive & Battery Health Viewer")
        ]))
        main.addItem(top("File", [command("Export Current Report"), command("Open Reports Folder"), command("Close Window", #selector(NSWindow.performClose(_:)), key: "w")]))
        main.addItem(top("View", [
            command("Show Sidebar"), command("Show Toolbar"), command("Customize Toolbar…"),
            command("Increase Report Text Size"), command("Decrease Report Text Size"), command("Reset Report Text Size"),
            command("Enter Full Screen")
        ]))
        main.addItem(top("Health Report", [command("Refresh", key: "r"), command("Copy Report", key: "c")]))
        main.addItem(top("Window", [
            command("Minimize"), command("Zoom"), command("Fill"), command("Center"), move,
            command("Full Screen Tile"), command("Remove Window from Set"), command("Bring All to Front")
        ]))
        main.addItem(top("Help", [command("Project Homepage"), command("Report an Issue"), command("View Release Notes")]))
        return main
    }

    @MainActor
    private func menuTreeItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(menuTreeItems) ?? []) }
    }

    @MainActor
    private func menuTreeSubmenus(_ menu: NSMenu) -> [NSMenu] {
        [menu] + menu.items.compactMap(\.submenu).flatMap(menuTreeSubmenus)
    }
}

private struct StubReleaseChecker: AppReleaseChecking {
    let release: AppReleaseInfo

    func latestStableRelease() async throws -> AppReleaseInfo { release }
}

private struct FixtureRunner: CommandRunning {
    let outputs: [String: CommandOutput]

    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        outputs[Self.key(executable, arguments)] ?? .failure
    }

    static func key(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).joined(separator: "\u{1F}")
    }
}

private extension CommandOutput {
    static func success(_ data: Data) -> CommandOutput { CommandOutput(data: data, errorText: "", status: 0) }
    static var failure: CommandOutput { CommandOutput(data: Data(), errorText: "fixture unavailable", status: 1) }
}

private func plist(_ value: Any) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
}

private func json(_ value: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: value)
}

private func sha256(of url: URL) throws -> String {
    let output = try SystemCommandRunner(timeout: 3).run(
        "/usr/bin/shasum", arguments: ["-a", "256", url.path]
    )
    guard output.status == 0,
          let digest = String(data: output.data, encoding: .utf8)?.split(separator: " ").first else {
        throw ScannerError.commandFailed(output.errorText)
    }
    return String(digest)
}

private let storageProfilerTestArguments = [
    "SPNVMeDataType", "SPSerialATADataType", "SPUSBDataType",
    "SPThunderboltDataType", "SPStorageDataType", "-json", "-detailLevel", "full"
]
