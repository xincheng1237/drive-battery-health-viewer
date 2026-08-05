import Foundation
import CNVMeSMART

enum ScannerError: LocalizedError {
    case commandFailed(String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message), .invalidData(let message): return message
        }
    }
}

struct CommandOutput: Sendable {
    let data: Data
    let errorText: String
    let status: Int32
}

protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> CommandOutput
}

struct SystemCommandRunner: CommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw ScannerError.commandFailed(error.localizedDescription)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandOutput(
            data: data,
            errorText: String(data: errorData, encoding: .utf8) ?? "",
            status: process.terminationStatus
        )
    }
}

struct HardwareScanner: Sendable {
    private let runner: CommandRunning

    init(runner: CommandRunning = SystemCommandRunner()) {
        self.runner = runner
    }

    func scan() async -> HealthSnapshot {
        await Task.detached(priority: .userInitiated) {
            scanSynchronously()
        }.value
    }

    func readLiveHardwareState(driveIdentifiers: [String]) async -> LiveHardwareState {
        await Task.detached(priority: .utility) {
            var driveTemperatures: [String: Double] = [:]
            for identifier in driveIdentifiers {
                if let temperature = nativeNVMeSMART(for: identifier)?.temperatureCelsius {
                    driveTemperatures[identifier] = temperature
                }
            }
            return LiveHardwareState(
                battery: readBatteryLiveState(),
                driveTemperatures: driveTemperatures
            )
        }.value
    }

    func scanSynchronously() -> HealthSnapshot {
        var warnings: [String] = []
        let drives: [DriveInfo]
        do {
            drives = try scanDrives()
        } catch {
            drives = []
            warnings.append("Drive information: \(error.localizedDescription)")
        }

        let batteries: [BatteryInfo]
        do {
            batteries = try scanBatteries()
        } catch {
            batteries = []
            // Desktop Macs legitimately have no battery. Only surface a real command error.
            if !error.localizedDescription.localizedCaseInsensitiveContains("no battery") {
                warnings.append("Battery information: \(error.localizedDescription)")
            }
        }

        return HealthSnapshot(
            computerName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            drives: drives,
            batteries: batteries,
            warnings: warnings
        )
    }

    func scanDrives() throws -> [DriveInfo] {
        let list = try plistCommand("/usr/sbin/diskutil", ["list", "-plist", "physical"])
        guard let root = list as? [String: Any] else {
            throw ScannerError.invalidData("diskutil returned an unexpected property list")
        }

        let items = root["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        var drives: [DriveInfo] = []
        for item in items {
            guard let identifier = string(item, ["DeviceIdentifier"]), !identifier.isEmpty else { continue }
            guard let info = try? plistCommand("/usr/sbin/diskutil", ["info", "-plist", identifier]) as? [String: Any] else { continue }
            if let whole = bool(info, ["Whole"]), !whole { continue }
            if string(info, ["VirtualOrPhysical"])?.lowercased() == "virtual" { continue }

            let status = string(info, ["SMARTStatus", "SMART Status"])
            drives.append(DriveInfo(
                deviceIdentifier: identifier,
                model: string(info, ["MediaName", "IORegistryEntryName", "DeviceModel"]) ?? identifier,
                // Disk/volume UUIDs are not hardware serial numbers. Only use a
                // real device serial if system_profiler supplies one below.
                serialNumber: nil,
                firmware: nil,
                protocolName: string(info, ["BusProtocol", "Protocol"]),
                capacityBytes: uint64(info, ["TotalSize", "DiskSize"]) ?? uint64(item, ["Size"]) ?? 0,
                smartStatus: status,
                healthState: healthState(forSMARTStatus: status),
                lifeRemainingPercent: nil,
                temperatureCelsius: nil,
                powerOnHours: nil,
                powerCycles: nil,
                bytesRead: nil,
                bytesWritten: nil,
                unsafeShutdowns: nil,
                mediaErrors: nil,
                isSolidState: bool(info, ["SolidState"]),
                isInternal: bool(info, ["Internal"]),
                notes: []
            ))
        }

        return enrich(drives: drives)
    }

    func scanBatteries() throws -> [BatteryInfo] {
        let plist = try plistCommand("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery", "-a"])
        let powerProfile = powerProfile()
        let entries: [[String: Any]]
        if let array = plist as? [[String: Any]] {
            entries = array
        } else if let dictionary = plist as? [String: Any] {
            entries = [dictionary]
        } else {
            throw ScannerError.invalidData("no battery")
        }

        return entries.compactMap { entry in
            let design = deepInt(entry, ["DesignCapacity"])
            let full = deepInt(entry, ["AppleRawMaxCapacity", "NominalChargeCapacity", "MaxCapacity"])
            let capacityRatio = design.flatMap { designValue -> Double? in
                guard designValue > 0, let full else { return nil }
                return min(100, max(0, Double(full) * 100 / Double(designValue)))
            }
            // System Settings uses macOS's calibrated maximum-capacity value,
            // which can differ from a simple raw-capacity ratio.
            let reportedHealth = deepPercent(powerProfile, [
                "sppower_battery_health_maximum_capacity",
                "sppower_battery_maximum_capacity",
                "maximum_capacity"
            ])
            let health = reportedHealth ?? capacityRatio
            let temperature = deepInt(entry, ["Temperature", "VirtualTemperature"]).flatMap { raw -> Double? in
                guard raw > 0 else { return nil }
                // AppleSmartBattery reports this field in hundredths of a degree Celsius.
                let celsius = Double(raw) / 100
                return (-30...120).contains(celsius) ? celsius : nil
            }
            let name = deepString(entry, ["DeviceName", "BatterySerialNumber", "Serial"])
                ?? deepString(powerProfile, ["sppower_battery_device_name", "device_name"])
                ?? "Mac Battery"
            let manufacturer = deepString(entry, ["Manufacturer", "PackManufacturer", "CellManufacturer"])
                ?? deepString(powerProfile, ["sppower_battery_manufacturer", "manufacturer"])
                ?? batteryManufacturerCode(entry)
            let reportedType = deepString(entry, ["Chemistry", "BatteryType", "BatteryChemistry", "PackType"])
                ?? deepString(powerProfile, ["sppower_battery_type", "battery_type", "chemistry"])
            let chemistry = reportedType.flatMap { meaningfulBatteryType($0) } ?? "InternalBattery"
            let currentPercent = normalizedPercent(
                deepInt(entry, ["StateOfCharge", "CurrentCapacity"])
                    ?? deepInt(powerProfile, ["sppower_battery_state_of_charge"])
            )
            let voltage = deepInt(entry, ["AppleRawBatteryVoltage", "Voltage"])
            let designVoltage = deepInt(entry, ["DesignVoltage", "NominalVoltage"])
                ?? inferredBatteryDesignVoltage(entry)
            let permanentFailure = (deepInt(entry, ["PermanentFailureStatus"]) ?? 0) != 0
            return BatteryInfo(
                name: name,
                manufacturer: manufacturer,
                serialNumber: deepString(entry, ["BatterySerialNumber", "Serial"])
                    ?? deepString(powerProfile, ["sppower_battery_serial_number", "serial_number"]),
                chemistry: chemistry,
                designCapacityMAh: design,
                fullChargeCapacityMAh: full,
                currentCapacityPercent: currentPercent,
                cycleCount: deepInt(entry, ["CycleCount"])
                    ?? deepInt(powerProfile, ["sppower_battery_cycle_count", "cycle_count"]),
                healthPercent: health,
                capacityRatioPercent: capacityRatio,
                voltageMillivolts: voltage,
                designVoltageMillivolts: designVoltage,
                temperatureCelsius: temperature,
                isCharging: deepBool(entry, ["IsCharging"]),
                externalConnected: deepBool(entry, ["ExternalConnected", "AppleRawExternalConnected"])
                    ?? deepBool(powerProfile, ["sppower_battery_charger_connected"]),
                healthState: permanentFailure ? .critical : healthState(forPercent: health),
                notes: []
            )
        }
    }

    private func powerProfile() -> Any? {
        guard let output = try? runner.run(
            "/usr/sbin/system_profiler",
            arguments: ["SPPowerDataType", "-json", "-detailLevel", "full"]
        ), output.status == 0, !output.data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: output.data)
    }

    private func plistCommand(_ executable: String, _ arguments: [String]) throws -> Any {
        let output = try runner.run(executable, arguments: arguments)
        guard output.status == 0, !output.data.isEmpty else {
            let message = output.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScannerError.commandFailed(message.isEmpty ? "\(URL(fileURLWithPath: executable).lastPathComponent) failed" : message)
        }
        do {
            return try PropertyListSerialization.propertyList(from: output.data, options: [], format: nil)
        } catch {
            throw ScannerError.invalidData(error.localizedDescription)
        }
    }

    private func enrich(drives: [DriveInfo]) -> [DriveInfo] {
        var profiles: [[String: Any]] = []
        if let output = try? runner.run(
            "/usr/sbin/system_profiler",
            arguments: ["SPNVMeDataType", "SPSerialATADataType", "-json", "-detailLevel", "full"]
        ), output.status == 0, let object = try? JSONSerialization.jsonObject(with: output.data) {
            collectProfiles(object, inherited: [:], into: &profiles)
        }

        // Some Macs expose extra model, firmware, serial, or telemetry values
        // only on storage-controller entries in the I/O Registry.
        for className in ["IONVMeBlockStorageDevice", "AppleANS3NVMeController", "IONVMeController", "IOBlockStorageDevice"] {
            if let object = try? plistCommand("/usr/sbin/ioreg", ["-r", "-c", className, "-a"]) {
                collectProfiles(object, inherited: [:], into: &profiles)
            }
        }

        let systemValues = drives.map { drive in
            var value = drive
            guard let profile = profiles.max(by: {
                profileMatchScore($0, drive: drive) < profileMatchScore($1, drive: drive)
            }), profileMatchScore(profile, drive: drive) > 0 else { return value }
            value.model = deepString(profile, ["model", "Product Name", "_name", "device_model"]) ?? value.model
            value.serialNumber = deepString(profile, ["device_serial", "spnvme_serial", "serial_num", "serial_number", "Serial Number"]) ?? value.serialNumber
            value.firmware = deepString(profile, ["device_revision", "spnvme_revision", "spnvme_apple_firmware_version", "revision", "firmware_revision", "Product Revision Level"])
                ?? value.firmware
            value.smartStatus = deepString(profile, ["smart_status", "SMART Status"]) ?? value.smartStatus
            value.temperatureCelsius = normalizedTemperature(deepDouble(profile, ["temperature", "Temperature", "controller_temperature"]))
            value.healthState = healthState(forSMARTStatus: value.smartStatus)
            return value
        }
        return enrichWithSmartctl(drives: enrichWithNativeNVMe(drives: systemValues))
    }

    private func enrichWithNativeNVMe(drives: [DriveInfo]) -> [DriveInfo] {
        drives.map { drive in
            guard let metrics = nativeNVMeSMART(for: drive.deviceIdentifier) else { return drive }
            var value = drive
            value.smartStatus = metrics.criticalWarning == 0 ? "Verified" : "Warning"
            value.healthState = metrics.criticalWarning == 0 ? .good : .warning
            value.lifeRemainingPercent = max(0, min(100, 100 - Double(metrics.percentageUsed)))
            value.temperatureCelsius = metrics.temperatureCelsius ?? value.temperatureCelsius
            value.powerOnHours = metrics.powerOnHours
            value.powerCycles = metrics.powerCycles
            value.bytesRead = nvmeDataUnitsToBytes(metrics.dataUnitsRead)
            value.bytesWritten = nvmeDataUnitsToBytes(metrics.dataUnitsWritten)
            value.unsafeShutdowns = metrics.unsafeShutdowns
            value.mediaErrors = metrics.mediaErrors
            return value
        }
    }

    private func enrichWithSmartctl(drives: [DriveInfo]) -> [DriveInfo] {
        let paths = ["/opt/homebrew/sbin/smartctl", "/opt/homebrew/bin/smartctl", "/usr/local/sbin/smartctl", "/usr/local/bin/smartctl", "/opt/local/sbin/smartctl", "/opt/local/bin/smartctl"]
        guard let executable = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return drives }
        return drives.map { drive in
            guard let output = try? runner.run(executable, arguments: ["-a", "-j", "/dev/\(drive.deviceIdentifier)"]),
                  !output.data.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: output.data) else { return drive }
            var value = drive
            value.model = deepString(object, ["model_name", "model_family"]) ?? value.model
            value.serialNumber = deepString(object, ["serial_number"]) ?? value.serialNumber
            value.firmware = deepString(object, ["firmware_version"]) ?? value.firmware
            let smartStatus = deepValue(object, ["smart_status"])
            if let passed = deepBool(smartStatus, ["passed"]) {
                value.smartStatus = passed ? "Verified" : "Failing"
                value.healthState = passed ? .good : .critical
            }
            let temperature = deepValue(object, ["temperature"])
            value.temperatureCelsius = normalizedTemperature(deepDouble(temperature, ["current"])) ?? value.temperatureCelsius
            let powerOnTime = deepValue(object, ["power_on_time"])
            value.powerOnHours = deepUInt64(powerOnTime, ["hours"]) ?? value.powerOnHours
            let nvme = deepValue(object, ["nvme_smart_health_information_log"]) ?? object
            value.powerCycles = deepUInt64(nvme, ["power_cycle_count", "power_cycles"]) ?? value.powerCycles
            if let used = deepDouble(nvme, ["percentage_used"]) {
                value.lifeRemainingPercent = max(0, min(100, 100 - used))
            }
            if let units = deepUInt64(nvme, ["data_units_read"]) {
                value.bytesRead = units.multipliedReportingOverflow(by: 512_000).overflow ? nil : units * 512_000
            }
            if let units = deepUInt64(nvme, ["data_units_written"]) {
                value.bytesWritten = units.multipliedReportingOverflow(by: 512_000).overflow ? nil : units * 512_000
            }
            value.unsafeShutdowns = deepUInt64(nvme, ["unsafe_shutdowns"]) ?? value.unsafeShutdowns
            value.mediaErrors = deepUInt64(nvme, ["media_errors"]) ?? value.mediaErrors
            return value
        }
    }

    private func collectProfiles(_ value: Any, inherited: [String: Any], into profiles: inout [[String: Any]]) {
        if let dictionary = value as? [String: Any] {
            var merged = inherited
            for (key, item) in dictionary where key != "_items" {
                if !(item is [Any]) && !(item is [String: Any]) {
                    merged[key] = item
                }
            }
            if deepString(merged, ["_name", "bsd_name", "device_identifier", "Product Name", "model"]) != nil {
                profiles.append(merged)
            }
            for item in dictionary.values {
                if item is [[String: Any]] || item is [String: Any] {
                    collectProfiles(item, inherited: merged, into: &profiles)
                }
            }
        } else if let array = value as? [Any] {
            for item in array { collectProfiles(item, inherited: inherited, into: &profiles) }
        }
    }

    private func profileMatchScore(_ profile: [String: Any], drive: DriveInfo) -> Int {
        let candidates = ["_name", "bsd_name", "BSD Name", "device_identifier", "device_name", "device_model", "Product Name", "model"]
            .compactMap { deepString(profile, [$0])?.lowercased() }
        if candidates.contains(drive.deviceIdentifier.lowercased()) { return 100 }
        let model = drive.model.lowercased()
        guard !model.isEmpty else { return 0 }
        if candidates.contains(model) { return 80 }
        return candidates.contains(where: { $0.contains(model) || model.contains($0) }) ? 40 : 0
    }
}

struct BatteryLiveState: Sendable, Equatable {
    let chargePercent: Int
    let isCharging: Bool
    let externalConnected: Bool
    let temperatureCelsius: Double?
}

struct LiveHardwareState: Sendable, Equatable {
    let battery: BatteryLiveState?
    let driveTemperatures: [String: Double]
}

func readBatteryLiveState() -> BatteryLiveState? {
    var raw = DBHVBatteryLiveStatus(
        chargePercent: 0,
        isCharging: 0,
        externalConnected: 0,
        temperatureCentiCelsius: -1
    )
    guard DBHVReadBatteryLiveStatus(&raw) == 1 else { return nil }
    let temperature = Double(raw.temperatureCentiCelsius) / 100
    return BatteryLiveState(
        chargePercent: min(100, max(0, Int(raw.chargePercent))),
        isCharging: raw.isCharging == 1,
        externalConnected: raw.externalConnected == 1,
        temperatureCelsius: (-30...120).contains(temperature) ? temperature : nil
    )
}

struct NativeNVMeSMART: Sendable, Equatable {
    let criticalWarning: UInt8
    let percentageUsed: UInt8
    let temperatureCelsius: Double?
    let dataUnitsRead: UInt64
    let dataUnitsWritten: UInt64
    let powerCycles: UInt64
    let powerOnHours: UInt64
    let unsafeShutdowns: UInt64
    let mediaErrors: UInt64
}

func nativeNVMeSMART(for bsdName: String) -> NativeNVMeSMART? {
    var raw = DBHVNVMeSMARTData(
        criticalWarning: 0,
        percentageUsed: 0,
        temperatureKelvin: 0,
        dataUnitsRead: 0,
        dataUnitsWritten: 0,
        powerCycles: 0,
        powerOnHours: 0,
        unsafeShutdowns: 0,
        mediaErrors: 0
    )
    let succeeded = bsdName.withCString { DBHVReadNVMeSMART($0, &raw) }
    guard succeeded == 1 else { return nil }
    let temperature = raw.temperatureKelvin > 0 ? Double(raw.temperatureKelvin) - 273.15 : nil
    return NativeNVMeSMART(
        criticalWarning: raw.criticalWarning,
        percentageUsed: raw.percentageUsed,
        temperatureCelsius: temperature.flatMap { (-30...150).contains($0) ? $0 : nil },
        dataUnitsRead: raw.dataUnitsRead,
        dataUnitsWritten: raw.dataUnitsWritten,
        powerCycles: raw.powerCycles,
        powerOnHours: raw.powerOnHours,
        unsafeShutdowns: raw.unsafeShutdowns,
        mediaErrors: raw.mediaErrors
    )
}

private func nvmeDataUnitsToBytes(_ units: UInt64) -> UInt64? {
    let value = units.multipliedReportingOverflow(by: 512_000)
    return value.overflow ? nil : value.partialValue
}

func healthState(forSMARTStatus status: String?) -> HealthState {
    guard let status = status?.lowercased() else { return .unknown }
    if status.contains("verified") || status.contains("good") || status.contains("ok") { return .good }
    if status.contains("fail") || status.contains("fatal") { return .critical }
    if status.contains("warn") { return .warning }
    return .unknown
}

func healthState(forPercent percent: Double?) -> HealthState {
    guard let percent else { return .unknown }
    if percent >= 80 { return .good }
    return .warning
}

private func string(_ dictionary: [String: Any], _ keys: [String]) -> String? {
    for key in keys {
        if let value = dictionary[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        if let value = dictionary[key] as? NSNumber { return value.stringValue }
    }
    return nil
}

private func int(_ dictionary: [String: Any], _ keys: [String]) -> Int? {
    for key in keys {
        if let value = dictionary[key] as? NSNumber { return value.intValue }
        if let value = dictionary[key] as? String, let number = Int(value) { return number }
    }
    return nil
}

private func uint64(_ dictionary: [String: Any], _ keys: [String]) -> UInt64? {
    for key in keys {
        if let value = dictionary[key] as? NSNumber { return value.uint64Value }
        if let value = dictionary[key] as? String, let number = UInt64(value) { return number }
    }
    return nil
}

private func bool(_ dictionary: [String: Any], _ keys: [String]) -> Bool? {
    for key in keys {
        if let value = dictionary[key] as? Bool { return value }
        if let value = dictionary[key] as? NSNumber { return value.boolValue }
        if let value = dictionary[key] as? String {
            if ["yes", "true", "1"].contains(value.lowercased()) { return true }
            if ["no", "false", "0"].contains(value.lowercased()) { return false }
        }
    }
    return nil
}

private func deepValue(_ root: Any?, _ keys: [String]) -> Any? {
    guard let root else { return nil }
    if let dictionary = root as? [String: Any] {
        for wantedKey in keys {
            if let match = dictionary.first(where: { $0.key.caseInsensitiveCompare(wantedKey) == .orderedSame }) {
                return match.value
            }
        }
        for value in dictionary.values {
            if let found = deepValue(value, keys) { return found }
        }
    } else if let array = root as? [Any] {
        for value in array {
            if let found = deepValue(value, keys) { return found }
        }
    }
    return nil
}

private func deepString(_ root: Any?, _ keys: [String]) -> String? {
    guard let value = deepValue(root, keys) else { return nil }
    if let text = value as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

private func deepInt(_ root: Any?, _ keys: [String]) -> Int? {
    guard let value = deepValue(root, keys) else { return nil }
    if let number = value as? NSNumber { return number.intValue }
    if let text = value as? String {
        let normalized = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(normalized)
    }
    return nil
}

private func deepUInt64(_ root: Any?, _ keys: [String]) -> UInt64? {
    guard let value = deepValue(root, keys) else { return nil }
    if let number = value as? NSNumber { return number.uint64Value }
    if let text = value as? String {
        let normalized = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return UInt64(normalized)
    }
    return nil
}

private func deepDouble(_ root: Any?, _ keys: [String]) -> Double? {
    guard let value = deepValue(root, keys) else { return nil }
    if let number = value as? NSNumber { return number.doubleValue }
    if let text = value as? String {
        let normalized = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "")
        let scanner = Scanner(string: normalized.trimmingCharacters(in: .whitespacesAndNewlines))
        return scanner.scanDouble()
    }
    return nil
}

private func deepBool(_ root: Any?, _ keys: [String]) -> Bool? {
    guard let value = deepValue(root, keys) else { return nil }
    if let bool = value as? Bool { return bool }
    if let number = value as? NSNumber { return number.boolValue }
    if let text = value as? String {
        if ["yes", "true", "1", "enabled"].contains(text.lowercased()) { return true }
        if ["no", "false", "0", "disabled"].contains(text.lowercased()) { return false }
    }
    return nil
}

private func deepData(_ root: Any?, _ keys: [String]) -> Data? {
    deepValue(root, keys) as? Data
}

private func deepPercent(_ root: Any?, _ keys: [String]) -> Double? {
    guard let value = deepDouble(root, keys) else { return nil }
    return (0...110).contains(value) ? value : nil
}

private func normalizedPercent(_ value: Int?) -> Int? {
    guard let value, (0...100).contains(value) else { return nil }
    return value
}

private func meaningfulBatteryType(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if ["0", "unknown", "n/a", "not available"].contains(trimmed.lowercased()) { return nil }
    return trimmed
}

private func batteryManufacturerCode(_ root: Any?) -> String? {
    guard let data = deepData(root, ["ManufacturerData", "MfgData"]) else { return nil }
    var tokens: [String] = []
    var bytes: [UInt8] = []

    func finishToken() {
        guard bytes.count >= 2, let token = String(bytes: bytes, encoding: .ascii) else {
            bytes.removeAll(keepingCapacity: true)
            return
        }
        if token.unicodeScalars.contains(where: CharacterSet.letters.contains) {
            tokens.append(token)
        }
        bytes.removeAll(keepingCapacity: true)
    }

    for byte in data {
        if (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) {
            bytes.append(byte)
        } else {
            finishToken()
        }
    }
    finishToken()
    return tokens.last
}

private func inferredBatteryDesignVoltage(_ root: Any?) -> Int? {
    guard let cells = deepValue(root, ["CellVoltage"]) as? [Any], (2...6).contains(cells.count) else {
        return nil
    }
    // Mac battery packs use high-voltage lithium-ion cells with a nominal
    // voltage close to 3.85 V. This value is used only for the explicitly
    // approximate Wh display when firmware omits DesignVoltage.
    return cells.count * 3_850
}

private func normalizedTemperature(_ value: Double?) -> Double? {
    guard let value else { return nil }
    if (-30...150).contains(value) { return value }
    if (240...450).contains(value) { return value - 273.15 }
    if (2_400...4_500).contains(value) { return value / 10 - 273.15 }
    return nil
}
