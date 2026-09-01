import AppKit
import ChargeProtectionCore
import CNVMeSMART
import Foundation
import IOKit.ps
import Testing
@testable import DriveBatteryHealthViewer
@testable import DriveBatteryChargeLimitAgent

@Suite("Drive & Battery Health Viewer core")
struct CoreTests {
    @Test
    func testOnlyReportCheckpointRefreshesMayAutomaticallySaveHistory() {
        #expect(HardwareRefreshReason.userInitiated.permitsAutomaticHistorySave)
        #expect(HardwareRefreshReason.coldLaunch.permitsAutomaticHistorySave)
        #expect(HardwareRefreshReason.resumedAfterExtendedBackground.permitsAutomaticHistorySave)
        #expect(!HardwareRefreshReason.lifecycleRecovery.permitsAutomaticHistorySave)
    }

    @Test
    func testExtendedBackgroundCheckpointBeginsAtTwentyFourHours() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        #expect(!BackgroundRefreshPolicy.requiresCheckpoint(
            backgroundedAt: now.addingTimeInterval(-(24 * 60 * 60) + 1),
            now: now
        ))
        #expect(BackgroundRefreshPolicy.requiresCheckpoint(
            backgroundedAt: now.addingTimeInterval(-(24 * 60 * 60)),
            now: now
        ))
    }

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
    func testNVMeSmartctlErrorCountersAreParsedSeparately() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk4", "Size": 1_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk4", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "External NVMe", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "Thunderbolt", "SolidState": true, "Internal": false
        ])
        let smart = json([
            "model_name": "External NVMe",
            "smart_status": ["passed": true],
            "nvme_smart_health_information_log": [
                "unsafe_shutdowns": 12,
                "media_errors": 3,
                "num_err_log_entries": 47
            ]
        ])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk4"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", storageProfilerTestArguments): .success(json([:])),
            FixtureRunner.key("/usr/bin/true", ["--version"]): .success(Data()),
            FixtureRunner.key("/usr/bin/true", ["-a", "-j", "/dev/disk4"]): .success(smart)
        ])

        let drive = try #require(HardwareScanner(runner: runner, smartctlPaths: ["/usr/bin/true"]).scanDrives().first)
        #expect(drive.unsafeShutdowns == 12)
        #expect(drive.mediaErrors == 3)
        #expect(drive.errorLogEntries == 47)
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
        fresh.drives[0].unsafeShutdowns = nil
        fresh.drives[0].errorLogEntries = nil
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
        #expect(merged.drives[0].unsafeShutdowns == 1)
        #expect(merged.drives[0].errorLogEntries == 2)
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

        // GitHub's shared macOS runners execute Swift Testing cases in
        // parallel, so a normally instant `lipo` launch can occasionally be
        // delayed by process contention. Keep this packaging assertion
        // bounded without treating a short-lived runner delay as a failure.
        let architectures = try SystemCommandRunner(timeout: 15).run(
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
        #expect(plist["CFBundleVersion"] as? String == "9")
        for script in ["build-universal.sh", "build-dmg.sh"] {
            let text = try String(contentsOf: macosRoot.appendingPathComponent("scripts/\(script)"), encoding: .utf8)
            #expect(text.contains("version=\"\(applicationVersion)\""))
            #expect(text.contains("bundle_build=\"9\""))
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
            #expect(report.contains("v\(applicationVersion)"))
            #expect(report.contains("mAh /"))
            #expect(report.contains("••••••••"))
        }
        #expect(L10n.text("powerOnHours", .simplifiedChinese) == "工作时间")
        #expect(L10n.text("driveWorkingTimeExplanation", .simplifiedChinese) == "硬盘工作时间由硬盘固件统计，可能不包含控制器处于低功耗状态的时间，不等同于电脑开机或实际使用时长。")
        #expect(L10n.text("batteryHealthExplanation", .simplifiedChinese) == "电池健康度以 macOS 校准后的最大容量为准，受温度、充电管理、系统校准和取整影响，它与“满充容量÷设计容量”的直接计算结果可能存在细微差异。")
        #expect(L10n.text("powerConnectedNotCharging", .simplifiedChinese) == "已连接电源；当前电池已充满，或 macOS 根据当前状态暂时采用直接供电。")
        #expect(L10n.text("uninstallChargeHelper", .simplifiedChinese) == "停用并卸载充电辅助程序")
        #expect(L10n.text("chargeHelperAuthorizationTitle", .simplifiedChinese) == "需要管理员授权")
        #expect(L10n.text("continueAuthorization", .simplifiedChinese) == "继续")
        #expect(L10n.text("chargeHelperInstallAuthorizationMessage", .simplifiedChinese).contains("密码仅由 macOS 验证"))
        #expect(L10n.text("chargeHelperUninstallAuthorizationMessage", .simplifiedChinese).contains("本软件不会读取或保存"))
        #expect(L10n.text("desktopMacPoweredTitle", .simplifiedChinese) == "插电即满血")
        #expect(L10n.text("desktopMacMode", .simplifiedChinese) == "桌面 Mac 模式")
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
        #expect(menu.items[5].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) == ["项目主页", "反馈问题", "导出诊断日志…", "查看更新日志"])
    }

    @Test @MainActor
    func testChangelogMerges1051Into106WithoutChangingOlderReleases() {
        for language in AppLanguage.allCases {
            let releases = ChangelogRelease.localized(for: language)
            #expect(releases.map(\.version) == ["1.1.0", "1.0.6", "1.0.5", "1.0.4", "1.0.0"])
            #expect(releases[0].sections.map(\.kind) == [.feature, .improvement])
            #expect(releases[0].sections[0].kind.symbol == "checkmark.circle.fill")
            #expect(releases[0].sections[1].kind.symbol == "wand.and.stars")
            #expect(releases[0].sections[0].items.count == 7)
            #expect(releases[0].sections[1].items.count == 3)
            #expect(releases[0].sections.flatMap(\.items).allSatisfy { !$0.isEmpty })
            #expect(releases[1].sections.map(\.kind) == [.feature, .fix])
            #expect(releases[2].sections.map(\.kind) == [.feature, .fix])
            #expect(releases[3].sections.map(\.kind) == [.feature, .fix])
            #expect(releases[4].sections.map(\.kind) == [.historical])
        }
        let chinese = ChangelogRelease.localized(for: .simplifiedChinese)
        #expect(chinese[0].sections[0].items[0] == "新增 Apple Silicon Mac 电池充电保护，支持 80% 至 100% 固定充电上限、“本次充满”以及达到设定电量后的菜单栏快捷控制。")
        #expect(chinese[0].sections[0].items[1] == "在 macOS 15.8 上新增 PowerUI 原生 80% 充电上限，仅开放系统实际支持的档位，并保持适配器供电。")
        #expect(chinese[0].sections[0].items.contains("为 iMac、Mac mini、Mac Studio 等桌面设备的“电池”部分设计了新的界面显示。"))
        #expect(chinese[0].sections[0].items.contains("新增概览中的非正常关机次数与错误日志条目显示。"))
        #expect(chinese[0].sections[0].items.contains("新增“关于”页面中的检查更新入口，便于用户发现并使用更新功能。"))
        #expect(chinese[0].sections[1].items.contains("优化了历史记录选择界面的按钮布局与多选操作体验。"))
        #expect(chinese[0].sections[1].items.contains("为内置 SSD 的“工作时间”增加说明，便于理解固件统计值与 Mac 实际使用时间的差异。"))
        #expect(!chinese[0].sections.flatMap(\.items).contains("修复升级应用后旧版充电辅助程序或菜单栏代理可能未被完整替换的问题。"))
        #expect(!chinese[0].sections.flatMap(\.items).contains("修复 macOS 15.8 原生 80% 充电上限已经生效时仍可能误报“无法应用充电保护”的问题。"))
        #expect(!chinese[0].sections.flatMap(\.items).contains("修复充电保护已启用时菜单栏图标可能不显示的问题，并增强睡眠唤醒、屏幕变化及代理更新后的自动恢复。"))
        #expect(chinese[1].sections[1].items.allSatisfy { $0.hasPrefix("修复了") && $0.hasSuffix("的问题。") })
        #expect(chinese[1].sections[0].items.contains("增强外接 USB、Thunderbolt 以及支持 SAT 透传的硬盘详细信息读取能力。"))
        #expect(chinese[1].sections[1].items.contains("修复了首次启动并跟随系统语言时，顶部应用菜单名称可能显示为英文的问题。"))
        #expect(chinese[2].sections[0].items.contains("新增对 macOS 26 及以上版本 Liquid Glass 界面效果的支持。"))
        #expect(chinese[2].sections[0].items.contains("新增检查更新功能。"))
        #expect(chinese[2].sections[1].items.allSatisfy { $0.hasPrefix("修复了") && $0.hasSuffix("的问题。") })
        #expect(chinese[3].sections[0].items == [
            "电量、充电状态、电源连接状态以及硬盘与电池温度改为自动实时更新。",
            "统一硬盘与电池字段顺序，容量改用 mAh / Wh，并完善健康度说明。"
        ])
        #expect(chinese[3].sections[1].items == [
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
            #expect(report.contains("v\(applicationVersion)"))
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
        #expect(helpItems.map(\.title) == ["项目主页", "反馈问题", "导出诊断日志…", "查看更新日志"])
        #expect(helpItems.map { $0.action.map(NSStringFromSelector) } == ["openProjectHome:", "openIssueFeedback:", "exportDiagnosticLogs:", "showChangelog:"])

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

    @Test
    func testVersionUpdatePromptDetectsPublicAndSameVersionBuildUpdates() {
        #expect(VersionUpdatePromptPolicy.shouldPresent(
            previousReleaseIdentifier: nil,
            legacyPreviousVersion: nil,
            currentVersion: "1.1.0",
            currentBuild: "9",
            hasExistingAppData: false
        ) == false)
        #expect(VersionUpdatePromptPolicy.shouldPresent(
            previousReleaseIdentifier: nil,
            legacyPreviousVersion: nil,
            currentVersion: "1.1.0",
            currentBuild: "9",
            hasExistingAppData: true
        ))
        #expect(VersionUpdatePromptPolicy.shouldPresent(
            previousReleaseIdentifier: nil,
            legacyPreviousVersion: "1.1.0",
            currentVersion: "1.1.0",
            currentBuild: "9",
            hasExistingAppData: true
        ))
        #expect(VersionUpdatePromptPolicy.shouldPresent(
            previousReleaseIdentifier: "1.1.0#8",
            legacyPreviousVersion: "1.1.0",
            currentVersion: "1.1.0",
            currentBuild: "9",
            hasExistingAppData: true
        ))
        #expect(VersionUpdatePromptPolicy.shouldPresent(
            previousReleaseIdentifier: "1.0.6#42",
            legacyPreviousVersion: "1.0.6",
            currentVersion: "1.1.0",
            currentBuild: "9",
            hasExistingAppData: true
        ))
        #expect(VersionUpdatePromptPolicy.shouldPresent(
            previousReleaseIdentifier: "1.1.0#9",
            legacyPreviousVersion: "1.1.0",
            currentVersion: "1.1.0",
            currentBuild: "9",
            hasExistingAppData: true
        ) == false)
    }

    @Test @MainActor
    func testVersionUpdatePromptPersistsFullReleaseIdentityOncePerBuild() {
        let suiteName = "DriveBatteryHealthViewerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cleanInstall = AppModel(
            defaults: defaults,
            currentAppVersion: "1.1.0",
            currentAppBuild: "9"
        )
        #expect(cleanInstall.showsVersionUpdatePrompt == false)

        let sameBuildRelaunch = AppModel(
            defaults: defaults,
            currentAppVersion: "1.1.0",
            currentAppBuild: "9"
        )
        #expect(sameBuildRelaunch.showsVersionUpdatePrompt == false)

        let sameVersionReplacementBuild = AppModel(
            defaults: defaults,
            currentAppVersion: "1.1.0",
            currentAppBuild: "10"
        )
        #expect(sameVersionReplacementBuild.showsVersionUpdatePrompt)

        let replacementBuildRelaunch = AppModel(
            defaults: defaults,
            currentAppVersion: "1.1.0",
            currentAppBuild: "10"
        )
        #expect(replacementBuildRelaunch.showsVersionUpdatePrompt == false)

        #expect(VersionUpdatePromptPolicy.shouldPresent(
            previousReleaseIdentifier: "1.1.0#10",
            legacyPreviousVersion: "1.1.0",
            currentVersion: "1.2.0",
            currentBuild: "1",
            hasExistingAppData: true
        ))
    }

    @Test
    func testAboutUpdateActionAndHistoryListUseStableNativeComponents() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let viewsURL = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DriveBatteryHealthViewer/Views.swift")
        let source = try String(contentsOf: viewsURL, encoding: .utf8)
        #expect(source.contains("AboutButton(symbol: \"arrow.clockwise\", title: model.t(\"checkForUpdates\")) { model.checkForUpdates() }"))
        #expect(source.contains(".listStyle(.plain)"))
        #expect(source.contains("VersionUpdateTip()"))
        #expect(source.contains("DetailItem(model.t(\"unsafeShutdowns\"), drive.unsafeShutdowns.map(String.init))"))
        #expect(source.contains("DetailItem(model.t(\"errorLogEntries\"), drive.errorLogEntries.map(String.init))"))
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
        let rangeStart = try #require(model.history.first?.id)
        let rangeEnd = try #require(model.history.last?.id)
        model.toggleHistorySelection(rangeStart)
        model.selectHistoryRange(from: rangeStart, through: rangeEnd)
        #expect(model.selectedHistoryIDs == Set([rangeStart, rangeEnd]))
        model.clearHistorySelection()
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
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let providingPower = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue() as String
        if providingPower == kIOPSACPowerValue {
            #expect(state.externalConnected)
        }
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
        #expect(NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) != nil)
    }

    @Test
    func testChargeProtectionSystemVersionBoundariesAndAllowedLimits() {
        let macOS158 = OperatingSystemVersion(majorVersion: 15, minorVersion: 8, patchVersion: 0)
        #expect(ChargeLimitCapabilityPolicy.isPowerUIEightyOnly(
            isAppleSilicon: true,
            operatingSystemVersion: macOS158
        ))
        #expect(ChargeLimitCapabilityPolicy.permits(
            .eighty,
            isAppleSilicon: true,
            operatingSystemVersion: macOS158
        ))
        #expect(!ChargeLimitCapabilityPolicy.permits(
            .eightyFive,
            isAppleSilicon: true,
            operatingSystemVersion: macOS158
        ))
        #expect(ChargeLimitCapabilityPolicy.permits(
            .oneHundred,
            isAppleSilicon: true,
            operatingSystemVersion: macOS158
        ))
        #expect(ChargeLimitCapabilityPolicy.normalized(
            .ninetyFive,
            isAppleSilicon: true,
            operatingSystemVersion: macOS158
        ) == .eighty)
        #expect(!ChargeLimitCapabilityPolicy.isPowerUIEightyOnly(
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 6)
        ))
        let multiLevelVersions = [
            OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0),
            OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 0),
            OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 6),
            OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0),
            OperatingSystemVersion(majorVersion: 26, minorVersion: 3, patchVersion: 9),
            OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        ]
        for version in multiLevelVersions {
            #expect(!ChargeLimitCapabilityPolicy.isPowerUIEightyOnly(
                isAppleSilicon: true,
                operatingSystemVersion: version
            ))
            for limit in FixedChargeLimit.allCases {
                #expect(ChargeLimitCapabilityPolicy.permits(
                    limit,
                    isAppleSilicon: true,
                    operatingSystemVersion: version
                ))
            }
        }
        #expect(ChargeProtectionAvailability.evaluate(
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 3, patchVersion: 9)
        ) == .softwareAvailable)
        #expect(ChargeProtectionAvailability.evaluate(
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        ) == .systemPreferred)
        #expect(ChargeProtectionAvailability.evaluate(
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 1),
            userSelectedSoftwareManagement: true
        ) == .softwareManaged)
        #expect(ChargeProtectionAvailability.evaluate(
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        ) == .systemPreferred)
        #expect(ChargeProtectionAvailability.evaluate(
            isAppleSilicon: false,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 0)
        ) == .unsupportedHardware)
        #expect(ChargeProtectionAvailability.evaluate(
            isAppleSilicon: false,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0),
            userSelectedSoftwareManagement: true
        ) == .unsupportedHardware)
        #expect(FixedChargeLimit.allCases.map(\.rawValue) == [80, 85, 90, 95, 100])
        #expect(FixedChargeLimit(validated: 80) == .eighty)
        #expect(FixedChargeLimit(validated: 95) == .ninetyFive)
        #expect(FixedChargeLimit(validated: 79) == nil)
        #expect(FixedChargeLimit(validated: 100) == .oneHundred)
        #expect(ChargeProtectionManager.requiresAdministratorAuthorizationForEnable(
            isInstalled: false,
            installedHelperMatchesBundledHelper: false
        ))
        #expect(ChargeProtectionManager.requiresAdministratorAuthorizationForEnable(
            isInstalled: true,
            installedHelperMatchesBundledHelper: false
        ))
        #expect(!ChargeProtectionManager.requiresAdministratorAuthorizationForEnable(
            isInstalled: true,
            installedHelperMatchesBundledHelper: true
        ))
    }

    @Test @MainActor
    func testMacOS158MainAppOffersNativeEightyOrNormalHundred() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbhv-main-158-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "dbhv-main-158-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ChargeProtectionConfiguration(
            enabled: true,
            fixedLimit: .ninetyFive
        )).write(to: root.appendingPathComponent("configuration.json"))

        let manager = ChargeProtectionManager(
            defaults: defaults,
            logger: DiagnosticLogger(directory: root.appendingPathComponent("logs")),
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 8, patchVersion: 0),
            configurationDirectory: root
        )
        #expect(manager.isPowerUIEightyOnly)
        #expect(manager.configuration.fixedLimit == .eighty)
        #expect(manager.displayedLimitPercentage == 80)
        #expect(manager.isLimitSelectable(80))
        #expect(!manager.isLimitSelectable(85))
        #expect(manager.isLimitSelectable(100))
        manager.setLimit(.ninety)
        #expect(manager.configuration.fixedLimit == .eighty)
        manager.setLimit(.oneHundred)
        #expect(manager.configuration.fixedLimit == .oneHundred)
        #expect(!manager.configuration.enabled)
        #expect(!manager.configuration.temporaryFullCharge)
        #expect(manager.displayedLimitPercentage == 100)
    }

    @Test
    func testChargeProtectionExactLimitAndTemporaryFullStateMachine() {
        let machine = ChargeProtectionStateMachine()
        var configuration = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty)
        let atLimit = machine.decide(
            configuration: configuration,
            battery: ChargeBatteryReading(percentage: 80, fullyCharged: false, adapterConnected: true),
            holdingLimit: nil
        )
        #expect(atLimit.actuation == .holdCharging)
        #expect(atLimit.holdingAfterDecision)
        let belowLimit = machine.decide(
            configuration: configuration,
            battery: ChargeBatteryReading(percentage: 79, fullyCharged: false, adapterConnected: true),
            holdingLimit: .eighty
        )
        #expect(belowLimit.actuation == .allowCharging)
        #expect(!belowLimit.holdingAfterDecision)
        #expect(belowLimit.event == .resumedBelowLimit)
        let atLimitStillHolds = machine.decide(
            configuration: configuration,
            battery: ChargeBatteryReading(percentage: 80, fullyCharged: false, adapterConnected: true),
            holdingLimit: .eighty
        )
        #expect(atLimitStillHolds.actuation == .unchanged)
        #expect(atLimitStillHolds.holdingAfterDecision)

        configuration.temporaryFullCharge = true
        let override = machine.decide(
            configuration: configuration,
            battery: ChargeBatteryReading(percentage: 80, fullyCharged: false, adapterConnected: true),
            holdingLimit: .eighty
        )
        #expect(override.actuation == .allowCharging)
        #expect(override.temporaryFullChargeAfterDecision)
        let completed = machine.decide(
            configuration: configuration,
            battery: ChargeBatteryReading(percentage: 100, fullyCharged: true, adapterConnected: true),
            holdingLimit: nil
        )
        #expect(completed.event == .temporaryFullCompleted)
        #expect(!completed.temporaryFullChargeAfterDecision)
        #expect(completed.holdingAfterDecision)
        #expect(completed.actuation == .holdCharging)
    }

    @Test
    func testChargeControlCapabilitySelectionPrefersAdapterPreservingMethods() {
        #expect(preferredChargeControlMethod(
            chteSupported: true,
            legacyCH0BCH0CSupported: true,
            chieSupported: true
        ) == .chte)
        #expect(preferredChargeControlMethod(
            chteSupported: false,
            legacyCH0BCH0CSupported: true,
            chieSupported: true
        ) == .legacyCH0BCH0C)
        #expect(preferredChargeControlMethod(
            chteSupported: false,
            legacyCH0BCH0CSupported: false,
            chieSupported: true,
        ) == .unavailable)
        #expect(preferredChargeControlMethod(
            chteSupported: false,
            legacyCH0BCH0CSupported: false,
            chieSupported: false
        ) == .unavailable)
    }

    @Test
    func testLegacyChargeControlMethodPersistsInHelperStatus() throws {
        let status = ChargeProtectionStatus(
            helperVersion: "1.1.0.13",
            installed: true,
            enabled: true,
            fixedLimit: .eighty,
            temporaryFullCharge: false,
            holding: true,
            adapterConnected: true,
            batteryPercentage: 80,
            controlMethod: .legacyCH0BCH0C
        )
        let data = try JSONEncoder().encode(status)
        #expect(try JSONDecoder().decode(ChargeProtectionStatus.self, from: data) == status)
    }

    @Test
    func testFreshHelperAdapterReadingCorrectsCHIEPublicBatteryState() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let configuration = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty)
        let fresh = ChargeProtectionStatus(
            helperVersion: "1.1.0",
            timestamp: now.addingTimeInterval(-2),
            installed: true,
            enabled: true,
            fixedLimit: .eighty,
            temporaryFullCharge: false,
            holding: true,
            adapterConnected: true,
            batteryPercentage: 83,
            controlMethod: .chieFallback
        )
        #expect(resolvedExternalPowerConnection(
            systemReportedConnection: false,
            configuration: configuration,
            status: fresh,
            now: now
        ))

        var heartbeatFresh = fresh
        heartbeatFresh.timestamp = now.addingTimeInterval(-15)
        #expect(resolvedExternalPowerConnection(
            systemReportedConnection: false,
            configuration: configuration,
            status: heartbeatFresh,
            now: now
        ))

        var stale = fresh
        stale.timestamp = now.addingTimeInterval(-21)
        #expect(!resolvedExternalPowerConnection(
            systemReportedConnection: false,
            configuration: configuration,
            status: stale,
            now: now
        ))

        var disabled = configuration
        disabled.enabled = false
        #expect(!resolvedExternalPowerConnection(
            systemReportedConnection: false,
            configuration: disabled,
            status: fresh,
            now: now
        ))
    }

    @Test
    func testRaisingChargeLimitReleasesThePreviousHoldImmediately() {
        let machine = ChargeProtectionStateMachine()
        let raised = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eightyFive)
        let decision = machine.decide(
            configuration: raised,
            battery: ChargeBatteryReading(percentage: 82, fullyCharged: false, adapterConnected: true),
            holdingLimit: .eighty
        )
        #expect(decision.actuation == .allowCharging)
        #expect(!decision.holdingAfterDecision)
        #expect(decision.event == .resumedAfterLimitIncrease)

        // A hold begun at 85% also resumes as soon as the reading is below
        // that fixed limit.
        let sameLimit = machine.decide(
            configuration: raised,
            battery: ChargeBatteryReading(percentage: 82, fullyCharged: false, adapterConnected: true),
            holdingLimit: .eightyFive
        )
        #expect(sameLimit.actuation == .allowCharging)
        #expect(!sameLimit.holdingAfterDecision)
        #expect(sameLimit.event == .resumedBelowLimit)
    }

    @Test
    func testPersistentOneHundredPercentLimitIsDistinctFromTemporaryFullCharge() {
        let configuration = ChargeProtectionConfiguration(
            enabled: true,
            fixedLimit: .oneHundred,
            temporaryFullCharge: false
        )
        let machine = ChargeProtectionStateMachine()
        let below = machine.decide(
            configuration: configuration,
            battery: ChargeBatteryReading(percentage: 99, fullyCharged: false, adapterConnected: true),
            holdingLimit: nil
        )
        #expect(below.actuation == .unchanged)
        #expect(!below.holdingAfterDecision)
        let full = machine.decide(
            configuration: configuration,
            battery: ChargeBatteryReading(percentage: 100, fullyCharged: true, adapterConnected: true),
            holdingLimit: nil
        )
        #expect(full.actuation == .holdCharging)
        #expect(full.holdingAfterDecision)
        #expect(!full.temporaryFullChargeAfterDecision)
    }

    @Test
    func testLoweringChargeLimitKeepsSafeHoldWithoutForcingBatteryDischarge() {
        let configuration = ChargeProtectionConfiguration(
            enabled: true,
            fixedLimit: .eighty
        )
        let decision = ChargeProtectionStateMachine().decide(
            configuration: configuration,
            battery: ChargeBatteryReading(
                percentage: 90,
                fullyCharged: false,
                adapterConnected: true
            ),
            holdingLimit: .ninety
        )

        // CHTE stops battery charging while the adapter continues to power the
        // Mac. Lowering a limit must never switch to forced battery discharge.
        #expect(decision.actuation == .unchanged)
        #expect(decision.holdingAfterDecision)
        #expect(!decision.temporaryFullChargeAfterDecision)
    }

    @Test @MainActor
    func testChargeProtectionDisclosureDefaultsAndPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let eligibleSuiteName = "dbhv-tests-eligible-\(UUID().uuidString)"
        let nativeSuiteName = "dbhv-tests-native-\(UUID().uuidString)"
        let eligibleSuite = try #require(UserDefaults(suiteName: eligibleSuiteName))
        let nativeSuite = try #require(UserDefaults(suiteName: nativeSuiteName))
        defer {
            eligibleSuite.removePersistentDomain(forName: eligibleSuiteName)
            nativeSuite.removePersistentDomain(forName: nativeSuiteName)
        }

        let eligible = ChargeProtectionManager(
            defaults: eligibleSuite,
            logger: DiagnosticLogger(directory: root.appendingPathComponent("logs-eligible")),
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 3, patchVersion: 9),
            configurationDirectory: root.appendingPathComponent("config-eligible")
        )
        #expect(eligible.isSectionExpanded)
        #expect(eligible.displayedLimitPercentage == 100)
        eligible.setSectionExpanded(false)

        let eligibleRelaunch = ChargeProtectionManager(
            defaults: eligibleSuite,
            logger: DiagnosticLogger(directory: root.appendingPathComponent("logs-eligible-relaunch")),
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 3, patchVersion: 9),
            configurationDirectory: root.appendingPathComponent("config-eligible")
        )
        #expect(!eligibleRelaunch.isSectionExpanded)

        let native = ChargeProtectionManager(
            defaults: nativeSuite,
            logger: DiagnosticLogger(directory: root.appendingPathComponent("logs-native")),
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0),
            configurationDirectory: root.appendingPathComponent("config-native")
        )
        #expect(!native.isSectionExpanded)
        native.setSectionExpanded(true)

        let nativeRelaunch = ChargeProtectionManager(
            defaults: nativeSuite,
            logger: DiagnosticLogger(directory: root.appendingPathComponent("logs-native-relaunch")),
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0),
            configurationDirectory: root.appendingPathComponent("config-native")
        )
        #expect(nativeRelaunch.isSectionExpanded)

        let intelSuiteName = "dbhv-tests-intel-\(UUID().uuidString)"
        let intelSuite = try #require(UserDefaults(suiteName: intelSuiteName))
        defer { intelSuite.removePersistentDomain(forName: intelSuiteName) }
        let intel = ChargeProtectionManager(
            defaults: intelSuite,
            logger: DiagnosticLogger(directory: root.appendingPathComponent("logs-intel")),
            isAppleSilicon: false,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 0),
            configurationDirectory: root.appendingPathComponent("config-intel")
        )
        #expect(!intel.isSectionExpanded)
    }

    @Test @MainActor
    func testSystemPreferredRequiresConfirmationBeforeSoftwareManagedMode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "dbhv-tests-mode-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ChargeProtectionManager(
            defaults: defaults,
            logger: DiagnosticLogger(directory: root.appendingPathComponent("logs")),
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 2),
            configurationDirectory: root.appendingPathComponent("config")
        )

        #expect(manager.availability == .systemPreferred)
        #expect(!manager.configuration.enabled)
        manager.beginSoftwareModePreparation()
        manager.completeSoftwareModePreparation()
        #expect(manager.availability == .systemPreferred)
        manager.hasConfirmedSystemPreparation = true
        manager.completeSoftwareModePreparation()
        #expect(manager.availability == .softwareManaged)
        #expect(manager.configuration.managementMode == .softwareManaged)
        #expect(!manager.configuration.enabled)

        manager.setLimit(.ninety)
        manager.switchToSystemPreferred(openSettings: false)
        #expect(manager.availability == .systemPreferred)
        #expect(manager.configuration.managementMode == .systemPreferred)
        #expect(!manager.configuration.enabled)
        #expect(manager.configuration.fixedLimit == .ninety)
    }

    @Test @MainActor
    func testUpgradeAcrossNativeLimitBoundaryStopsControlAndPromptsOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "dbhv-tests-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: ChargeProtectionManager.lastNativeLimitBoundaryDefaultsKey)
        let configDirectory = root.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configURL = configDirectory.appendingPathComponent("configuration.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ChargeProtectionConfiguration(
            enabled: true,
            fixedLimit: .eightyFive,
            managementMode: .softwareAvailable
        )).write(to: configURL)

        let manager = ChargeProtectionManager(
            defaults: defaults,
            logger: DiagnosticLogger(directory: root.appendingPathComponent("logs")),
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0),
            configurationDirectory: configDirectory
        )
        #expect(manager.showsUpgradeMigrationPrompt)
        #expect(manager.availability == .systemPreferred)
        #expect(!manager.configuration.enabled)
        #expect(manager.configuration.fixedLimit == .eightyFive)
        #expect(manager.configuration.managementMode == .systemPreferred)

        let relaunched = ChargeProtectionManager(
            defaults: defaults,
            logger: DiagnosticLogger(directory: root.appendingPathComponent("logs-relaunch")),
            isAppleSilicon: true,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0),
            configurationDirectory: configDirectory
        )
        #expect(!relaunched.showsUpgradeMigrationPrompt)
        #expect(relaunched.availability == .systemPreferred)
    }

    @Test
    func testHelperPolicyRequiresExplicitSoftwareManagementOnNativeLimitSystems() {
        let nativeOS = OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        let legacyOS = OperatingSystemVersion(majorVersion: 26, minorVersion: 3, patchVersion: 9)
        let available = ChargeProtectionConfiguration(enabled: true, managementMode: .softwareAvailable)
        let managed = ChargeProtectionConfiguration(enabled: true, managementMode: .softwareManaged)
        let disabled = ChargeProtectionConfiguration(enabled: false, managementMode: .softwareManaged)
        #expect(ChargeProtectionAvailability.helperMayControl(isAppleSilicon: true, operatingSystemVersion: legacyOS, configuration: available))
        #expect(!ChargeProtectionAvailability.helperMayControl(isAppleSilicon: true, operatingSystemVersion: nativeOS, configuration: available))
        #expect(ChargeProtectionAvailability.helperMayControl(isAppleSilicon: true, operatingSystemVersion: nativeOS, configuration: managed))
        #expect(!ChargeProtectionAvailability.helperMayControl(isAppleSilicon: true, operatingSystemVersion: nativeOS, configuration: disabled))
        #expect(!ChargeProtectionAvailability.helperMayControl(isAppleSilicon: false, operatingSystemVersion: legacyOS, configuration: managed))
    }

    @MainActor
    @Test
    func testChargeProtectionStatusItemUsesStateImagesAndVersionedPlacement() {
        let image = ChargeLimitAgentStatusItemController.reachedLimitImage()
        #expect(image != nil)
        #expect(image?.isTemplate == true)
        #expect(image?.size == NSSize(width: 24, height: 16))
        let bitmap = image?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        let visiblePixelCount = (0..<(bitmap?.pixelsHigh ?? 0)).reduce(0) { count, y in
            count + (0..<(bitmap?.pixelsWide ?? 0)).filter { x in
                (bitmap?.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
            }.count
        }
        #expect(visiblePixelCount > 100)
        // The E design is a complete framed battery rather than a partially
        // filled charge gauge, so its silhouette must touch neither side.
        if let bitmap {
            let leftEdge = (0..<bitmap.pixelsHigh).filter {
                (bitmap.colorAt(x: 0, y: $0)?.alphaComponent ?? 0) > 0.05
            }
            let rightEdge = (0..<bitmap.pixelsHigh).filter {
                (bitmap.colorAt(x: bitmap.pixelsWide - 1, y: $0)?.alphaComponent ?? 0) > 0.05
            }
            #expect(leftEdge.isEmpty)
            #expect(rightEdge.isEmpty)
        }
        #expect(!ChargeLimitAgentStatusItemController.statusItemAutosaveName.isEmpty)
        #expect(
            ChargeLimitAgentStatusItemController.statusItemAutosaveName !=
                ChargeLimitAgentStatusItemController.legacyStatusItemAutosaveName
        )
        for state in [
            ChargeLimitAgentPresentationState.protectionActive,
            .limitReached,
            .temporaryFullCharge,
            .attentionRequired
        ] {
            let stateImage = ChargeLimitAgentStatusItemController.statusItemImage(for: state)
            #expect(stateImage != nil)
            #expect(stateImage?.isTemplate == true)
            #expect(stateImage?.tiffRepresentation == image?.tiffRepresentation)
        }
        #expect(ChargeLimitAgentStatusItemController.recoveryInterval == 2)
        #expect(ChargeLimitAgentStatusItemController.fadeDuration > 0)
        #expect(ChargeLimitAgentStatusItemController.fadeDuration < 0.5)
        #expect(ChargeLimitAgentStatusItemController.fadeFrameCount > 1)
        #expect(ChargeLimitAgentStatusItemController.buttonAvailabilityRetryLimit >= 10)
        #expect(
            ChargeLimitAgentStatusItemController.preferredPositionDefaultsKey.contains(
                ChargeLimitAgentStatusItemController.statusItemAutosaveName
            )
        )
        #expect(
            ChargeLimitAgentStatusItemController.rememberedPreferredPositionDefaultsKey.contains(
                ChargeLimitAgentStatusItemController.statusItemAutosaveName
            )
        )
        #expect(ChargeLimitAgentStatusItemController.fallbackPreferredPosition == 350)
        #expect(ChargeLimitAgentStatusItemController.safePreferredPosition(for: nil) == 350)
    }

    @MainActor
    @Test
    func testEnabledProtectionKeepsMenuBarStatusItemVisibleWithoutReachedStatus() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbhv-agent-persistent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ChargeLimitAgentModel(
            configurationDirectory: root,
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 15,
                minorVersion: 7,
                patchVersion: 6
            )
        )
        #expect(!model.shouldShowStatusItem)
        model.selectDisplayedLimit(85)
        #expect(model.configuration.enabled)
        #expect(model.shouldShowStatusItem)
        model.setMenuBarStatusVisible(false)
        #expect(!model.shouldShowStatusItem)
    }

    @Test
    func testChargeLimitAgentPresentationStateTracksProtectionState() {
        let configuration = ChargeProtectionConfiguration(
            enabled: true,
            fixedLimit: .eighty
        )
        #expect(
            ChargeLimitAgentPresentationState.resolve(
                configuration: configuration,
                status: nil
            ) == .protectionActive
        )
        let holding = ChargeProtectionStatus(
            helperVersion: "test",
            installed: true,
            enabled: true,
            fixedLimit: .eighty,
            temporaryFullCharge: false,
            holding: true,
            adapterConnected: true,
            batteryPercentage: 80,
            controlMethod: .powerUIOptimized80
        )
        #expect(
            ChargeLimitAgentPresentationState.resolve(
                configuration: configuration,
                status: holding
            ) == .limitReached
        )
        var temporaryFull = configuration
        temporaryFull.temporaryFullCharge = true
        #expect(
            ChargeLimitAgentPresentationState.resolve(
                configuration: temporaryFull,
                status: holding
            ) == .temporaryFullCharge
        )
        var failed = holding
        failed.lastError = "test error"
        #expect(
            ChargeLimitAgentPresentationState.resolve(
                configuration: configuration,
                status: failed
            ) == .attentionRequired
        )
    }

    @Test
    func testChargeHelperKeepsKnownGoodControlOrdering() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helperURL = macosRoot.appendingPathComponent("Sources/DriveBatteryChargeHelper/main.swift")
        let source = try String(contentsOf: helperURL, encoding: .utf8)
        #expect(source.contains("private let helperVersion = \"1.1.0.14\""))
        #expect(!source.contains("st_mode & S_IFLNK"))
        let markerStart = try #require(source.range(of: "private struct PowerUIOwnershipMarker: Codable"))
        let markerEnd = try #require(source.range(of: "private func readBattery()", range: markerStart.upperBound..<source.endIndex))
        let markerBody = source[markerStart.lowerBound..<markerEnd.lowerBound]
        #expect(!markerBody.contains("createdAt"))
        #expect(source.contains("output[resultOffset] == kOK"))
        #expect(source.contains("return true"))
        #expect(source.contains("private let hasCHTE"))
        #expect(source.contains("private let hasCHIE"))
        #expect(source.contains("static func writeLegacyCommand"))
        #expect(source.contains("private static func keyInfoSizeWithRetry"))
        #expect(source.contains("Self.keyInfoSizeWithRetry(\"CHTE\", expectedSize: 4)"))
        #expect(source.contains("Self.keyInfoSizeWithRetry(\"CH0B\", expectedSize: 1)"))
        #expect(source.contains("Self.keyInfoSizeWithRetry(\"CH0C\", expectedSize: 1)"))
        #expect(source.contains("Self.keyInfoSizeWithRetry(\"CHIE\", expectedSize: 1)"))

        #expect(source.contains("DBHVPowerUIEngageEighty"))
        #expect(source.contains("powerui-owner.json"))
        let holdStart = try #require(source.range(of: "func holdCharging(at batteryPercentage: Int) -> Bool"))
        let holdEnd = try #require(source.range(of: "func isHoldApplied() -> Bool", range: holdStart.upperBound..<source.endIndex))
        let holdBody = source[holdStart.lowerBound..<holdEnd.lowerBound]
        #expect(holdBody.contains("case .chte: return SMC.write(\"CHTE\", value: chteHold)"))
        #expect(holdBody.contains("case .legacyCH0BCH0C:"))
        #expect(holdBody.contains("SMC.writeLegacyCommand(\"CH0B\", value: legacyHold)"))
        #expect(holdBody.contains("SMC.writeLegacyCommand(\"CH0C\", value: legacyHold)"))
        #expect(!holdBody.contains("SMC.write(\"CHIE\", value: chieConnect)"))
    }

    @Test
    func testChargeLimitAgentInstallerUsesCurrentUserLaunchAgentWithoutRoot() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = macosRoot.appendingPathComponent("Resources/ChargeProtection/install-charge-limit-agent.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(script.contains("${HOME}/Library/LaunchAgents"))
        #expect(script.contains("gui/${uid}"))
        #expect(script.contains("KeepAlive bool true"))
        #expect(script.contains("source.sha256"))
        #expect(script.contains("source_fingerprint"))
        #expect(!script.contains("cmp -s"))
        #expect(script.contains("DriveBatteryChargeLimitAgent.app"))
        #expect(script.contains("LSUIElement bool true"))
        #expect(script.contains("pkill -TERM -f -u"))
        #expect(script.contains("pkill -KILL -f -u"))
        #expect(!script.contains("pkill -x -u"))
        #expect(script.contains("running_count"))
        #expect(script.contains("legacy_running_count"))
        #expect(script.contains("The menu-bar agent did not start cleanly."))
        #expect(script.contains("/bin/rm -rf \"${installation_directory}\""))
        #expect(script.contains("The menu-bar charge Agent could not be removed completely."))
        #expect(!script.contains("launchctl kickstart -k"))
        let unloadIndex = try #require(script.range(of: "        unload\n"))
        let removalIndex = try #require(script.range(of: "/bin/rm -rf \"${agent_app}\""))
        #expect(unloadIndex.lowerBound < removalIndex.lowerBound)
        #expect(!script.contains("sudo"))
        #expect(!script.contains("0777"))
        #expect(!script.contains("0666"))
        let syntax = try SystemCommandRunner(timeout: 5).run("/bin/sh", arguments: ["-n", scriptURL.path])
        #expect(syntax.status == 0)
    }

    @Test
    func testChargeLimitAgentCreatesStatusItemOnlyAfterAppKitLaunch() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: macosRoot.appendingPathComponent("Sources/DriveBatteryChargeLimitAgent/main.swift"),
            encoding: .utf8
        )
        let launchBody = try #require(
            source.range(of: "func applicationDidFinishLaunching")
        )
        let controllerCreation = try #require(
            source.range(of: "ChargeLimitAgentStatusItemController(model: model)")
        )
        #expect(controllerCreation.lowerBound > launchBody.lowerBound)
        #expect(source.contains("application.delegate = delegate"))
        #expect(source.contains("application.finishLaunching()"))
        #expect(source.contains("delegate.startStatusItemIfNeeded()"))
        #expect(source.contains("guard model == nil, statusItemController == nil else { return }"))
        #expect(source.contains("flock(opened, LOCK_EX | LOCK_NB)"))

        let controllerSource = try String(
            contentsOf: macosRoot.appendingPathComponent("Sources/DriveBatteryChargeLimitAgent/StatusItemController.swift"),
            encoding: .utf8
        )
        let visible = try #require(controllerSource.range(of: "item.isVisible = true"))
        let configure = try #require(
            controllerSource.range(of: "configureButtonIfAvailable()", range: visible.upperBound..<controllerSource.endIndex)
        )
        #expect(configure.lowerBound > visible.lowerBound)
        #expect(controllerSource.contains("NSApp.activate(ignoringOtherApps: true)"))
        #expect(controllerSource.contains("view.window?.makeKey()"))
        #expect(controllerSource.contains("override func acceptsFirstMouse"))
        #expect(controllerSource.contains("created.autosaveName = Self.statusItemAutosaveName"))
        #expect(controllerSource.contains("screen.auxiliaryTopRightArea"))
        #expect(controllerSource.contains("recoverFromObscuredSafeAreaIfNeeded"))
        #expect(controllerSource.contains("defaults.object(forKey: Self.preferredPositionDefaultsKey) == nil"))
        #expect(controllerSource.contains("removeStatusItemForDisabledProtection"))
        #expect(controllerSource.contains("rememberCurrentPreferredPosition"))
        #expect(!controllerSource.contains("item.isVisible = false"))
        #expect(!controllerSource.contains("defaults.set(0.0"))

        let mainViewsSource = try String(
            contentsOf: macosRoot.appendingPathComponent("Sources/DriveBatteryHealthViewer/Views.swift"),
            encoding: .utf8
        )
        #expect(mainViewsSource.contains(".frame(maxWidth: .infinity, minHeight: 34)"))
        #expect(mainViewsSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(!mainViewsSource.contains(".allowsHitTesting(!manager.isPowerUIEightyOnly)"))
        #expect(!mainViewsSource.contains("optionLabel(percentage)\n                                .allowsHitTesting(false)"))
        #expect(mainViewsSource.contains("nextSelectableIndex(after:"))
        #expect(mainViewsSource.contains("presentedIndex = Double(selectedIndex)"))
        #expect(!mainViewsSource.contains("NSViewRepresentable"))
        #expect(!mainViewsSource.contains(".onTapGesture { select(index: index) }"))

        let agentViewsSource = try String(
            contentsOf: macosRoot.appendingPathComponent("Sources/DriveBatteryChargeLimitAgent/AgentViews.swift"),
            encoding: .utf8
        )
        #expect(agentViewsSource.contains(".frame(maxWidth: .infinity, minHeight: 34)"))
        #expect(!agentViewsSource.contains(".allowsHitTesting(!model.isPowerUIEightyOnly)"))
        #expect(!agentViewsSource.contains("optionLabel(percentage)\n                                .allowsHitTesting(false)"))
        #expect(agentViewsSource.contains("nextSelectableIndex(after:"))
        #expect(agentViewsSource.contains("presentedIndex = Double(selectedIndex)"))
        #expect(!agentViewsSource.contains("NSViewRepresentable"))
        #expect(!agentViewsSource.contains(".onTapGesture { settle(on: index) }"))
    }

    @MainActor
    @Test
    func testChargeLimitAgentWritesOnlyValidatedPrivateConfiguration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbhv-agent-config-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ChargeLimitAgentModel(
            configurationDirectory: root,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 6)
        )
        model.selectDisplayedLimit(90)
        let file = root.appendingPathComponent("configuration.json")
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configuration = try decoder.decode(ChargeProtectionConfiguration.self, from: data)
        #expect(configuration.enabled)
        #expect(configuration.fixedLimit == .ninety)
        let mode = try #require(
            (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]) as? NSNumber
        )
        #expect(mode.intValue & 0o777 == 0o600)
    }

    @Test
    func testLegacyChargeConfigurationDefaultsMenuBarStatusToVisible() throws {
        let legacy = """
        {
          "schema": 1,
          "enabled": true,
          "fixedLimit": 85,
          "temporaryFullCharge": false,
          "updatedAt": "2026-08-13T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configuration = try decoder.decode(
            ChargeProtectionConfiguration.self,
            from: Data(legacy.utf8)
        )
        #expect(configuration.showMenuBarStatus)
    }

    @MainActor
    @Test
    func testHiddenMenuBarPreferenceSuppressesReachedStatusItem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbhv-agent-hidden-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ChargeLimitAgentModel(
            configurationDirectory: root,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 6)
        )
        model.selectDisplayedLimit(85)
        model.setMenuBarStatusVisible(false)
        #expect(!model.configuration.showMenuBarStatus)
        #expect(!model.shouldShowStatusItem)
    }

    @MainActor
    @Test
    func testMacOS158AgentOffersNativeEightyOrNormalHundred() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbhv-agent-158-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ChargeLimitAgentModel(
            configurationDirectory: root,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 8, patchVersion: 0)
        )
        #expect(model.isPowerUIEightyOnly)
        #expect(model.isLimitSelectable(80))
        #expect(!model.isLimitSelectable(85))
        #expect(model.isLimitSelectable(100))
        model.selectDisplayedLimit(95)
        #expect(model.configuration.fixedLimit == .eighty)
        model.selectDisplayedLimit(100)
        #expect(!model.configuration.enabled)
        #expect(model.configuration.fixedLimit == .oneHundred)
        #expect(model.displayedLimitPercentage == 100)
        model.selectDisplayedLimit(80)
        #expect(model.configuration.enabled)
        #expect(model.configuration.fixedLimit == .eighty)
        #expect(model.displayedLimitPercentage == 80)
        let shortNotice = AgentL10n.text("only80", language: .simplifiedChinese)
        #expect(!shortNotice.contains("\n"))
        #expect(shortNotice.count < 32)
    }

    @MainActor
    @Test
    func testAgentMatchesNativeSystemPreferredAndSoftwareManagedPolicies() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbhv-agent-native-policy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nativeVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)

        let systemPreferred = ChargeLimitAgentModel(
            configurationDirectory: root.appendingPathComponent("system"),
            operatingSystemVersion: nativeVersion
        )
        #expect(systemPreferred.availability == .systemPreferred)
        #expect(!systemPreferred.shouldShowStatusItem)
        #expect(!systemPreferred.isLimitSelectable(80))
        systemPreferred.selectDisplayedLimit(85)
        systemPreferred.setMenuBarStatusVisible(false)
        #expect(!systemPreferred.configuration.enabled)
        #expect(systemPreferred.configuration.fixedLimit == .eighty)
        #expect(systemPreferred.configuration.showMenuBarStatus)

        let managedDirectory = root.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let managedConfiguration = ChargeProtectionConfiguration(
            managementMode: .softwareManaged
        )
        try encoder.encode(managedConfiguration).write(
            to: managedDirectory.appendingPathComponent("configuration.json"),
            options: .atomic
        )
        let softwareManaged = ChargeLimitAgentModel(
            configurationDirectory: managedDirectory,
            operatingSystemVersion: nativeVersion
        )
        #expect(softwareManaged.availability == .softwareManaged)
        #expect(softwareManaged.isLimitSelectable(85))
        softwareManaged.selectDisplayedLimit(85)
        #expect(softwareManaged.configuration.enabled)
        #expect(softwareManaged.configuration.fixedLimit == .eightyFive)
    }

    @Test
    func testOverviewExportUsesDownloadStyleSymbol() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: macosRoot.appendingPathComponent("Sources/DriveBatteryHealthViewer/Views.swift"),
            encoding: .utf8
        )
        #expect(source.contains("Label(model.t(\"exportReport\"), systemImage: \"square.and.arrow.down\")"))
        #expect(source.contains("DesktopMacEmptyCard()"))
        #expect(source.contains("desktopMacEmptyStateAnimationShown"))
        #expect(source.contains("Image(systemName: \"powerplug.fill\")"))
        #expect(source.contains("ChargeHelperUninstallButton(manager:"))
        #expect(source.contains("model.t(\"uninstallChargeHelperConfirm\")"))
        #expect(source.contains("model.t(\"chargeHelperAuthorizationTitle\")"))
        #expect(source.contains("model.t(\"chargeHelperInstallAuthorizationMessage\")"))
        #expect(source.contains("model.t(\"chargeHelperUninstallAuthorizationMessage\")"))
    }

    @Test
    func testChargeHelperInstallerCreatesAValidPlistRootAndRollsBackFailure() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = macosRoot.appendingPathComponent("Resources/ChargeProtection/install-charge-helper.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(script.contains("/usr/bin/plutil -create xml1"))
        #expect(!script.contains("PlistBuddy -c 'Clear dict'"))
        #expect(script.contains("cleanup_install"))
        #expect(script.contains("restore_charging"))
        #expect(script.contains("restore_charging \"${fallback_config_path}\" \"${fallback_owner_uid}\""))
        #expect(script.contains("${state_directory}/powerui-owner.json"))
        #expect(script.contains("The charge helper launchd job is still registered."))
        #expect(script.contains("The charge helper could not be removed completely."))
        #expect(script.contains("launchctl bootout system/\"${identifier}\""))
        #expect(script.contains("rm -f \"${plist_destination}\" \"${helper_destination}\""))
        #expect(script.contains("cmp -s \"${helper_source}\" \"${helper_destination}\""))
        #expect(script.contains("launchctl print system/\"${identifier}\""))
        let syntax = try SystemCommandRunner(timeout: 5).run("/bin/sh", arguments: ["-n", scriptURL.path])
        #expect(syntax.status == 0)
    }

    @Test
    func testAdministratorCommandPreservesUnicodeSpacesAndQuotes() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let command = ChargeProtectionManager.administratorCommand(
            script: "/tmp/充电保护/install helper.sh",
            arguments: ["install", "/tmp/应用程序/Helper's Tool", "501"]
        )
        let output = try SystemCommandRunner(timeout: 5).run(
            "/bin/sh",
            arguments: ["-c", "set -- \(command); printf '%s\\n' \"$@\""]
        )
        #expect(output.status == 0)
        #expect(String(data: output.data, encoding: .utf8) == """
        /tmp/充电保护/install helper.sh
        install
        /tmp/应用程序/Helper's Tool
        501

        """)

        let managerSourceURL = macosRoot
            .appendingPathComponent("Sources/DriveBatteryHealthViewer/ChargeProtectionManager.swift")
        let managerSource = try String(contentsOf: managerSourceURL, encoding: .utf8)
        // The privileged AppleScript now receives one pre-built argument and
        // never performs the locale-sensitive argv list slicing that produced
        // error -1708 on a Chinese system.
        #expect(!managerSource.contains("items 2 thru"))
        #expect(!managerSource.contains("count argv"))
    }

    @Test
    func testApplicationRemovalCleanupUsesGracePeriodAndRecoversDuringUpdates() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        var monitor = ApplicationRemovalMonitor(graceInterval: 180)
        let firstMissing = monitor.shouldCleanUp(applicationExists: false, now: start)
        let stillMissing = monitor.shouldCleanUp(applicationExists: false, now: start.addingTimeInterval(179))
        let recovered = monitor.shouldCleanUp(applicationExists: true, now: start.addingTimeInterval(180))
        let missingAgain = monitor.shouldCleanUp(applicationExists: false, now: start.addingTimeInterval(181))
        let expired = monitor.shouldCleanUp(applicationExists: false, now: start.addingTimeInterval(361))
        #expect(!firstMissing)
        #expect(!stillMissing)
        #expect(!recovered)
        #expect(!missingAgain)
        #expect(expired)
    }

    @Test
    func testDiagnosticRangeFilteringMergeEmptySourceAndRedaction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let app = root.appendingPathComponent("app", isDirectory: true)
        let helper = root.appendingPathComponent("helper", isDirectory: true)
        let destination = root.appendingPathComponent("diagnostic.log")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
        let base = Date(timeIntervalSince1970: 2_000_000_000)
        let records = [
            DiagnosticLogRecord(timestamp: base.addingTimeInterval(-10), severity: .info, subsystem: DiagnosticLogger.subsystem, category: "hardware", event: "old", message: "too old", source: "APP"),
            DiagnosticLogRecord(timestamp: base.addingTimeInterval(10), severity: .warning, subsystem: DiagnosticLogger.subsystem, category: "smartctl", event: "timeout", message: "query timed out", source: "APP")
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = try records.map { try encoder.encode($0) }.reduce(into: Data()) { data, line in data.append(line); data.append(0x0A) }
        try lines.write(to: app.appendingPathComponent("app.jsonl"))
        let exporter = DiagnosticLogExporter(appDirectory: app, helperDirectory: helper)
        try exporter.export(
            request: DiagnosticExportRequest(start: base, end: base.addingTimeInterval(20)),
            context: DiagnosticExportContext(appVersion: "1.1.0", buildVersion: "8", selectedLanguage: "zh-Hans", helperInstalled: false, protectionEnabled: true, fixedLimit: 80),
            destination: destination,
            now: base.addingTimeInterval(20)
        )
        let output = try String(contentsOf: destination)
        #expect(output.contains("[APP]"))
        #expect(output.contains("query timed out"))
        #expect(!output.contains("too old"))
        #expect(output.contains("No matching helper log entries in the selected period."))
        #expect(output.range(of: "too old") == nil)
        #expect(DiagnosticLogger.redact("/Users/sample/Documents/a serial=SECRET") == "~/Documents/a serial=[REDACTED]")
        #expect(throws: DiagnosticExportValidationError.startAfterEnd) {
            try DiagnosticExportRequest(start: base.addingTimeInterval(2), end: base).validate(now: base.addingTimeInterval(10))
        }
        #expect(throws: DiagnosticExportValidationError.endTooFarInFuture) {
            try DiagnosticExportRequest(start: base, end: base.addingTimeInterval(1)).validate(now: base)
        }

        let unreadableHelper = root.appendingPathComponent("helper-file")
        try Data("not a directory".utf8).write(to: unreadableHelper)
        let fallbackDestination = root.appendingPathComponent("fallback.log")
        try DiagnosticLogExporter(appDirectory: app, helperDirectory: unreadableHelper).export(
            request: DiagnosticExportRequest(start: base, end: base.addingTimeInterval(20)),
            context: DiagnosticExportContext(appVersion: "1.1.0", buildVersion: "8", selectedLanguage: "en", helperInstalled: true, protectionEnabled: true, fixedLimit: 80),
            destination: fallbackDestination,
            now: base.addingTimeInterval(20)
        )
        let fallback = try String(contentsOf: fallbackDestination)
        #expect(fallback.contains("[APP]"))
        #expect(fallback.contains("[CHARGE-HELPER] Log source unavailable"))

        let helperRecord = DiagnosticLogRecord(
            timestamp: base.addingTimeInterval(11), severity: .error,
            subsystem: DiagnosticLogger.subsystem, category: "charge", event: "sample",
            message: "batterySerial=HELPER-SECRET /Users/private/Documents/file", source: "CHARGE-HELPER"
        )
        var helperLine = try encoder.encode(helperRecord)
        helperLine.append(0x0A)
        try helperLine.write(to: helper.appendingPathComponent("charge-helper.jsonl"))
        let redactedDestination = root.appendingPathComponent("redacted-helper.log")
        try exporter.export(
            request: DiagnosticExportRequest(start: base, end: base.addingTimeInterval(20)),
            context: DiagnosticExportContext(appVersion: "1.1.0", buildVersion: "8", selectedLanguage: "en", helperInstalled: true, protectionEnabled: true, fixedLimit: 80),
            destination: redactedDestination,
            now: base.addingTimeInterval(20)
        )
        let redactedOutput = try String(contentsOf: redactedDestination)
        #expect(!redactedOutput.contains("HELPER-SECRET"))
        #expect(!redactedOutput.contains("/Users/private"))
        #expect(redactedOutput.contains("[REDACTED]"))
    }

    @Test
    func testDiagnosticLoggerRotationAndSensitiveSerialRedaction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = root.appendingPathComponent("app-old.jsonl")
        try Data(repeating: 0x41, count: 2_000).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-20 * 86_400)], ofItemAtPath: old.path)
        let logger = DiagnosticLogger(directory: root, retentionDays: 14, maximumBytes: 20 * 1_024 * 1_024, now: { now })
        logger.log(.info, category: "privacy", event: "sample", message: "diskSerial=VERY-SECRET /Users/private/Documents/file")
        logger.flush()
        logger.cleanNow()
        #expect(!FileManager.default.fileExists(atPath: old.path))
        let current = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.pathExtension == "jsonl" }
        let contents = try current.map { try String(contentsOf: $0) } ?? ""
        #expect(!contents.contains("VERY-SECRET"))
        #expect(!contents.contains("/Users/private"))
        #expect(contents.contains("[REDACTED]"))
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
                errorLogEntries: 2,
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
