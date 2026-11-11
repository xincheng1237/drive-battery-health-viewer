// The AppleSMC access pattern and the CHTE/CHIE control strategy in this file
// are adapted from ChargeWatch by TY-teo (MIT License).
// See Resources/ThirdParty/ChargeWatch/LICENSE and NOTICE.
// The legacy CH0B/CH0C compatibility path is an independent implementation
// based on the public SMC key semantics used by pre-Tahoe Apple Silicon Macs.

import ChargeProtectionCore
import CPowerUIBridge
import Darwin
import Foundation
import IOKit
import IOKit.ps

private let helperVersion = "1.1.2.4"
private let statusHeartbeatInterval: TimeInterval = 10

private enum HelperExit: Int32 {
    case success = 0
    case invalidArguments = 2
    case smcUnavailable = 3
    case unsafeConfiguration = 4
}

private enum JSONLineLogger {
    private static let lock = NSLock()
    private static let maximumFileBytes: Int64 = 1 * 1_024 * 1_024
    private static let maximumTotalBytes: Int64 = 4 * 1_024 * 1_024
    private static let retentionInterval: TimeInterval = 14 * 86_400
    static var fileURL: URL?

    private static func safeMessage(_ message: String) -> String {
        var result = message
        if let userPath = try? NSRegularExpression(pattern: #"/Users/[^/\s]+"#) {
            result = userPath.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "~"
            )
        }
        if let serialAssignment = try? NSRegularExpression(
            pattern: #"(?i)\b(serial(?:Number)?|batterySerial|diskSerial)\s*[:=]\s*[^\s,;}]+"#
        ) {
            result = serialAssignment.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1=[REDACTED]"
            )
        }
        return result
    }

    static func write(
        _ severity: String,
        category: String,
        event: String,
        message: String
    ) {
        guard let fileURL else { return }
        let record: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "severity": severity,
            "subsystem": "com.chengxin.drive-battery-health-viewer",
            "category": category,
            "event": event,
            "message": safeMessage(message),
            "source": "CHARGE-HELPER"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              var line = String(data: data, encoding: .utf8)?.data(using: .utf8) else { return }
        line.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0]
                )
            }
            var directoryInfo = stat()
            guard lstat(directory.path, &directoryInfo) == 0,
                  (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
                  directoryInfo.st_uid == 0,
                  directoryInfo.st_mode & 0o022 == 0 else {
                throw CocoaError(.fileWriteNoPermission)
            }
            try rotateAndCleanIfNeeded(fileURL)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0],
                    ofItemAtPath: fileURL.path
                )
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } catch {
            FileHandle.standardError.write(Data("charge helper log failure\n".utf8))
        }
    }

    private static func rotateAndCleanIfNeeded(_ current: URL) throws {
        let manager = FileManager.default
        if let attributes = try? manager.attributesOfItem(atPath: current.path),
           let size = attributes[.size] as? NSNumber,
           size.int64Value >= maximumFileBytes {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let archive = current.deletingLastPathComponent()
                .appendingPathComponent("charge-helper-\(formatter.string(from: Date())).jsonl")
            try manager.moveItem(at: current, to: archive)
        }
        let directory = current.deletingLastPathComponent()
        guard let files = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        var retained: [(URL, Date, Int64)] = []
        for url in files where url.lastPathComponent.hasPrefix("charge-helper") && url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            if url != current && modified < cutoff {
                try? manager.removeItem(at: url)
            } else {
                retained.append((url, modified, Int64(values?.fileSize ?? 0)))
            }
        }
        var total = retained.reduce(Int64(0)) { $0 + $1.2 }
        for file in retained.sorted(by: { $0.1 < $1.1 }) where total > maximumTotalBytes {
            guard file.0 != current else { continue }
            if (try? manager.removeItem(at: file.0)) != nil { total -= file.2 }
        }
    }
}

private enum SMC {
    private static let kOpen: UInt32 = 0
    private static let kYPC: UInt32 = 2
    private static let kRead: UInt8 = 5
    private static let kWrite: UInt8 = 6
    private static let kInfo: UInt8 = 9
    private static let kOK: UInt8 = 0
    private static let size = 80
    private static let keyOffset = 0
    private static let dataSizeOffset = 28
    private static let resultOffset = 40
    private static let selectorOffset = 42
    private static let bytesOffset = 48
    private static var connection: io_connect_t = 0
    private static let lock = NSLock()

    static func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Use the AppleSMC client used by the historical working helper. The
        // charge-control keys are queried through this service connection;
        // AppleSMCKeysEndpoint does not speak this 80-byte transaction format.
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 1, &connection) == KERN_SUCCESS else { return false }
        _ = IOConnectCallMethod(connection, kOpen, nil, 0, nil, 0, nil, nil, nil, nil)
        return true
    }

    static func stop() {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    static func keyInfoSize(_ key: String) -> UInt32? {
        lock.lock()
        defer { lock.unlock() }
        var input = [UInt8](repeating: 0, count: size)
        putUInt32(&input, keyOffset, fourCC(key))
        input[selectorOffset] = kInfo
        guard let output = call(input), output[resultOffset] == kOK else { return nil }
        return getUInt32(output, dataSizeOffset)
    }

    static func read(_ key: String, size requestedSize: UInt32) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        return readUnlocked(key, size: requestedSize)
    }

    @discardableResult
    static func write(_ key: String, value: [UInt8]) -> Bool {
        guard !value.isEmpty, value.count <= 32 else { return false }
        lock.lock()
        defer { lock.unlock() }
        var input = [UInt8](repeating: 0, count: size)
        putUInt32(&input, keyOffset, fourCC(key))
        putUInt32(&input, dataSizeOffset, UInt32(value.count))
        input[selectorOffset] = kWrite
        for (index, byte) in value.enumerated() { input[bytesOffset + index] = byte }
        // The SMC command result is the reliable acknowledgement for charge
        // control. Some firmware does not mirror a successful control command
        // byte-for-byte when it is read back, so read-back must not decide
        // whether a supported method is usable.
        guard let output = call(input), output[resultOffset] == kOK else { return false }
        return true
    }

    /// CH0B/CH0C accept writes on firmware that does not always expose a
    /// dependable immediate read-back. For these legacy keys the successful
    /// AppleSMC command result is the acknowledgement.
    @discardableResult
    static func writeLegacyCommand(_ key: String, value: [UInt8]) -> Bool {
        write(key, value: value)
    }

    private static func readUnlocked(_ key: String, size requestedSize: UInt32) -> [UInt8]? {
        guard requestedSize > 0, requestedSize <= 32 else { return nil }
        var input = [UInt8](repeating: 0, count: size)
        putUInt32(&input, keyOffset, fourCC(key))
        putUInt32(&input, dataSizeOffset, requestedSize)
        input[selectorOffset] = kRead
        guard let output = call(input), output[resultOffset] == kOK else { return nil }
        return Array(output[bytesOffset..<(bytesOffset + Int(requestedSize))])
    }

    private static func call(_ input: [UInt8]) -> [UInt8]? {
        guard connection != 0 else { return nil }
        var output = [UInt8](repeating: 0, count: size)
        var outputSize = size
        let result = input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                IOConnectCallStructMethod(
                    connection,
                    kYPC,
                    inputBytes.baseAddress,
                    size,
                    outputBytes.baseAddress,
                    &outputSize
                )
            }
        }
        return result == KERN_SUCCESS ? output : nil
    }

    private static func fourCC(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func putUInt32(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt32) {
        bytes[offset] = UInt8(value & 0xff)
        bytes[offset + 1] = UInt8((value >> 8) & 0xff)
        bytes[offset + 2] = UInt8((value >> 16) & 0xff)
        bytes[offset + 3] = UInt8((value >> 24) & 0xff)
    }

    private static func getUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }
}

private struct BatteryReading {
    let charge: ChargeBatteryReading
    let isCharging: Bool?
    let systemAdapterConnected: Bool?

    var nativeAdapterConfirmed: Bool {
        charge.adapterConnected && systemAdapterConnected == true
    }
}

private let chargeStateDirectory = URL(
    fileURLWithPath: "/Library/Application Support/DriveBatteryHealthViewer/ChargeProtection",
    isDirectory: true
)

private func readPowerUIOwnershipBaseline() -> PowerUIOwnershipBaseline {
    var status = DBHVPowerUIStatus()
    guard DBHVPowerUIReadStatus(&status) else { return .unknown }
    let gauging = DBHVReadGaugingLimitSuspension()
    if status.temporarily_disabled == 1 || gauging == 1 || status.current_state == 3 {
        return .system
    }
    guard status.temporarily_disabled == 0, gauging == 0 else { return .unknown }
    if status.enabled == 0 && status.current_state == 0 &&
        (status.checkpoint == 0 || status.checkpoint == 10) && status.engaged == 0 {
        return .clean
    }
    if status.enabled == 1 && status.current_state == 1 && status.checkpoint == 5 && status.engaged == 0 {
        return .restoredTopOff
    }
    if status.checkpoint == 10 && status.enabled == 1 { return .system }
    return .other
}

private func isTrustedDirectory(_ url: URL, exactMode: mode_t? = nil) -> Bool {
    var information = stat()
    return lstat(url.path, &information) == 0 && information.st_mode & S_IFMT == S_IFDIR &&
        information.st_uid == 0 && information.st_mode & 0o022 == 0 &&
        (exactMode.map { information.st_gid == 0 && information.st_mode & 0o7777 == $0 } ?? true)
}

private func isTrustedChargeStateDirectory() -> Bool {
    var directory = chargeStateDirectory
    while directory.path != "/" {
        guard isTrustedDirectory(directory) else { return false }
        directory.deleteLastPathComponent()
    }
    return true
}

private func reconcileUpgradeOwnership(_ command: String) throws {
    let upgrade = chargeStateDirectory.appendingPathComponent(".helper-upgrade", isDirectory: true)
    guard isTrustedChargeStateDirectory(), isTrustedDirectory(upgrade, exactMode: 0o700) else {
        throw CocoaError(.fileReadNoPermission)
    }
    let marker = chargeStateDirectory.appendingPathComponent("powerui-owner.json")
    let backup = upgrade.appendingPathComponent("powerui-owner.json")
    try migratePowerUIOwnership(
        marker: marker, backup: backup, preparing: command == "--prepare-upgrade-ownership",
        baseline: readPowerUIOwnershipBaseline
    )
}


private func readBattery() -> BatteryReading? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let values = properties?.takeRetainedValue() as? [String: Any],
          let charge = values["CurrentCapacity"] as? NSNumber else { return nil }
    let fullyCharged = (values["FullyCharged"] as? NSNumber)?.boolValue ?? false
    let adapterConnected: Bool
    if let adapter = SMC.read("AC-W", size: 1)?.first {
        adapterConnected = adapter > 0 && adapter != 0xFF
    } else if let details = values["AdapterDetails"] as? [String: Any],
              let watts = details["Watts"] as? NSNumber {
        adapterConnected = watts.intValue > 0
    } else {
        adapterConnected = (values["ExternalConnected"] as? NSNumber)?.boolValue ?? false
    }
    return BatteryReading(
        charge: ChargeBatteryReading(percentage: charge.intValue, fullyCharged: fullyCharged, adapterConnected: adapterConnected),
        isCharging: (values["IsCharging"] as? NSNumber)?.boolValue,
        systemAdapterConnected: ((values["AppleRawExternalConnected"] ?? values["ExternalConnected"]) as? NSNumber)?.boolValue
    )
}

/// Check the adapter again at the bridge's write boundary. This is independent
/// of the reported battery percentage, which can be unavailable.
private func powerUIExternalPowerConfirmed() -> Bool {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return false }
    defer { IOObjectRelease(service) }
    func read(_ key: String) -> Bool? {
        (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.boolValue
    }
    guard (read("AppleRawExternalConnected") ?? read("ExternalConnected")) == true else { return false }
    if let adapter = SMC.read("AC-W", size: 1)?.first { return adapter > 0 && adapter != 0xFF }
    guard let sources = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let type = IOPSGetProvidingPowerSourceType(sources)?.takeUnretainedValue() else { return false }
    return type as String == kIOPSACPowerValue
}

private final class ChargeActuator {
    private let chteAllow: [UInt8] = [0, 0, 0, 0]
    private let chteHold: [UInt8] = [1, 0, 0, 0]
    private let legacyAllow: [UInt8] = [0]
    private let legacyHold: [UInt8] = [0x02]
    private let chieConnect: [UInt8] = [0]
    private let chieDisconnect: [UInt8] = [0x08]
    private let hasCHTE: Bool
    private let hasCH0B: Bool
    private let hasCH0C: Bool
    private let hasLegacyPair: Bool
    private let hasCHIE: Bool
    private let powerUIOwnershipURL: URL
    private var legacyHoldCommanded = false
    private let powerUIActuation = NSRecursiveLock()
    private var ownershipPersistenceFailed = false
    let method: ChargeControlMethod

    init(preferPowerUIEighty: Bool, powerUIOwnershipURL: URL) {
        self.powerUIOwnershipURL = powerUIOwnershipURL
        // The known-good helper selected CHTE from key metadata with a short
        // retry window. Requiring a read/write/read-back round trip here is
        // too strict: a valid charge-control key may be write-capable without
        // returning a byte-for-byte mirror of its command. On pre-Tahoe
        // firmware the equivalent adapter-preserving path is CH0B + CH0C.
        let chteSize = Self.keyInfoSizeWithRetry("CHTE", expectedSize: 4)
        let ch0bSize = Self.keyInfoSizeWithRetry("CH0B", expectedSize: 1)
        let ch0cSize = Self.keyInfoSizeWithRetry("CH0C", expectedSize: 1)
        let chieSize = Self.keyInfoSizeWithRetry("CHIE", expectedSize: 1)

        hasCHTE = chteSize == 4
        hasCH0B = ch0bSize == 1
        hasCH0C = ch0cSize == 1
        hasLegacyPair = hasCH0B && hasCH0C
        hasCHIE = chieSize == 1
        if preferPowerUIEighty {
            // This platform is native-80-only. A missing private interface
            // must not turn system maintenance into forced SMC limiting.
            method = DBHVPowerUIOpen() ? .powerUIOptimized80 : .unavailable
        } else {
            method = preferredChargeControlMethod(
                chteSupported: hasCHTE,
                legacyCH0BCH0CSupported: hasLegacyPair,
                chieSupported: hasCHIE
            )
        }

        func describe(_ size: UInt32?) -> String {
            size.map(String.init) ?? "unreadable"
        }
        JSONLineLogger.write(
            "info",
            category: "charge",
            event: "control_probe",
            message: "Control probe: PowerUI80=\(preferPowerUIEighty), CHTE=\(describe(chteSize)), CH0B=\(describe(ch0bSize)), CH0C=\(describe(ch0cSize)), CHIE=\(describe(chieSize)); selected=\(method.rawValue)."
        )
    }

    private func readPowerUIOwnership() -> ChargeProtectionCore.PowerUIOwnershipMarker? {
        switch inspectPowerUIOwnershipFile(at: powerUIOwnershipURL, requireRoot: true) {
        case .owned(let marker):
            return marker
        case .unowned, .corrupted:
            return nil
        }
    }

    private func hasPowerUIOwnership() -> Bool {
        hasOwnedPowerUIState
    }

    var hasOwnedPowerUIState: Bool {
        guard method == .powerUIOptimized80 else { return false }
        powerUIActuation.lock()
        defer { powerUIActuation.unlock() }
        guard !ownershipPersistenceFailed else { return false }
        switch inspectPowerUIOwnershipFile(at: powerUIOwnershipURL, requireRoot: true) {
        case .owned(let marker):
            return marker.leaseState == .activeEighty
        case .unowned, .corrupted:
            return false
        }
    }

    private func writePowerUIOwnership(
        batteryPercentage: Int,
        leaseState: PowerUIOwnershipLeaseState = .activeEighty
    ) -> Bool {
        guard (0...100).contains(batteryPercentage) else { return false }
        do {
            try PowerUIOwnershipStore.write(PowerUIOwnershipMarker(
                leaseState: leaseState, lastKnownBatteryPercentage: batteryPercentage
            ), to: powerUIOwnershipURL)
            return true
        } catch {
            JSONLineLogger.write("error", category: "charge", event: "ownership_write_failed",
                                 message: "Could not persist \(leaseState.rawValue) ownership: \(error)")
            return false
        }
    }

    private func removePowerUIOwnership() -> Bool {
        do {
            try PowerUIOwnershipStore.remove(at: powerUIOwnershipURL)
            return true
        } catch {
            JSONLineLogger.write("error", category: "charge", event: "ownership_remove_failed",
                                 message: "Could not remove the ownership marker: \(error)")
            return false
        }
    }

    private func restorePowerUI(preserveOwnership: Bool) -> Bool {
        switch inspectPowerUIOwnershipFile(at: powerUIOwnershipURL) {
        case .unowned:
            return true
        case .corrupted(let reason):
            JSONLineLogger.write("error", category: "charge", event: "corrupted_ownership_marker",
                                 message: "Cannot restore unverified PowerUI ownership: \(reason)")
            return false
        case .owned(let marker):
            if preserveOwnership && marker.leaseState == .activeEighty { return true }
            let before = readPowerUIOwnershipBaseline()
            switch before {
            case .clean: return removePowerUIOwnership()
            case .system:
                return writePowerUIOwnership(batteryPercentage: marker.lastKnownBatteryPercentage ?? 80,
                                             leaseState: .deferredToSystem)
            case .unknown: return false
            case .restoredTopOff:
                if marker.leaseState == .restoredTopOff { return true }
                guard marker.leaseState == .activeEighty else { return removePowerUIOwnership() }
            case .other:
                guard marker.leaseState == .activeEighty else { return removePowerUIOwnership() }
                guard DBHVPowerUIDisable() else { return false }
            }
            switch readPowerUIOwnershipBaseline() {
            case .clean: return removePowerUIOwnership()
            case .restoredTopOff:
                return writePowerUIOwnership(batteryPercentage: marker.lastKnownBatteryPercentage ?? 80,
                                             leaseState: .restoredTopOff)
            case .system:
                return writePowerUIOwnership(batteryPercentage: marker.lastKnownBatteryPercentage ?? 80,
                                             leaseState: .deferredToSystem)
            case .unknown, .other: return false
            }
        }
    }

    private static func keyInfoSizeWithRetry(_ key: String, expectedSize: UInt32) -> UInt32? {
        var lastSize: UInt32?
        for attempt in 0..<5 {
            if let size = SMC.keyInfoSize(key) {
                lastSize = size
                if size == expectedSize { return size }
                return size
            }
            if attempt < 4 { usleep(100_000) }
        }
        return lastSize
    }

    @discardableResult
    func allowCharging(preserveOwnedPowerUI: Bool = false) -> Bool {
        // The selected adapter-preserving method is authoritative. Other
        // keys are cleaned up on a best-effort basis so a read-only legacy key
        // cannot make an otherwise working CHTE path fail closed.
        var selectedOK: Bool
        switch method {
        case .powerUIOptimized80:
            powerUIActuation.lock()
            defer { powerUIActuation.unlock() }
            selectedOK = restorePowerUI(preserveOwnership: preserveOwnedPowerUI)
        case .chte:
            selectedOK = SMC.write("CHTE", value: chteAllow)
        case .legacyCH0BCH0C:
            let ch0bOK = SMC.writeLegacyCommand("CH0B", value: legacyAllow)
            let ch0cOK = ch0bOK && SMC.writeLegacyCommand("CH0C", value: legacyAllow)
            selectedOK = ch0bOK && ch0cOK
        case .chieFallback:
            selectedOK = SMC.write("CHIE", value: chieConnect)
        case .unavailable:
            selectedOK = true
        }

        if method != .chte, hasCHTE { _ = SMC.write("CHTE", value: chteAllow) }
        if method != .legacyCH0BCH0C, hasCH0B {
            _ = SMC.writeLegacyCommand("CH0B", value: legacyAllow)
        }
        if method != .legacyCH0BCH0C, hasCH0C {
            _ = SMC.writeLegacyCommand("CH0C", value: legacyAllow)
        }
        let chieOK = !hasCHIE || SMC.write("CHIE", value: chieConnect)
        let succeeded = selectedOK && chieOK
        if succeeded { legacyHoldCommanded = false }
        return succeeded
    }

    func powerUIInput(_ battery: BatteryReading) -> PowerUIProtectionCoordinator.Input {
        var status = DBHVPowerUIStatus()
        let readable = DBHVPowerUIReadStatus(&status)
        let gauging = readable ? DBHVReadGaugingLimitSuspension() : -1
        return PowerUIProtectionCoordinator.Input(
            batteryPercentage: battery.charge.percentage,
            isCharging: battery.isCharging,
            adapterConnected: battery.charge.adapterConnected,
            systemAdapterConnected: battery.systemAdapterConnected,
            checkpoint: readable ? status.checkpoint : -1,
            engaged: readable && status.engaged == 1,
            temporarilyDisabled: readable && status.temporarily_disabled == 1,
            calibrationSuspended: gauging == 1,
            hasOwnership: hasPowerUIOwnership(),
            isHoldApplied: readable && status.checkpoint == 2 && status.engaged == 1,
            pauseSignalsKnown: readable && status.engaged >= 0 && status.current_state != 3 &&
                (status.checkpoint != 10 || (status.enabled == 0 && status.current_state == 0)) &&
                status.temporarily_disabled == 0 && gauging == 0,
            powerUIActive: readable && status.enabled == 1 && status.current_state == 1
        )
    }

    func applyPowerUIRequest(_ request: PowerUIRequestSchedule.Request, input: PowerUIProtectionCoordinator.Input) -> Bool {
        powerUIActuation.lock()
        defer { powerUIActuation.unlock() }
        // A real charging mismatch at Checkpoint 2 needs a fresh bridge request,
        // even though the controller's engagement bit is already set.
        if request == .renew || (input.hasOwnership && input.checkpoint == 2 && input.engaged) {
            return hasPowerUIOwnership() &&
                DBHVPowerUIRefreshEighty(Int32(input.batteryPercentage), powerUIExternalPowerConfirmed)
        }
        return holdCharging(at: input.batteryPercentage)
    }

    @discardableResult
    func holdCharging(at batteryPercentage: Int) -> Bool {
        // The startup restore already clears any adapter-isolation state left
        // by an older helper. Holding a real charge-inhibit key must not touch
        // CHIE again: CHIE is the adapter-disconnect mechanism that causes
        // macOS to publish "no external power" and 0 W.
        switch method {
        case .powerUIOptimized80:
            powerUIActuation.lock()
            defer { powerUIActuation.unlock() }
            do {
                let inspection = inspectPowerUIOwnershipFile(at: powerUIOwnershipURL)
                let accepted = try acquirePowerUIOwnership(
                    inspection: inspection,
                    baseline: readPowerUIOwnershipBaseline(),
                    percentage: batteryPercentage,
                    persist: { try PowerUIOwnershipStore.write($0, to: powerUIOwnershipURL) },
                    retire: { try PowerUIOwnershipStore.remove(at: powerUIOwnershipURL) },
                    engage: { DBHVPowerUIEngageEighty(Int32(batteryPercentage), $0, powerUIExternalPowerConfirmed) },
                    restore: { DBHVPowerUIDisable() }
                )
                if accepted { ownershipPersistenceFailed = false }
                return accepted
            } catch {
                ownershipPersistenceFailed = true
                JSONLineLogger.write("error", category: "charge", event: "ownership_transaction_failed",
                                     message: "Could not complete the PowerUI ownership transaction: \(error)")
                return false
            }
        case .chte: return SMC.write("CHTE", value: chteHold)
        case .legacyCH0BCH0C:
            let ch0bOK = SMC.writeLegacyCommand("CH0B", value: legacyHold)
            let ch0cOK = ch0bOK && SMC.writeLegacyCommand("CH0C", value: legacyHold)
            guard ch0bOK && ch0cOK else {
                _ = SMC.writeLegacyCommand("CH0B", value: legacyAllow)
                _ = SMC.writeLegacyCommand("CH0C", value: legacyAllow)
                legacyHoldCommanded = false
                return false
            }
            legacyHoldCommanded = true
            return true
        case .chieFallback: return SMC.write("CHIE", value: chieDisconnect)
        case .unavailable: return false
        }
    }

    func isHoldApplied() -> Bool {
        switch method {
        case .powerUIOptimized80:
            guard hasPowerUIOwnership() else { return false }
            var snapshot = DBHVPowerUIStatus()
            return DBHVPowerUIReadStatus(&snapshot) &&
                snapshot.temporarily_disabled == 0 && DBHVReadGaugingLimitSuspension() == 0 &&
                snapshot.enabled == 1 && snapshot.current_state == 1 && snapshot.checkpoint == 2 && snapshot.engaged == 1
        case .chte: return SMC.read("CHTE", size: 4) == chteHold
        case .legacyCH0BCH0C: return legacyHoldCommanded
        case .chieFallback: return SMC.read("CHIE", size: 1) == chieDisconnect
        case .unavailable: return false
        }
    }

    func systemTemporaryFullChargeObservation() -> Bool? {
        guard method == .powerUIOptimized80 else { return nil }
        var snapshot = DBHVPowerUIStatus()
        guard DBHVPowerUIReadStatus(&snapshot) else { return nil }
        switch snapshot.temporarily_disabled {
        case 1: return true
        case 0: return false
        default: return nil
        }
    }

    func systemCalibrationObservation() -> Bool? {
        guard method == .powerUIOptimized80 else { return nil }
        switch DBHVReadGaugingLimitSuspension() {
        case 1: return true
        case 0: return false
        default: return nil
        }
    }

    /// Keeps an already-owned PowerUI policy alive when AppleSmartBattery
    /// telemetry is temporarily unavailable.
    func maintainPowerUIWithoutBatteryReading() -> (succeeded: Bool, managed: Bool, holding: Bool) {
        guard method == .powerUIOptimized80, hasPowerUIOwnership() else {
            return (false, false, false)
        }
        var snapshot = DBHVPowerUIStatus()
        guard DBHVPowerUIReadStatus(&snapshot),
              snapshot.temporarily_disabled == 0,
              DBHVReadGaugingLimitSuspension() == 0,
              snapshot.enabled == 1,
              snapshot.current_state == 1 else {
            return (false, false, false)
        }
        let holding = snapshot.checkpoint == 2 && snapshot.engaged == 1
        let managed = holding || snapshot.checkpoint == 1
        return (true, managed, holding)
    }
}

private struct HelperArguments {
    let configurationURL: URL
    let statusURL: URL
    let logURL: URL
    let ownerUID: uid_t
    let applicationURL: URL?
    let restoreOnly: Bool

    init?(_ arguments: [String]) {
        var values: [String: String] = [:]
        var restoreOnly = false
        var index = 1
        while index < arguments.count {
            if arguments[index] == "--restore-only" {
                restoreOnly = true
                index += 1
            } else if index + 1 < arguments.count {
                values[arguments[index]] = arguments[index + 1]
                index += 2
            } else {
                return nil
            }
        }
        guard let configuration = values["--config"], configuration.hasPrefix("/Users/"),
              let status = values["--status"], status == chargeStateDirectory.appendingPathComponent("status.json").path,
              let log = values["--log"], log == "/Library/Logs/DriveBatteryHealthViewer/charge-helper.jsonl",
              let ownerText = values["--owner-uid"], let owner = uid_t(ownerText), owner >= 500 else { return nil }
        let application = values["--application"]
        guard restoreOnly || (application?.hasPrefix("/") == true && application?.hasSuffix(".app") == true) else { return nil }
        configurationURL = URL(fileURLWithPath: configuration).standardizedFileURL
        statusURL = URL(fileURLWithPath: status).standardizedFileURL
        logURL = URL(fileURLWithPath: log).standardizedFileURL
        ownerUID = owner
        applicationURL = application.map { URL(fileURLWithPath: $0).standardizedFileURL }
        self.restoreOnly = restoreOnly
    }
}

private enum InstalledComponents {
    static let helperIdentifier = "com.chengxin.drivebatteryhealthviewer.chargehelper"
    static let agentIdentifier = "com.chengxin.drivebatteryhealthviewer.chargelimitagent"
    static let helperURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(helperIdentifier)")
    static let daemonURL = URL(fileURLWithPath: "/Library/LaunchDaemons/\(helperIdentifier).plist")
}

private func verifiedApplicationExists(at url: URL) -> Bool {
    var information = stat()
    guard lstat(url.path, &information) == 0,
          (information.st_mode & S_IFMT) == S_IFDIR else { return false }
    let infoURL = url.appendingPathComponent("Contents/Info.plist")
    guard let dictionary = NSDictionary(contentsOf: infoURL),
          dictionary["CFBundleIdentifier"] as? String == "com.chengxin.drive-battery-health-viewer" else { return false }
    return true
}

@discardableResult
private func runLaunchctl(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch { return 127 }
}

@discardableResult
private func stopAgentProcess(ownerUID: uid_t) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    process.arguments = ["-x", "-u", String(ownerUID), "DriveBatteryChargeLimitAgent"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch { return 127 }
}

private func removeKnownItem(_ url: URL) {
    guard url.path.hasPrefix("/Library/") || url.path.hasPrefix("/Users/") else { return }
    try? FileManager.default.removeItem(at: url)
}

private func cleanUpAfterApplicationRemoval(_ arguments: HelperArguments) -> Never {
    let restored = attemptNormalChargingRestoration()
    JSONLineLogger.write(
        restored ? "warning" : "error",
        category: "charge",
        event: "application_removed_cleanup",
        message: restored
            ? "The application was removed; normal charging was restored and installed components are being removed."
            : "The application was removed; installed components are being removed, but normal charging could not be verified."
    )
    let ownerHome = arguments.configurationURL
        .deletingLastPathComponent() // ChargeProtection
        .deletingLastPathComponent() // DriveBatteryHealthViewer
        .deletingLastPathComponent() // Application Support
        .deletingLastPathComponent() // Library
        .deletingLastPathComponent() // user home
    let agentDirectory = ownerHome.appendingPathComponent(
        "Library/Application Support/DriveBatteryHealthViewer/ChargeLimitAgent",
        isDirectory: true
    )
    let launchAgent = ownerHome.appendingPathComponent(
        "Library/LaunchAgents/\(InstalledComponents.agentIdentifier).plist"
    )
    let appIdentifier = "com.chengxin.drive-battery-health-viewer"
    let userCleanupURLs = [
        ownerHome.appendingPathComponent("Library/Logs/DriveBatteryHealthViewer", isDirectory: true),
        ownerHome.appendingPathComponent("Library/Caches/\(appIdentifier)", isDirectory: true),
        ownerHome.appendingPathComponent("Library/HTTPStorages/\(appIdentifier)", isDirectory: true),
        ownerHome.appendingPathComponent("Library/Saved Application State/\(appIdentifier).savedState", isDirectory: true),
        ownerHome.appendingPathComponent("Library/Preferences/\(appIdentifier).plist")
    ]
    _ = runLaunchctl(["bootout", "gui/\(arguments.ownerUID)/\(InstalledComponents.agentIdentifier)"])
    _ = stopAgentProcess(ownerUID: arguments.ownerUID)
    removeKnownItem(launchAgent)
    removeKnownItem(agentDirectory)
    removeKnownItem(arguments.configurationURL.deletingLastPathComponent())
    for url in userCleanupURLs { removeKnownItem(url) }
    removeKnownItem(arguments.statusURL.deletingLastPathComponent())
    removeKnownItem(arguments.logURL.deletingLastPathComponent())
    removeKnownItem(InstalledComponents.daemonURL)
    removeKnownItem(InstalledComponents.helperURL)
    SMC.stop()
    // Unregister the in-memory launchd job as the final step. Removing only
    // its plist/binary would leave a failed job record until logout/reboot.
    _ = runLaunchctl(["bootout", "system/\(InstalledComponents.helperIdentifier)"])
    exit(HelperExit.success.rawValue)
}

private func secureConfiguration(at url: URL, ownerUID: uid_t) -> ChargeProtectionConfiguration? {
    var information = stat()
    guard lstat(url.path, &information) == 0,
          (information.st_mode & S_IFMT) == S_IFREG,
          information.st_uid == ownerUID,
          information.st_mode & 0o022 == 0,
          let data = try? Data(contentsOf: url),
          let configuration = try? JSONDecoder.chargeProtection.decode(ChargeProtectionConfiguration.self, from: data),
          configuration.isValid else { return nil }
    return configuration
}

private func writeConfiguration(
    _ configuration: ChargeProtectionConfiguration,
    to url: URL,
    ownerUID: uid_t
) -> Bool {
    do {
        let data = try JSONEncoder.chargeProtection.encode(configuration)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".config-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        guard chown(temporary.path, ownerUID, gid_t.max) == 0,
              chmod(temporary.path, 0o600) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            return false
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        return true
    } catch {
        return false
    }
}

private struct StatusSnapshot: Equatable {
    let helperVersion: String
    let installed: Bool
    let enabled: Bool
    let fixedLimit: FixedChargeLimit
    let temporaryFullCharge: Bool
    let configurationUpdatedAt: Date?
    let configurationRevision: UUID?
    let holding: Bool
    let adapterConnected: Bool?
    let batteryPercentage: Int?
    let controlMethod: ChargeControlMethod
    let lastError: String?
    let systemChargeOverride: SystemChargeOverrideState?
    let systemCalibration: SystemCalibrationState?
    let powerUIPolicyConfirmed: Bool?
    /// Keep the adapter observation fresh even when no charge-control state
    /// changes. This status file is tiny and is overwritten atomically; a
    /// ten-second heartbeat avoids both stale UI state and high-frequency I/O.
    let heartbeatBucket: Int

    init(_ status: ChargeProtectionStatus) {
        helperVersion = status.helperVersion
        installed = status.installed
        enabled = status.enabled
        fixedLimit = status.fixedLimit
        temporaryFullCharge = status.temporaryFullCharge
        configurationUpdatedAt = status.configurationUpdatedAt
        configurationRevision = status.configurationRevision
        holding = status.holding
        adapterConnected = status.adapterConnected
        batteryPercentage = status.batteryPercentage
        controlMethod = status.controlMethod
        lastError = status.lastError
        systemChargeOverride = status.systemChargeOverride
        systemCalibration = status.systemCalibration
        powerUIPolicyConfirmed = status.powerUIPolicyConfirmed
        heartbeatBucket = Int(status.timestamp.timeIntervalSince1970 / statusHeartbeatInterval)
    }
}

private func writeStatusIfChanged(
    _ status: ChargeProtectionStatus,
    to url: URL,
    previous: inout StatusSnapshot?
) {
    let snapshot = StatusSnapshot(status)
    guard snapshot != previous else { return }
    do {
        let data = try JSONEncoder.chargeProtection.encode(status)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0],
            ofItemAtPath: url.path
        )
        previous = snapshot
    } catch {
        JSONLineLogger.write("error", category: "charge", event: "status_write_failed", message: "Unable to write helper status.")
    }
}

private extension JSONDecoder {
    static var chargeProtection: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private func writeSystemChargingPauseStatus(
    override: SystemChargeOverrideState?,
    calibration: SystemCalibrationState?,
    configuration: ChargeProtectionConfiguration,
    battery: BatteryReading?,
    to url: URL,
    previous: inout StatusSnapshot?,
    lastReported: inout String?
) {
    let reason: String
    if let calibration, calibration.defersChargeControl {
        reason = "calibration:\(calibration.rawValue)"
    } else {
        reason = "system-full:\(override?.rawValue ?? "unknown")"
    }
    if reason != lastReported {
        JSONLineLogger.write(
            "info", category: "charge", event: "system_charging_pause",
            message: "System charging pause: \(reason); configured limit retained; engagement and renewal deferred."
        )
    }
    lastReported = reason
    writeStatusIfChanged(ChargeProtectionStatus(
        helperVersion: helperVersion,
        installed: true,
        enabled: configuration.enabled,
        fixedLimit: configuration.fixedLimit,
        temporaryFullCharge: configuration.temporaryFullCharge,
        configurationUpdatedAt: configuration.updatedAt,
        configurationRevision: configuration.revision,
        holding: false,
        adapterConnected: battery?.nativeAdapterConfirmed,
        batteryPercentage: battery?.charge.percentage,
        controlMethod: .powerUIOptimized80,
        systemChargeOverride: override,
        systemCalibration: calibration
    ), to: url, previous: &previous)
}

private extension JSONEncoder {
    static var chargeProtection: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

guard geteuid() == 0 else { exit(HelperExit.invalidArguments.rawValue) }
let command = CommandLine.arguments.dropFirst()
if command.count == 1, let operation = command.first,
   operation == "--prepare-upgrade-ownership" || operation == "--reconcile-upgrade-ownership" {
    do {
        try reconcileUpgradeOwnership(operation)
        exit(HelperExit.success.rawValue)
    } catch {
        fputs("PowerUI ownership upgrade validation failed: \(error)\n", stderr)
        exit(HelperExit.smcUnavailable.rawValue)
    }
}
guard isTrustedChargeStateDirectory(),
      let arguments = HelperArguments(CommandLine.arguments) else { exit(HelperExit.invalidArguments.rawValue) }
JSONLineLogger.fileURL = arguments.logURL

#if !arch(arm64)
JSONLineLogger.write("warning", category: "charge", event: "unsupported_architecture", message: "Charge control is unavailable on Intel Mac.")
exit(HelperExit.success.rawValue)
#endif

guard SMC.start() else {
    JSONLineLogger.write("error", category: "charge", event: "smc_open_failed", message: "Unable to open AppleSMC.")
    exit(HelperExit.smcUnavailable.rawValue)
}
private let currentOSVersion = ProcessInfo.processInfo.operatingSystemVersion
private let usesPowerUIEightyPolicy = ChargeLimitCapabilityPolicy.isPowerUIEightyOnly(
    isAppleSilicon: true,
    operatingSystemVersion: currentOSVersion
)
private let powerUIOwnershipURL = arguments.statusURL
    .deletingLastPathComponent()
    .appendingPathComponent("powerui-owner.json")
private let actuator = ChargeActuator(
    preferPowerUIEighty: usesPowerUIEightyPolicy,
    powerUIOwnershipURL: powerUIOwnershipURL
)

private func attemptNormalChargingRestoration(preserveOwnedPowerUI: Bool = false) -> Bool {
    for _ in 0..<3 {
        if actuator.allowCharging(preserveOwnedPowerUI: preserveOwnedPowerUI) {
            let chie = SMC.read("CHIE", size: 1)?.map { String(format: "%02x", $0) }.joined() ?? "unreadable"
            let acw = SMC.read("AC-W", size: 1)?.map { String(format: "%02x", $0) }.joined() ?? "unreadable"
            JSONLineLogger.write(
                "info",
                category: "charge",
                event: "restore_observation",
                message: "Restore acknowledged; CHIE=\(chie), AC-W=\(acw)."
            )
            return true
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    return false
}

private func restoreAndExit(_ code: HelperExit, event: String, message: String) -> Never {
    let restored = attemptNormalChargingRestoration()
    JSONLineLogger.write(restored && code == .success ? "info" : "error", category: "charge", event: event, message: restored ? message : "\(message) Normal charging restoration could not be verified after retries.")
    SMC.stop()
    exit(!restored && code == .success ? HelperExit.smcUnavailable.rawValue : code.rawValue)
}

private func writeTerminalStatus(
    configuration: ChargeProtectionConfiguration,
    error: String?,
    controlMethod: ChargeControlMethod,
    to url: URL,
    previous: inout StatusSnapshot?
) {
    writeStatusIfChanged(ChargeProtectionStatus(
        helperVersion: helperVersion,
        installed: true,
        enabled: false,
        fixedLimit: configuration.fixedLimit,
        temporaryFullCharge: false,
        configurationUpdatedAt: configuration.updatedAt,
        configurationRevision: configuration.revision,
        holding: false,
        adapterConnected: nil,
        batteryPercentage: nil,
        controlMethod: controlMethod,
        lastError: error
    ), to: url, previous: &previous)
}

guard actuator.method != .unavailable else {
    restoreAndExit(.success, event: "control_unavailable", message: "No adapter-preserving PowerUI, CHTE, or CH0B/CH0C control path was detected; charging was restored.")
}
guard let initialConfiguration = secureConfiguration(
    at: arguments.configurationURL,
    ownerUID: arguments.ownerUID
) else {
    restoreAndExit(
        .success,
        event: "invalid_configuration",
        message: "Configuration ownership, permissions, or contents were invalid; charging was restored."
    )
}
let preserveSystemFullCharge = !arguments.restoreOnly && initialConfiguration.enabled &&
    initialConfiguration.fixedLimit == .eighty &&
    (actuator.systemTemporaryFullChargeObservation() == true || actuator.systemCalibrationObservation() == true)
// Keep ownership across an unexpected Helper restart. Restore the legacy
// adapter path as usual, while the loop verifies or replaces the native lease.
let preserveOwnedPowerUI = !arguments.restoreOnly && initialConfiguration.enabled &&
    initialConfiguration.fixedLimit == .eighty && !initialConfiguration.temporaryFullCharge &&
    ChargeProtectionAvailability.helperMayControl(
        isAppleSilicon: true, operatingSystemVersion: currentOSVersion, configuration: initialConfiguration
    ) && actuator.hasOwnedPowerUIState
guard preserveSystemFullCharge || attemptNormalChargingRestoration(preserveOwnedPowerUI: preserveOwnedPowerUI) else {
    restoreAndExit(.smcUnavailable, event: "failsafe_restore_failed", message: "The helper could not verify normal charging state and stopped without applying a limit.")
}
if arguments.restoreOnly {
    SMC.stop()
    exit(HelperExit.success.rawValue)
}

if ChargeProtectionAvailability.nativeLimitAvailable(on: currentOSVersion),
   initialConfiguration.managementMode != .softwareManaged {
    JSONLineLogger.write(
        "warning",
        category: "charge",
        event: "system_management_required",
        message: "macOS charge management is preferred; software control was refused until the user explicitly selects software management."
    )
}

let signalQueue = DispatchQueue(label: "com.chengxin.dbhv.charge-helper.signal")
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
var signalSources: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT] {
    let source = DispatchSource.makeSignalSource(signal: number, queue: signalQueue)
    source.setEventHandler {
        DBHVPowerUIRequestAbort()
        let restored = attemptNormalChargingRestoration()
        JSONLineLogger.write(restored ? "warning" : "error", category: "charge", event: "failsafe_signal", message: restored ? "A termination signal triggered fail-safe charging restoration." : "A termination signal triggered fail-safe restoration, but normal charging could not be verified after retries.")
        SMC.stop()
        exit(restored ? 0 : HelperExit.smcUnavailable.rawValue)
    }
    source.resume()
    signalSources.append(source)
}

JSONLineLogger.write(
    "info",
    category: "charge",
    event: "helper_started",
    message: "Charge helper started; control method: \(actuator.method.rawValue)."
)
JSONLineLogger.write(
    "info",
    category: "charge",
    event: "capability_detected",
    message: "Runtime charge-control capability: \(actuator.method.rawValue)."
)
var holdingLimit: FixedChargeLimit?
var lastConfigurationInvalid = false
var wasEnabled = false
var lastBatteryReadFailed = false
var lastActuationFailed = false
var lastRestorationFailed = false
var systemOverrideTracker = SystemChargeOverrideTracker()
var systemCalibrationTracker = SystemCalibrationTracker()
var lastReportedSystemPause: String?
private var previousStatus: StatusSnapshot?
let machine = ChargeProtectionStateMachine()
var applicationRemovalMonitor = ApplicationRemovalMonitor()
var powerUICoordinator = PowerUIProtectionCoordinator()

private func deferToSystemIfNeeded(
    configuration: ChargeProtectionConfiguration,
    battery: BatteryReading? = nil
) -> Bool {
    guard actuator.method == .powerUIOptimized80, configuration.fixedLimit == .eighty else {
        systemOverrideTracker = SystemChargeOverrideTracker()
        systemCalibrationTracker = SystemCalibrationTracker()
        lastReportedSystemPause = nil
        return false
    }
    let override = systemOverrideTracker.observe(
        temporarilyDisabled: actuator.systemTemporaryFullChargeObservation()
    )
    let calibration = systemCalibrationTracker.observe(
        limitSuspended: actuator.systemCalibrationObservation()
    )
    guard override?.defersChargeControl == true || calibration?.defersChargeControl == true else {
        if lastReportedSystemPause != nil {
            JSONLineLogger.write("info", category: "charge", event: "system_charging_pause_ended",
                                 message: "The system no longer reports a charging pause; normal policy verification resumes. This is not a claim of calibration completion or restored protection.")
            lastReportedSystemPause = nil
        }
        return false
    }
    powerUICoordinator.reset()
    holdingLimit = nil
    lastActuationFailed = false
    writeSystemChargingPauseStatus(
        override: override, calibration: calibration,
        configuration: configuration, battery: battery ?? readBattery(),
        to: arguments.statusURL, previous: &previousStatus,
        lastReported: &lastReportedSystemPause
    )
    return true
}

private func writePowerUIReport(
    configuration: ChargeProtectionConfiguration,
    battery: BatteryReading,
    managed: Bool,
    holding: Bool,
    policyConfirmed: Bool? = nil,
    error: String? = nil
) {
    writeStatusIfChanged(ChargeProtectionStatus(
        helperVersion: helperVersion,
        installed: true,
        enabled: configuration.enabled,
        fixedLimit: .eighty,
        temporaryFullCharge: false,
        configurationUpdatedAt: configuration.updatedAt,
        configurationRevision: configuration.revision,
        holding: holding,
        adapterConnected: battery.nativeAdapterConfirmed,
        batteryPercentage: battery.charge.percentage,
        controlMethod: .powerUIOptimized80,
        lastError: error,
        systemChargeOverride: systemOverrideTracker.state,
        systemCalibration: systemCalibrationTracker.state,
        powerUIPolicyConfirmed: policyConfirmed ?? managed
    ), to: arguments.statusURL, previous: &previousStatus)
}

while true {
    if let applicationURL = arguments.applicationURL,
       applicationRemovalMonitor.shouldCleanUp(
           applicationExists: verifiedApplicationExists(at: applicationURL)
       ) {
        cleanUpAfterApplicationRemoval(arguments)
    }
    guard var configuration = secureConfiguration(at: arguments.configurationURL, ownerUID: arguments.ownerUID) else {
        if holdingLimit != nil || actuator.hasOwnedPowerUIState {
            if actuator.allowCharging() { holdingLimit = nil }
        }
        let fallback = ChargeProtectionConfiguration()
        writeTerminalStatus(
            configuration: fallback,
            error: "Unsafe or invalid configuration",
            controlMethod: actuator.method,
            to: arguments.statusURL,
            previous: &previousStatus
        )
        if !lastConfigurationInvalid {
            JSONLineLogger.write("error", category: "charge", event: "invalid_configuration", message: "Configuration ownership, permissions, or contents were invalid; charging was restored.")
            lastConfigurationInvalid = true
        }
        wasEnabled = false
        Thread.sleep(forTimeInterval: 5)
        continue
    }
    if lastConfigurationInvalid {
        JSONLineLogger.write("info", category: "charge", event: "configuration_recovered", message: "A valid charge protection configuration became available again.")
        lastConfigurationInvalid = false
    }
    if ChargeProtectionAvailability.nativeLimitAvailable(on: currentOSVersion),
       configuration.managementMode != .softwareManaged {
        if holdingLimit != nil { _ = actuator.allowCharging(); holdingLimit = nil }
        writeTerminalStatus(
            configuration: configuration,
            error: nil,
            controlMethod: actuator.method,
            to: arguments.statusURL,
            previous: &previousStatus
        )
        if wasEnabled {
            JSONLineLogger.write(
                "warning",
                category: "charge",
                event: "system_management_restored",
                message: "Software charging control was stopped because software-managed mode is not authorized."
            )
        }
        wasEnabled = false
        Thread.sleep(forTimeInterval: 5)
        continue
    }
    if !configuration.enabled {
        powerUICoordinator.reset()
        systemOverrideTracker = SystemChargeOverrideTracker()
        systemCalibrationTracker = SystemCalibrationTracker()
        lastReportedSystemPause = nil
        let restorationRequired = holdingLimit != nil || actuator.hasOwnedPowerUIState || actuator.method == .powerUIOptimized80
        let restored = !restorationRequired || actuator.allowCharging()
        if restored { holdingLimit = nil }
        writeTerminalStatus(
            configuration: configuration,
            error: restored ? nil : "Unable to restore normal charging",
            controlMethod: actuator.method,
            to: arguments.statusURL,
            previous: &previousStatus
        )
        if wasEnabled {
            JSONLineLogger.write(
                restored ? "info" : "error",
                category: "charge",
                event: restored ? "protection_disabled" : "protection_disable_restore_failed",
                message: restored
                    ? "Charge protection was disabled and normal system charging was restored."
                    : "Charge protection was disabled, but normal charging restoration could not yet be verified; the helper will retry."
            )
        } else if lastRestorationFailed && restored {
            JSONLineLogger.write(
                "info",
                category: "charge",
                event: "protection_disable_restore_recovered",
                message: "Normal charging restoration succeeded after a previous retryable failure."
            )
        }
        lastRestorationFailed = !restored
        wasEnabled = false
        Thread.sleep(forTimeInterval: 5)
        continue
    }
    wasEnabled = true

    // Both system reasons take precedence over telemetry maintenance and
    // control. Unknown reads after a confirmed pause cannot cancel it.
    if deferToSystemIfNeeded(configuration: configuration) {
        Thread.sleep(forTimeInterval: 5)
        continue
    }

    guard let battery = readBattery() else {
        if actuator.method == .powerUIOptimized80,
           configuration.fixedLimit == .eighty,
           !configuration.temporaryFullCharge,
           actuator.hasOwnedPowerUIState {
            let maintenance = actuator.maintainPowerUIWithoutBatteryReading()
            if deferToSystemIfNeeded(configuration: configuration) {
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            holdingLimit = maintenance.holding ? .eighty : nil
            if !lastBatteryReadFailed {
                JSONLineLogger.write(
                    maintenance.succeeded ? "warning" : "error",
                    category: "charge",
                    event: "battery_read_failed_powerui_maintained",
                    message: maintenance.succeeded
                        ? "Battery telemetry is unavailable; the owned native 80% policy remains managed using the last validated battery reading."
                        : "Battery telemetry is unavailable and the owned native 80% policy could not be verified; recovery will be retried."
                )
                lastBatteryReadFailed = true
            }
            writeStatusIfChanged(ChargeProtectionStatus(
                helperVersion: helperVersion,
                installed: true,
                enabled: configuration.enabled,
                fixedLimit: .eighty,
                temporaryFullCharge: false,
                configurationUpdatedAt: configuration.updatedAt,
                configurationRevision: configuration.revision,
                holding: false,
                adapterConnected: nil,
                batteryPercentage: nil,
                controlMethod: actuator.method,
                lastError: maintenance.succeeded ? nil : "Unable to verify battery telemetry or the native 80% policy",
                systemChargeOverride: systemOverrideTracker.state,
                systemCalibration: systemCalibrationTracker.state,
                powerUIPolicyConfirmed: false
            ), to: arguments.statusURL, previous: &previousStatus)
            Thread.sleep(forTimeInterval: 5)
            continue
        }

        let restorationRequired = holdingLimit != nil || actuator.hasOwnedPowerUIState
        if restorationRequired, actuator.allowCharging() { holdingLimit = nil }
        if !lastBatteryReadFailed {
            JSONLineLogger.write("error", category: "charge", event: "battery_read_failed", message: "The helper could not read the battery; charging was restored.")
            lastBatteryReadFailed = true
        }
        writeStatusIfChanged(ChargeProtectionStatus(
            helperVersion: helperVersion,
            installed: true,
            enabled: configuration.enabled,
            fixedLimit: configuration.fixedLimit,
            temporaryFullCharge: configuration.temporaryFullCharge,
            configurationUpdatedAt: configuration.updatedAt,
            configurationRevision: configuration.revision,
            holding: false,
            adapterConnected: nil,
            batteryPercentage: nil,
            controlMethod: actuator.method,
            lastError: "Unable to read battery"
        ), to: arguments.statusURL, previous: &previousStatus)
        Thread.sleep(forTimeInterval: 5)
        continue
    }
    if lastBatteryReadFailed {
        JSONLineLogger.write(
            "info",
            category: "charge",
            event: "battery_read_recovered",
            message: "Battery telemetry recovered; live charge-protection decisions resumed."
        )
    }
    lastBatteryReadFailed = false
    if actuator.method == .powerUIOptimized80 {
        guard let buildVer = currentOSBuildVersion(), isVerifiedPowerUIMacOSBuild(buildVer) else {
            _ = actuator.allowCharging()
            holdingLimit = nil
            let errMessage = "Native PowerUI 80% control is not verified on macOS build \(currentOSBuildVersion() ?? "unknown")"
            JSONLineLogger.write("warning", category: "charge", event: "unverified_macos_build", message: errMessage)
            writeStatusIfChanged(ChargeProtectionStatus(
                helperVersion: helperVersion,
                installed: true,
                enabled: configuration.enabled,
                fixedLimit: configuration.fixedLimit,
                temporaryFullCharge: configuration.temporaryFullCharge,
                configurationUpdatedAt: configuration.updatedAt,
                configurationRevision: configuration.revision,
                holding: false,
                adapterConnected: battery.nativeAdapterConfirmed,
                batteryPercentage: battery.charge.percentage,
                controlMethod: actuator.method,
                lastError: errMessage
            ), to: arguments.statusURL, previous: &previousStatus)
            Thread.sleep(forTimeInterval: 5)
            continue
        }

        if configuration.fixedLimit != .eighty {
            powerUICoordinator.reset()
            _ = actuator.allowCharging()
            holdingLimit = nil
            writeStatusIfChanged(ChargeProtectionStatus(
                helperVersion: helperVersion,
                installed: true,
                enabled: configuration.enabled,
                fixedLimit: configuration.fixedLimit,
                temporaryFullCharge: configuration.temporaryFullCharge,
                configurationUpdatedAt: configuration.updatedAt,
                configurationRevision: configuration.revision,
                holding: false,
                adapterConnected: battery.nativeAdapterConfirmed,
                batteryPercentage: battery.charge.percentage,
                controlMethod: actuator.method,
                lastError: "macOS 15.8 supports only the native 80% charge limit"
            ), to: arguments.statusURL, previous: &previousStatus)
            Thread.sleep(forTimeInterval: 5)
            continue
        }

        if configuration.temporaryFullCharge {
            powerUICoordinator.reset()
            let restored = actuator.allowCharging()
            holdingLimit = nil
            if battery.charge.fullyCharged || battery.charge.percentage >= 100 {
                configuration.temporaryFullCharge = false
                configuration.renewRevision()
                guard writeConfiguration(
                    configuration,
                    to: arguments.configurationURL,
                    ownerUID: arguments.ownerUID
                ) else {
                    restoreAndExit(
                        .unsafeConfiguration,
                        event: "configuration_update_failed",
                        message: "The completed temporary override could not be saved; charging was restored."
                    )
                }
                JSONLineLogger.write(
                    "info",
                    category: "charge",
                    event: "temporary_full_completed",
                    message: "The temporary full charge completed. The saved 80% policy will be reapplied when eligible."
                )
            } else {
                writeStatusIfChanged(ChargeProtectionStatus(
                    helperVersion: helperVersion,
                    installed: true,
                    enabled: true,
                    fixedLimit: .eighty,
                    temporaryFullCharge: true,
                    configurationUpdatedAt: configuration.updatedAt,
                    configurationRevision: configuration.revision,
                    holding: false,
                    adapterConnected: battery.nativeAdapterConfirmed,
                    batteryPercentage: battery.charge.percentage,
                    controlMethod: actuator.method,
                    lastError: restored ? nil : "Unable to restore charging for the temporary full charge"
                ), to: arguments.statusURL, previous: &previousStatus)
                Thread.sleep(forTimeInterval: 5)
                continue
            }
        }

        var observedBattery = battery
        let input = actuator.powerUIInput(battery)
        var decision = powerUICoordinator.evaluate(input: input)
        if let request = decision.request {
            writePowerUIReport(
                configuration: configuration, battery: battery,
                managed: decision.managed, holding: decision.holding,
                policyConfirmed: decision.policyConfirmed, error: decision.errorMessage
            )
            let accepted = actuator.applyPowerUIRequest(request, input: input)
            guard let freshBattery = readBattery() else {
                powerUICoordinator.record(request, accepted: false, observed: input)
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            if deferToSystemIfNeeded(configuration: configuration, battery: freshBattery) {
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            observedBattery = freshBattery
            let freshInput = actuator.powerUIInput(freshBattery)
            powerUICoordinator.record(request, accepted: accepted, observed: freshInput)
            decision = powerUICoordinator.evaluate(input: freshInput)
        }
        if let error = decision.errorMessage, !lastActuationFailed {
            JSONLineLogger.write("error", category: "charge", event: "powerui_recovery_failed", message: error)
            lastActuationFailed = true
        } else if decision.policyConfirmed && lastActuationFailed {
            JSONLineLogger.write("info", category: "charge", event: "powerui_engaged",
                                 message: "The native 80% policy was confirmed after recovery.")
            lastActuationFailed = false
        }
        holdingLimit = decision.holding ? .eighty : nil
        writePowerUIReport(
            configuration: configuration, battery: observedBattery,
            managed: decision.managed, holding: decision.holding,
            policyConfirmed: decision.policyConfirmed, error: decision.errorMessage
        )
        Thread.sleep(forTimeInterval: 5)
        continue
    }

    let decision = machine.decide(
        configuration: configuration,
        battery: battery.charge,
        holdingLimit: holdingLimit
    )
    var actuationSucceeded = true
    switch decision.actuation {
    case .allowCharging: actuationSucceeded = actuator.allowCharging()
    case .holdCharging: actuationSucceeded = actuator.holdCharging(at: battery.charge.percentage)
    case .unchanged:
        if decision.holdingAfterDecision && !actuator.isHoldApplied() {
            actuationSucceeded = actuator.holdCharging(at: battery.charge.percentage)
        }
    }
    if !actuationSucceeded {
        _ = actuator.allowCharging()
        holdingLimit = nil
        if !lastActuationFailed {
            JSONLineLogger.write("error", category: "charge", event: "smc_write_failed", message: "An SMC write or verification failed; fail-safe charging was restored.")
            lastActuationFailed = true
        }
    } else {
        lastActuationFailed = false
        holdingLimit = decision.holdingAfterDecision ? configuration.fixedLimit : nil
        switch decision.event {
        case .beganHolding:
            JSONLineLogger.write("info", category: "charge", event: "limit_reached", message: "The fixed charge limit was reached and charging was paused.")
        case .resumedBelowLimit:
            JSONLineLogger.write("info", category: "charge", event: "below_limit_resumed", message: "Battery level fell below the fixed limit and charging resumed.")
        case .resumedAfterLimitIncrease:
            JSONLineLogger.write("info", category: "charge", event: "limit_increased_resumed", message: "The fixed charge limit was raised and charging resumed toward the new target.")
        case .temporaryFullCompleted:
            configuration.temporaryFullCharge = false
            configuration.renewRevision()
            if !writeConfiguration(configuration, to: arguments.configurationURL, ownerUID: arguments.ownerUID) {
                restoreAndExit(
                    .unsafeConfiguration,
                    event: "configuration_update_failed",
                    message: "The completed temporary override could not be saved; charging was restored."
                )
            } else {
                JSONLineLogger.write("info", category: "charge", event: "temporary_full_completed", message: "The temporary full charge completed and the fixed limit was restored.")
            }
        case .disabledRestored:
            JSONLineLogger.write("info", category: "charge", event: "protection_disabled", message: "Charge protection was disabled and normal charging was restored.")
        case .adapterDisconnectedRestored, .none:
            break
        }
    }

    writeStatusIfChanged(ChargeProtectionStatus(
        helperVersion: helperVersion,
        installed: true,
        enabled: configuration.enabled,
        fixedLimit: configuration.fixedLimit,
        temporaryFullCharge: decision.temporaryFullChargeAfterDecision,
        configurationUpdatedAt: configuration.updatedAt,
        configurationRevision: configuration.revision,
        holding: holdingLimit != nil,
        adapterConnected: battery.charge.adapterConnected,
        batteryPercentage: battery.charge.percentage,
        controlMethod: actuator.method,
        lastError: actuationSucceeded ? nil : "SMC write verification failed"
    ), to: arguments.statusURL, previous: &previousStatus)
    Thread.sleep(forTimeInterval: 5)
}
