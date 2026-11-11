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

private let helperVersion = "1.1.2.3"
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

private struct PowerUIOwnershipMarker: Codable {
    static let schemaVersion = 1

    let schema: Int
    let helperIdentifier: String
    let targetPercentage: Int
    let leaseState: PowerUIOwnershipLeaseState
    /// Last battery percentage read directly from AppleSmartBattery while the
    /// policy was owned. Optional keeps existing v1 markers decodable during
    /// an in-place helper upgrade.
    let lastKnownBatteryPercentage: Int?

    enum CodingKeys: String, CodingKey {
        case schema
        case helperIdentifier
        case targetPercentage
        case leaseState
        case lastKnownBatteryPercentage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        helperIdentifier = try container.decode(String.self, forKey: .helperIdentifier)
        targetPercentage = try container.decode(Int.self, forKey: .targetPercentage)
        leaseState = try container.decodeIfPresent(PowerUIOwnershipLeaseState.self, forKey: .leaseState) ?? .activeEighty
        lastKnownBatteryPercentage = try container.decodeIfPresent(Int.self, forKey: .lastKnownBatteryPercentage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(helperIdentifier, forKey: .helperIdentifier)
        try container.encode(targetPercentage, forKey: .targetPercentage)
        try container.encode(leaseState, forKey: .leaseState)
        try container.encodeIfPresent(lastKnownBatteryPercentage, forKey: .lastKnownBatteryPercentage)
    }

    init(leaseState: PowerUIOwnershipLeaseState = .activeEighty, lastKnownBatteryPercentage: Int?) {
        schema = Self.schemaVersion
        helperIdentifier = InstalledComponents.helperIdentifier
        targetPercentage = FixedChargeLimit.eighty.rawValue
        self.leaseState = leaseState
        self.lastKnownBatteryPercentage = lastKnownBatteryPercentage.flatMap {
            (0...100).contains($0) ? $0 : nil
        }
    }

    var isValid: Bool {
        schema == Self.schemaVersion &&
            helperIdentifier == InstalledComponents.helperIdentifier &&
            targetPercentage == FixedChargeLimit.eighty.rawValue &&
            lastKnownBatteryPercentage.map { (0...100).contains($0) } != false
    }
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
    private var powerUISchedule = PowerUIRequestSchedule()
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
        switch inspectPowerUIOwnershipFile(at: powerUIOwnershipURL, requireRoot: true) {
        case .owned(let marker):
            return marker.leaseState == .activeEighty || marker.leaseState == .preEngaging
        case .unowned, .corrupted:
            return false
        }
    }

    var cachedPowerUIBatteryPercentage: Int? {
        readPowerUIOwnership()?.lastKnownBatteryPercentage
    }

    @discardableResult
    func rememberPowerUIBatteryPercentage(_ percentage: Int) -> Bool {
        guard (0...100).contains(percentage),
              let marker = readPowerUIOwnership() else { return false }
        guard marker.lastKnownBatteryPercentage != percentage else { return true }
        return writePowerUIOwnership(batteryPercentage: percentage, leaseState: marker.leaseState)
    }

    private func writePowerUIOwnership(
        batteryPercentage: Int,
        leaseState: PowerUIOwnershipLeaseState = .activeEighty
    ) -> Bool {
        guard (0...100).contains(batteryPercentage) else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(PowerUIOwnershipMarker(
                leaseState: leaseState,
                lastKnownBatteryPercentage: batteryPercentage
            )).write(to: powerUIOwnershipURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600, .ownerAccountID: 0, .groupOwnerAccountID: 0],
                ofItemAtPath: powerUIOwnershipURL.path
            )
            return true
        } catch {
            return false
        }
    }

    private func removePowerUIOwnership() {
        guard powerUIOwnershipURL.path.hasPrefix(
            "/Library/Application Support/DriveBatteryHealthViewer/ChargeProtection/"
        ) else { return }
        try? FileManager.default.removeItem(at: powerUIOwnershipURL)
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
            let inspection = inspectPowerUIOwnershipFile(at: powerUIOwnershipURL, requireRoot: true)
            switch inspection {
            case .corrupted(let err):
                var status = DBHVPowerUIStatus()
                if DBHVPowerUIReadStatus(&status), status.enabled == 1 {
                    JSONLineLogger.write("error", category: "charge", event: "corrupted_ownership_marker",
                                         message: "Ownership marker is corrupted while PowerUI is active (\(err)); refusing unverified state mutation.")
                    selectedOK = false
                } else {
                    JSONLineLogger.write("warning", category: "charge", event: "corrupted_ownership_marker_cleared",
                                         message: "Ownership marker was corrupted (\(err)) but baseline PowerUI is inactive; clearing file.")
                    removePowerUIOwnership()
                    selectedOK = true
                }
            case .unowned:
                selectedOK = true
            case .owned(let marker):
                switch marker.leaseState {
                case .restoredTopOff, .deferredToSystem:
                    selectedOK = true
                case .activeEighty, .preEngaging:
                    if preserveOwnedPowerUI {
                        selectedOK = true
                    } else {
                        var rawStatus = DBHVPowerUIStatus()
                        if DBHVPowerUIReadStatus(&rawStatus), DBHVSystemDefersEighty(rawStatus) {
                            if !writePowerUIOwnership(batteryPercentage: marker.lastKnownBatteryPercentage ?? 80, leaseState: .deferredToSystem) {
                                selectedOK = false
                            } else {
                                selectedOK = true
                            }
                        } else {
                            selectedOK = DBHVPowerUIDisable()
                            var afterStatus = DBHVPowerUIStatus()
                            if DBHVPowerUIReadStatus(&afterStatus) {
                                if afterStatus.enabled == 1 && afterStatus.current_state == 1 && afterStatus.checkpoint == 5 {
                                    if !writePowerUIOwnership(batteryPercentage: marker.lastKnownBatteryPercentage ?? 80, leaseState: .restoredTopOff) {
                                        selectedOK = false
                                    }
                                } else if (afterStatus.enabled == 0 && afterStatus.current_state == 0 && afterStatus.checkpoint == 10) ||
                                          (afterStatus.enabled == 0 && afterStatus.current_state == 0 && afterStatus.checkpoint == 0) {
                                    removePowerUIOwnership()
                                    if FileManager.default.fileExists(atPath: powerUIOwnershipURL.path) {
                                        selectedOK = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
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

    func powerUIRequest(
        adapterConnected: Bool,
        systemAdapterConnected: Bool?,
        batteryPercentage: Int,
        managed: Bool,
        checkpoint: Int32? = nil,
        engaged: Bool? = nil
    ) -> PowerUIRequestSchedule.Request? {
        powerUISchedule.request(adapterConnected: adapterConnected, systemAdapterConnected: systemAdapterConnected,
                                batteryPercentage: batteryPercentage, managed: managed,
                                checkpoint: checkpoint, engaged: engaged)
    }

    var powerUIRequestFailed: Bool { powerUISchedule.hasFailed }

    func resetPowerUIRequests() { powerUISchedule = PowerUIRequestSchedule() }

    func applyPowerUIRequest(_ request: PowerUIRequestSchedule.Request, at batteryPercentage: Int) -> Bool {
        let succeeded: Bool
        switch request {
        case .recover:
            succeeded = holdCharging(at: batteryPercentage)
        case .renew:
            succeeded = hasPowerUIOwnership() && DBHVPowerUIRefreshEighty(Int32(batteryPercentage), powerUIExternalPowerConfirmed)
        }
        powerUISchedule.record(succeeded: succeeded)
        return succeeded
    }

    @discardableResult
    func holdCharging(at batteryPercentage: Int) -> Bool {
        // The startup restore already clears any adapter-isolation state left
        // by an older helper. Holding a real charge-inhibit key must not touch
        // CHIE again: CHIE is the adapter-disconnect mechanism that causes
        // macOS to publish "no external power" and 0 W.
        switch method {
        case .powerUIOptimized80:
            let inspection = inspectPowerUIOwnershipFile(at: powerUIOwnershipURL, requireRoot: true)
            let ownsPolicy: Bool
            switch inspection {
            case .owned(let marker):
                switch marker.leaseState {
                case .activeEighty, .preEngaging:
                    ownsPolicy = true
                case .restoredTopOff, .deferredToSystem:
                    guard writePowerUIOwnership(batteryPercentage: batteryPercentage, leaseState: .preEngaging) else {
                        JSONLineLogger.write("error", category: "charge", event: "ownership_write_failed",
                                             message: "Failed to persist preEngaging ownership state; aborting engagement.")
                        return false
                    }
                    ownsPolicy = true
                }
            case .unowned:
                var rawStatus = DBHVPowerUIStatus()
                if DBHVPowerUIReadStatus(&rawStatus) {
                    if DBHVSystemDefersEighty(rawStatus) {
                        return false
                    }
                    let isBaselineClean = (rawStatus.enabled == 0 && rawStatus.current_state == 0 && rawStatus.checkpoint == 0) ||
                                          (rawStatus.enabled == 0 && rawStatus.current_state == 0 && rawStatus.checkpoint == 10)
                    if !isBaselineClean {
                        JSONLineLogger.write("warning", category: "charge", event: "unowned_system_policy_detected",
                                             message: "PowerUI is already engaged with unowned system policy (\(rawStatus.checkpoint)); refusing to hijack.")
                        return false
                    }
                }
                ownsPolicy = false
                guard writePowerUIOwnership(batteryPercentage: batteryPercentage, leaseState: .preEngaging) else {
                    return false
                }
            case .corrupted(let err):
                var rawStatus = DBHVPowerUIStatus()
                let isBaselineClean = DBHVPowerUIReadStatus(&rawStatus) &&
                    ((rawStatus.enabled == 0 && rawStatus.current_state == 0 && rawStatus.checkpoint == 0) ||
                     (rawStatus.enabled == 0 && rawStatus.current_state == 0 && rawStatus.checkpoint == 10))
                if isBaselineClean {
                    JSONLineLogger.write("warning", category: "charge", event: "clearing_corrupted_marker_at_clean_baseline",
                                         message: "Clearing corrupted marker (\(err)) before new engagement.")
                    removePowerUIOwnership()
                    guard writePowerUIOwnership(batteryPercentage: batteryPercentage, leaseState: .preEngaging) else { return false }
                    ownsPolicy = false
                } else {
                    JSONLineLogger.write("error", category: "charge", event: "corrupted_marker_cannot_engage",
                                         message: "Ownership marker corrupted (\(err)) with active PowerUI; cannot safely engage.")
                    return false
                }
            }

            let engageOK = DBHVPowerUIEngageEighty(Int32(batteryPercentage), ownsPolicy, powerUIExternalPowerConfirmed)
            if engageOK {
                if !writePowerUIOwnership(batteryPercentage: batteryPercentage, leaseState: .activeEighty) {
                    JSONLineLogger.write("error", category: "charge", event: "active_marker_write_failed",
                                         message: "Engaged 80% successfully, but failed to write activeEighty marker to disk.")
                }
                return true
            } else {
                if !ownsPolicy {
                    var afterStatus = DBHVPowerUIStatus()
                    if DBHVPowerUIReadStatus(&afterStatus) {
                        let isClean = (afterStatus.enabled == 0 && afterStatus.current_state == 0 && afterStatus.checkpoint == 0) ||
                                      (afterStatus.enabled == 0 && afterStatus.current_state == 0 && afterStatus.checkpoint == 10)
                        if isClean {
                            removePowerUIOwnership()
                        } else {
                            _ = writePowerUIOwnership(batteryPercentage: batteryPercentage, leaseState: .restoredTopOff)
                        }
                    } else {
                        _ = writePowerUIOwnership(batteryPercentage: batteryPercentage, leaseState: .restoredTopOff)
                    }
                }
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
                snapshot.temporarily_disabled != 1 && DBHVReadGaugingLimitSuspension() != 1 &&
                snapshot.enabled == 1 && snapshot.current_state == 1 && snapshot.checkpoint == 2 && snapshot.engaged == 1
        case .chte: return SMC.read("CHTE", size: 4) == chteHold
        case .legacyCH0BCH0C: return legacyHoldCommanded
        case .chieFallback: return SMC.read("CHIE", size: 1) == chieDisconnect
        case .unavailable: return false
        }
    }

    func isPowerUIManaged() -> Bool {
        isPowerUIManaged(batteryPercentage: nil)
    }

    func isPowerUIManaged(batteryPercentage: Int?) -> Bool {
        guard method == .powerUIOptimized80, hasPowerUIOwnership() else { return false }
        var snapshot = DBHVPowerUIStatus()
        guard DBHVPowerUIReadStatus(&snapshot),
              snapshot.temporarily_disabled != 1, DBHVReadGaugingLimitSuspension() != 1,
              snapshot.enabled == 1,
              snapshot.current_state == 1 else { return false }
        if let batteryPercentage {
            if PowerUIRequestSchedule.needsCheckpointRecovery(
                checkpoint: snapshot.checkpoint,
                engaged: snapshot.engaged == 1,
                batteryPercentage: batteryPercentage
            ) {
                return false
            }
        }
        return snapshot.checkpoint == 1 ||
            (snapshot.checkpoint == 2 && snapshot.engaged == 1)
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
              snapshot.temporarily_disabled != 1,
              DBHVReadGaugingLimitSuspension() != 1,
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
              let status = values["--status"], status.hasPrefix("/Library/Application Support/DriveBatteryHealthViewer/"),
              let log = values["--log"], log.hasPrefix("/Library/Logs/DriveBatteryHealthViewer/"),
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
guard let arguments = HelperArguments(CommandLine.arguments) else { exit(HelperExit.invalidArguments.rawValue) }
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
    exit(code.rawValue)
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
    restoreAndExit(.success, event: "restore_completed", message: "Normal system charging was restored.")
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
        exit(0)
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
var overchargeMonitor = PowerUIOverchargeMonitor()

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
        actuator.resetPowerUIRequests()
        systemOverrideTracker = SystemChargeOverrideTracker()
        systemCalibrationTracker = SystemCalibrationTracker()
        lastReportedSystemPause = nil
        let restorationRequired = holdingLimit != nil || actuator.hasOwnedPowerUIState
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
                powerUIPolicyConfirmed: maintenance.managed
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

        _ = actuator.rememberPowerUIBatteryPercentage(battery.charge.percentage)
        if configuration.fixedLimit != .eighty {
            actuator.resetPowerUIRequests()
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
            actuator.resetPowerUIRequests()
            overchargeMonitor.reset()
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

        // 100% Armed Waiting: if at 100%, do not request engage/renew.
        if battery.charge.percentage >= 100 {
            actuator.resetPowerUIRequests()
            overchargeMonitor.reset()
            let managed = actuator.isPowerUIManaged(batteryPercentage: battery.charge.percentage)
            let isHolding = actuator.isHoldApplied()
            let holding = battery.nativeAdapterConfirmed && managed && isHolding
            holdingLimit = holding ? .eighty : nil
            writePowerUIReport(
                configuration: configuration,
                battery: battery,
                managed: managed,
                holding: holding,
                policyConfirmed: false
            )
            Thread.sleep(forTimeInterval: 5)
            continue
        }

        var managed = actuator.isPowerUIManaged(batteryPercentage: battery.charge.percentage)
        let adapterConnected = battery.nativeAdapterConfirmed
        var rawStatusForRequest = DBHVPowerUIStatus()
        _ = DBHVPowerUIReadStatus(&rawStatusForRequest)
        var didAttemptReassert = false
        if let request = actuator.powerUIRequest(
            adapterConnected: battery.charge.adapterConnected,
            systemAdapterConnected: battery.systemAdapterConnected,
            batteryPercentage: battery.charge.percentage,
            managed: managed,
            checkpoint: rawStatusForRequest.checkpoint,
            engaged: rawStatusForRequest.engaged == 1
        ) {
            if request == .recover {
                // Invalidate a previous hold and refresh timestamp before entering the bridge's bounded wait.
                writePowerUIReport(configuration: configuration, battery: battery, managed: false, holding: false, policyConfirmed: false)
            } else {
                // Heartbeat before bounded wait
                writePowerUIReport(configuration: configuration, battery: battery, managed: managed, holding: holdingLimit != nil, policyConfirmed: managed && holdingLimit != nil)
            }
            didAttemptReassert = true
            _ = actuator.applyPowerUIRequest(request, at: battery.charge.percentage)
            managed = actuator.isPowerUIManaged(batteryPercentage: battery.charge.percentage)
        }

        // Re-read battery after bridge execution: if adapter was unplugged during wait, do not record failure backoff
        guard let freshBattery = readBattery() else {
            Thread.sleep(forTimeInterval: 5)
            continue
        }
        if !freshBattery.nativeAdapterConfirmed {
            actuator.resetPowerUIRequests()
            overchargeMonitor.reset()
            holdingLimit = nil
            writePowerUIReport(configuration: configuration, battery: freshBattery, managed: false, holding: false, policyConfirmed: false)
            Thread.sleep(forTimeInterval: 5)
            continue
        }

        // A pause can arrive while the bridge is waiting for confirmation.
        if deferToSystemIfNeeded(configuration: configuration, battery: freshBattery) {
            Thread.sleep(forTimeInterval: 5)
            continue
        }

        var rawStatus = DBHVPowerUIStatus()
        _ = DBHVPowerUIReadStatus(&rawStatus)
        let overchargeState = overchargeMonitor.update(
            batteryPercentage: freshBattery.charge.percentage,
            isCharging: freshBattery.isCharging ?? false,
            checkpoint: rawStatus.checkpoint,
            engaged: rawStatus.engaged == 1,
            managed: managed,
            didAttemptReassert: didAttemptReassert
        )

        var lastError: String? = nil
        let holding: Bool
        let isHoldingConfirmed = (rawStatus.checkpoint == 2 && rawStatus.engaged == 1)
        switch overchargeState {
        case .abnormalChargingPastLimit(let msg):
            holding = false
            managed = false
            lastError = msg
            if !lastActuationFailed {
                JSONLineLogger.write("error", category: "charge", event: "overcharge_detected", message: msg)
                lastActuationFailed = true
            }
        default:
            holding = adapterConnected && managed && freshBattery.isCharging == false &&
                freshBattery.charge.percentage >= FixedChargeLimit.eighty.rawValue && actuator.isHoldApplied()
            let requestFailed = adapterConnected && !managed && freshBattery.charge.percentage < 100 &&
                actuator.powerUIRequestFailed
            if requestFailed && !lastActuationFailed {
                JSONLineLogger.write("error", category: "charge", event: "powerui_engagement_failed",
                                     message: "PowerUI did not confirm the native 80% policy; recovery will be retried.")
                lastActuationFailed = true
            } else if adapterConnected && managed && lastActuationFailed {
                JSONLineLogger.write("info", category: "charge", event: "powerui_engaged",
                                     message: "PowerUI confirmed the native 80% policy while external power is available.")
                lastActuationFailed = false
            }
            if requestFailed {
                lastError = "Native PowerUI 80% engagement failed"
            }
        }

        let policyConfirmed: Bool
        if freshBattery.charge.percentage >= 80 {
            policyConfirmed = managed && (holding || isHoldingConfirmed)
        } else {
            policyConfirmed = managed
        }

        holdingLimit = holding ? .eighty : nil
        writePowerUIReport(
            configuration: configuration,
            battery: freshBattery,
            managed: managed,
            holding: holding,
            policyConfirmed: policyConfirmed,
            error: lastError
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
