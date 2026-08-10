import Foundation
import CNVMeSMART
import Darwin

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
    let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        if Task.isCancelled { throw CancellationError() }
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in termination.signal() }
        do {
            try process.run()
        } catch {
            throw ScannerError.commandFailed(error.localizedDescription)
        }

        // Drain both pipes concurrently. Reading one pipe to EOF before the
        // other can deadlock when a command writes enough data to fill both.
        // A child process may also leave a descendant holding a pipe open, so
        // both process waiting and pipe draining have absolute deadlines.
        let outputBuffer = LockedDataBuffer()
        let errorBuffer = LockedDataBuffer()
        let readers = DispatchGroup()
        let outputDrain = BoundedPipeDrain(
            handle: stdout.fileHandleForReading,
            buffer: outputBuffer,
            group: readers
        )
        let errorDrain = BoundedPipeDrain(
            handle: stderr.fileHandleForReading,
            buffer: errorBuffer,
            group: readers
        )
        outputDrain.start()
        errorDrain.start()

        var timedOut = false
        var cancelled = false
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while process.isRunning {
            if Task.isCancelled {
                cancelled = true
                break
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 {
                timedOut = true
                break
            }
            if termination.wait(timeout: .now() + min(0.05, remaining)) == .success { break }
        }
        if timedOut || cancelled {
            process.terminate()
            if termination.wait(timeout: .now() + 1) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = termination.wait(timeout: .now() + 1)
            }
        }
        if readers.wait(timeout: .now() + 0.25) == .timedOut {
            outputDrain.stop()
            errorDrain.stop()
        } else {
            outputDrain.stop()
            errorDrain.stop()
        }
        if !process.isRunning { process.terminationHandler = nil }

        if cancelled { throw CancellationError() }

        var errorText = String(data: errorBuffer.value, encoding: .utf8) ?? ""
        if timedOut {
            let timeoutText = "Command timed out after \(Int(timeout)) seconds"
            errorText = errorText.isEmpty ? timeoutText : "\(errorText)\n\(timeoutText)"
        }
        return CommandOutput(
            data: outputBuffer.value,
            errorText: errorText,
            status: timedOut ? 124 : process.terminationStatus
        )
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}

private final class BoundedPipeDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let buffer: LockedDataBuffer
    private let group: DispatchGroup
    private let lock = NSLock()
    private var finished = false

    init(handle: FileHandle, buffer: LockedDataBuffer, group: DispatchGroup) {
        self.handle = handle
        self.buffer = buffer
        self.group = group
        group.enter()
    }

    func start() {
        handle.readabilityHandler = { [weak self] readable in
            guard let self else { return }
            let data = readable.availableData
            if data.isEmpty {
                self.finish()
            } else {
                self.buffer.append(data)
            }
        }
    }

    func stop() {
        handle.readabilityHandler = nil
        try? handle.close()
        finish()
    }

    private func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        handle.readabilityHandler = nil
        lock.unlock()
        group.leave()
    }
}

struct HardwareScanner: Sendable {
    private let runner: CommandRunning
    private let smartctlPaths: [String]?

    init(runner: CommandRunning = SystemCommandRunner(), smartctlPaths: [String]? = nil) {
        self.runner = runner
        self.smartctlPaths = smartctlPaths
    }

    func scan() async -> HealthSnapshot {
        let task = Task.detached(priority: .userInitiated) {
            scanSynchronously()
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func readLiveHardwareState(driveIdentifiers: [String]) async -> LiveHardwareState {
        let task = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return LiveHardwareState(battery: nil, driveTemperatures: [:]) }
            var driveTemperatures: [String: Double] = [:]
            for identifier in driveIdentifiers {
                guard !Task.isCancelled else { break }
                if let temperature = nativeNVMeSMART(for: identifier)?.temperatureCelsius {
                    driveTemperatures[identifier] = temperature
                }
            }
            guard !Task.isCancelled else { return LiveHardwareState(battery: nil, driveTemperatures: [:]) }
            return LiveHardwareState(
                battery: readBatteryLiveState(),
                driveTemperatures: driveTemperatures
            )
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func scanSynchronously() -> HealthSnapshot {
        if Task.isCancelled { return cancelledSnapshot() }
        var warnings: [String] = []
        let drives: [DriveInfo]
        do {
            drives = try scanDrives()
        } catch is CancellationError {
            return cancelledSnapshot()
        } catch {
            drives = []
            warnings.append("Drive information: \(error.localizedDescription)")
        }

        if Task.isCancelled { return cancelledSnapshot() }
        let batteries: [BatteryInfo]
        do {
            batteries = try scanBatteries()
        } catch is CancellationError {
            return cancelledSnapshot()
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
        if Task.isCancelled { throw CancellationError() }
        let list: Any
        do {
            list = try plistCommand("/usr/sbin/diskutil", ["list", "-plist", "physical"])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("timed out") { throw error }
            // `physical` is unavailable on a few older diskutil variants.
            // The generic list is safe because virtual/non-whole disks are
            // filtered using the detailed `diskutil info` response below.
            list = try plistCommand("/usr/sbin/diskutil", ["list", "-plist"])
        }
        guard let root = list as? [String: Any] else {
            throw ScannerError.invalidData("diskutil returned an unexpected property list")
        }

        guard let items = root["AllDisksAndPartitions"] as? [[String: Any]], !items.isEmpty else {
            throw ScannerError.invalidData("diskutil did not return any physical disks")
        }
        var drives: [DriveInfo] = []
        for item in items {
            if Task.isCancelled { throw CancellationError() }
            guard let identifier = string(item, ["DeviceIdentifier"]), !identifier.isEmpty else { continue }
            guard let info = try plistCommand("/usr/sbin/diskutil", ["info", "-plist", identifier]) as? [String: Any] else {
                throw ScannerError.invalidData("diskutil returned incomplete information for \(identifier)")
            }
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
        if Task.isCancelled { throw CancellationError() }
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
        if Task.isCancelled { throw CancellationError() }
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
        guard !Task.isCancelled else { return drives }
        var profiles: [[String: Any]] = []
        let enrichmentDeadline = Date().addingTimeInterval(28)
        let profilerOutput = try? runner.run(
            "/usr/sbin/system_profiler",
            arguments: storageProfilerArguments
        )
        if let output = profilerOutput,
           output.status == 0,
           let object = try? JSONSerialization.jsonObject(with: output.data) {
            collectProfiles(object, inherited: [:], into: &profiles)
        } else if profilerOutput?.status != 124 {
            // Some macOS releases or hardware combinations reject a combined
            // profiler request when one data type is unavailable. Querying
            // each read-only data type separately recovers the remaining data.
            for dataType in storageProfilerDataTypes {
                guard !Task.isCancelled, Date() < enrichmentDeadline else { break }
                if let output = try? runner.run(
                    "/usr/sbin/system_profiler",
                    arguments: [dataType, "-json", "-detailLevel", "full"]
                ) {
                    if output.status == 124 { break }
                    if output.status == 0,
                       let object = try? JSONSerialization.jsonObject(with: output.data) {
                    collectProfiles(object, inherited: [:], into: &profiles)
                    }
                }
            }
        }

        // Some Macs expose extra model, firmware, serial, or telemetry values
        // only on storage-controller entries in the I/O Registry.
        for className in [
            "IONVMeBlockStorageDevice", "AppleANS3NVMeController", "IONVMeController",
            "IOBlockStorageDevice", "IOUSBMassStorageInterfaceNub",
            "IOSCSIPeripheralDeviceNub", "IOSCSILogicalUnitNub"
        ] {
            guard !Task.isCancelled, Date() < enrichmentDeadline else { break }
            do {
                let object = try plistCommand("/usr/sbin/ioreg", ["-r", "-c", className, "-a"])
                collectProfiles(object, inherited: [:], into: &profiles)
            } catch {
                if error.localizedDescription.localizedCaseInsensitiveContains("timed out") { break }
            }
        }

        let systemValues = drives.map { drive in
            var value = drive
            let exactProfiles = profiles.filter { profileHasExactBSDName($0, drive: drive) }
            let modelProfiles: [[String: Any]]
            if exactProfiles.isEmpty, isUniqueDriveModel(drive, among: drives) {
                modelProfiles = profiles.filter { profileHasExactModel($0, drive: drive) }
            } else {
                modelProfiles = []
            }
            let matches = exactProfiles.isEmpty ? modelProfiles : exactProfiles
            guard !matches.isEmpty else { return value }

            value.model = uniqueProfileString(matches, keys: [
                "model", "Product Name", "USB Product Name", "Media Name",
                "device_model", "device_name", "product_name"
            ]) ?? value.model
            value.serialNumber = uniqueProfileString(matches, keys: [
                "device_serial", "spnvme_serial", "serial_num", "serial_number",
                "Serial Number", "USB Serial Number"
            ]) ?? value.serialNumber
            value.firmware = uniqueProfileString(matches, keys: ["device_revision", "spnvme_revision", "spnvme_apple_firmware_version", "revision", "firmware_revision", "Product Revision Level"])
                ?? value.firmware
            value.smartStatus = uniqueProfileString(matches, keys: ["smart_status", "SMART Status"]) ?? value.smartStatus
            value.temperatureCelsius = matches.lazy.compactMap {
                normalizedTemperature(deepDouble($0, ["temperature", "Temperature", "controller_temperature"]))
            }.first ?? value.temperatureCelsius
            if value.smartStatus != nil { value.healthState = healthState(forSMARTStatus: value.smartStatus) }
            return value
        }
        let nativeValues = enrichWithNativeNVMe(drives: systemValues)
        guard !Task.isCancelled, Date() < enrichmentDeadline else { return nativeValues }
        return enrichWithSmartctl(drives: nativeValues)
    }

    private func enrichWithNativeNVMe(drives: [DriveInfo]) -> [DriveInfo] {
        drives.map { drive in
            guard !Task.isCancelled else { return drive }
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
            value.healthState = combinedDriveHealthState(
                smartState: value.healthState,
                lifeRemainingPercent: value.lifeRemainingPercent
            )
            return value
        }
    }

    private func enrichWithSmartctl(drives: [DriveInfo]) -> [DriveInfo] {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/smartctl").path
        let legacyBundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/smartctl").path
        let paths = smartctlPaths ?? [bundled, legacyBundled, "/opt/homebrew/sbin/smartctl", "/opt/homebrew/bin/smartctl", "/usr/local/sbin/smartctl", "/usr/local/bin/smartctl", "/opt/local/sbin/smartctl", "/opt/local/bin/smartctl"]
        guard let executable = paths.first(where: { path in
            guard FileManager.default.isExecutableFile(atPath: path),
                  let output = try? runner.run(path, arguments: ["--version"]) else { return false }
            return output.status == 0
        }) else { return drives }

        let smartctlStartedAt = Date()
        return drives.map { drive in
            guard !Task.isCancelled,
                  Date().timeIntervalSince(smartctlStartedAt) < 40 else { return drive }
            let devicePath = "/dev/\(drive.deviceIdentifier)"
            // On Darwin, stock smartctl has no generic SCSI transport. SAT and
            // SNT bridge modes therefore cannot be made functional merely by
            // supplying `-d`; probing them only adds delays and misleading
            // confidence. Automatic mode still works for devices exposed by
            // macOS directly (including systems with a compatible SAT driver).
            var bestObject: Any?
            var bestScore = 0
            let startedAt = Date()
            for type: String? in [nil] {
                if Task.isCancelled || Date().timeIntervalSince(startedAt) >= 18 { break }
                var arguments = ["-a", "-j"]
                if let type { arguments.append(contentsOf: ["-d", type]) }
                arguments.append(devicePath)
                guard let output = try? runner.run(executable, arguments: arguments),
                      !output.data.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: output.data) else { continue }
                let score = smartctlPayloadScore(object)
                if score > bestScore {
                    bestScore = score
                    bestObject = object
                }
                if score >= 7 { break }
            }

            guard bestScore > 0, let bestObject else { return drive }
            return applyingSmartctl(bestObject, to: drive)
        }
    }

    private func applyingSmartctl(_ object: Any, to drive: DriveInfo) -> DriveInfo {
        var value = drive
        value.model = deepString(object, ["model_name", "model_family", "product"]) ?? value.model
        value.serialNumber = deepString(object, ["serial_number"]) ?? value.serialNumber
        value.firmware = deepString(object, ["firmware_version", "scsi_revision"]) ?? value.firmware
        if value.capacityBytes == 0 {
            value.capacityBytes = deepUInt64(deepValue(object, ["user_capacity"]), ["bytes"]) ?? 0
        }
        if let rotationRate = deepUInt64(object, ["rotation_rate"]) {
            value.isSolidState = rotationRate == 0
        }

        let smartStatus = deepValue(object, ["smart_status"])
        if let passed = deepBool(smartStatus, ["passed"]) {
            value.smartStatus = passed ? "Verified" : "Failing"
            value.healthState = passed ? .good : .critical
        }

        let temperature = deepValue(object, ["temperature"])
            ?? deepValue(object, ["scsi_temperature"])
        value.temperatureCelsius = normalizedTemperature(deepDouble(temperature, ["current"]))
            ?? value.temperatureCelsius

        let powerOnTime = deepValue(object, ["power_on_time"])
        value.powerOnHours = deepUInt64(powerOnTime, ["hours"]) ?? value.powerOnHours
        let nvme = deepValue(object, ["nvme_smart_health_information_log"]) ?? object
        let scsiCycles = deepValue(object, ["scsi_start_stop_cycle_counter"])
        value.powerCycles = deepUInt64(object, ["power_cycle_count", "power_cycles"])
            ?? deepUInt64(nvme, ["power_cycle_count", "power_cycles"])
            ?? deepUInt64(scsiCycles, ["accumulated_start_stop_cycles"])
            ?? value.powerCycles
        if let used = deepDouble(nvme, ["percentage_used"])
            ?? directDouble(deepValue(object, ["scsi_percentage_used_endurance_indicator"])) {
            value.lifeRemainingPercent = max(0, min(100, 100 - used))
        }
        if let units = deepUInt64(nvme, ["data_units_read"]) {
            value.bytesRead = nvmeDataUnitsToBytes(units) ?? value.bytesRead
        }
        if let units = deepUInt64(nvme, ["data_units_written"]) {
            value.bytesWritten = nvmeDataUnitsToBytes(units) ?? value.bytesWritten
        }
        value.unsafeShutdowns = deepUInt64(nvme, ["unsafe_shutdowns"]) ?? value.unsafeShutdowns
        value.mediaErrors = deepUInt64(nvme, ["media_errors"]) ?? value.mediaErrors

        // ATA raw values are vendor-defined. They are a last-resort fallback
        // and must never overwrite smartctl's normalized top-level fields.
        if value.powerOnHours == nil,
           let attribute = ataSMARTAttribute(object, names: ["Power_On_Hours", "Power_On_Hours_and_Msec"]) {
            value.powerOnHours = ataRawUInt64(attribute)
        }
        if value.powerCycles == nil,
           let attribute = ataSMARTAttribute(object, names: ["Power_Cycle_Count"]) {
            value.powerCycles = ataRawUInt64(attribute)
        }
        if value.temperatureCelsius == nil,
           let attribute = ataSMARTAttribute(object, names: ["Temperature_Celsius", "Airflow_Temperature_Cel", "Temperature_Internal"]) {
            value.temperatureCelsius = normalizedTemperature(ataRawDouble(attribute))
        }
        if value.unsafeShutdowns == nil,
           let attribute = ataSMARTAttribute(object, names: ["Unsafe_Shutdown_Count", "Unexpected_Power_Loss_Ct"]) {
            value.unsafeShutdowns = ataRawUInt64(attribute)
        }
        if value.lifeRemainingPercent == nil,
           let attribute = ataSMARTAttribute(object, names: ["Percent_Lifetime_Remain", "Media_Wearout_Indicator"]),
           let remaining = ataNormalizedValue(attribute) {
            value.lifeRemainingPercent = max(0, min(100, remaining))
        }
        value.healthState = combinedDriveHealthState(
            smartState: value.healthState,
            lifeRemainingPercent: value.lifeRemainingPercent
        )
        return value
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

    private func profileHasExactBSDName(_ profile: [String: Any], drive: DriveInfo) -> Bool {
        let names = ["bsd_name", "BSD Name", "device_identifier", "IOBSDName"]
            .compactMap { deepString(profile, [$0]) }
            .compactMap(wholeDiskIdentifier)
        return names.contains(drive.deviceIdentifier.lowercased())
    }

    private func profileHasExactModel(_ profile: [String: Any], drive: DriveInfo) -> Bool {
        guard let model = normalizedHardwareString(drive.model),
              model != normalizedHardwareString(drive.deviceIdentifier) else { return false }
        let candidates = [
            "model", "Product Name", "USB Product Name", "Media Name",
            "device_model", "device_name", "product_name"
        ].compactMap { deepString(profile, [$0]).flatMap(normalizedHardwareString) }
        return candidates.contains(model)
    }

    private func isUniqueDriveModel(_ drive: DriveInfo, among drives: [DriveInfo]) -> Bool {
        guard let model = normalizedHardwareString(drive.model) else { return false }
        return drives.filter { normalizedHardwareString($0.model) == model }.count == 1
    }

    private func cancelledSnapshot() -> HealthSnapshot {
        HealthSnapshot(
            computerName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            drives: [],
            batteries: [],
            warnings: []
        )
    }
}

private let storageProfilerDataTypes = [
    "SPNVMeDataType", "SPSerialATADataType", "SPUSBDataType",
    "SPThunderboltDataType", "SPStorageDataType"
]

private let storageProfilerArguments = [
    storageProfilerDataTypes[0], storageProfilerDataTypes[1], storageProfilerDataTypes[2],
    storageProfilerDataTypes[3], storageProfilerDataTypes[4], "-json", "-detailLevel", "full"
]

private func wholeDiskIdentifier(_ value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let range = normalized.range(of: #"^disk[0-9]+"#, options: .regularExpression) else { return nil }
    return String(normalized[range])
}

private func normalizedHardwareString(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value
        .replacingOccurrences(of: "\0", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return normalized.isEmpty ? nil : normalized
}

private func uniqueProfileString(_ profiles: [[String: Any]], keys: [String]) -> String? {
    var values: [(normalized: String, original: String)] = []
    for profile in profiles {
        guard let value = deepString(profile, keys),
              let normalized = normalizedHardwareString(value),
              !values.contains(where: { $0.normalized == normalized }) else { continue }
        values.append((normalized, value))
    }
    return values.count == 1 ? values[0].original : nil
}

private func smartctlPayloadScore(_ object: Any) -> Int {
    var score = 0
    if deepString(object, ["model_name", "model_family", "product"]) != nil { score += 1 }
    if deepString(object, ["serial_number"]) != nil { score += 1 }
    if deepString(object, ["firmware_version", "scsi_revision"]) != nil { score += 1 }
    if deepBool(deepValue(object, ["smart_status"]), ["passed"]) != nil { score += 4 }
    if deepDouble(deepValue(object, ["temperature", "scsi_temperature"]), ["current"]) != nil { score += 2 }
    if deepUInt64(deepValue(object, ["power_on_time"]), ["hours"]) != nil { score += 2 }
    if deepValue(object, ["nvme_smart_health_information_log"]) != nil { score += 5 }
    if deepValue(object, ["ata_smart_attributes"]) != nil { score += 5 }
    if deepValue(object, ["scsi_start_stop_cycle_counter", "scsi_percentage_used_endurance_indicator"]) != nil { score += 3 }
    return score
}

private func directDouble(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let text = value as? String {
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }
    return nil
}

private func ataSMARTAttribute(_ root: Any, names: Set<String>) -> [String: Any]? {
    guard let table = deepValue(root, ["ata_smart_attributes"]).flatMap({ deepValue($0, ["table"]) }) as? [[String: Any]] else {
        return nil
    }
    return table.first { attribute in
        guard let name = deepString(attribute, ["name"]) else { return false }
        return names.contains(name)
    }
}

private func ataRawUInt64(_ attribute: [String: Any]) -> UInt64? {
    guard let raw = deepValue(attribute, ["raw"]) else { return nil }
    return deepUInt64(raw, ["value"])
}

private func ataRawDouble(_ attribute: [String: Any]) -> Double? {
    guard let raw = deepValue(attribute, ["raw"]) else { return nil }
    return deepDouble(raw, ["value"])
}

private func ataNormalizedValue(_ attribute: [String: Any]) -> Double? {
    guard let value = deepDouble(attribute, ["value"]), (0...100).contains(value) else { return nil }
    return value
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
    guard let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !status.isEmpty else { return .unknown }
    if status.contains("fail") || status.contains("fatal") || status == "not ok" || status == "not verified" {
        return .critical
    }
    if status.contains("warn") { return .warning }
    if ["verified", "good", "ok", "passed"].contains(status) { return .good }
    return .unknown
}

func healthState(forPercent percent: Double?) -> HealthState {
    guard let percent else { return .unknown }
    if percent >= 80 { return .good }
    return .warning
}

private func combinedDriveHealthState(
    smartState: HealthState,
    lifeRemainingPercent: Double?
) -> HealthState {
    if smartState == .critical { return .critical }
    guard let lifeRemainingPercent else { return smartState }
    if lifeRemainingPercent <= 10 { return .critical }
    if lifeRemainingPercent < 80 { return .warning }
    if smartState == .warning { return .warning }
    return smartState == .unknown ? .good : smartState
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
    if let data = value as? Data {
        let decoded = String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded?.isEmpty == false ? decoded : nil
    }
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
