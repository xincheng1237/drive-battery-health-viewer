import Darwin
import Foundation

public enum FixedChargeLimit: Int, Codable, CaseIterable, Sendable {
    case eighty = 80
    case eightyFive = 85
    case ninety = 90
    case ninetyFive = 95
    case oneHundred = 100

    public static let defaultValue: Self = .eighty

    public init?(validated value: Int) {
        self.init(rawValue: value)
    }
}

public enum ChargeLimitCapabilityPolicy: Sendable {
    /// macOS 15.8 on Apple Silicon exposes the native optimized-charging path
    /// used by PowerUI, but does not expose arbitrary MCL targets on the tested
    /// hardware. Keep every fixed level visible for continuity: 80% selects
    /// the native limit, while 100% represents normal charging with protection
    /// disabled. Intermediate targets remain visible but unavailable.
    public static func isPowerUIEightyOnly(
        isAppleSilicon: Bool,
        operatingSystemVersion: OperatingSystemVersion
    ) -> Bool {
        isAppleSilicon &&
            operatingSystemVersion.majorVersion == 15 &&
            operatingSystemVersion.minorVersion == 8
    }

    public static func permits(
        _ limit: FixedChargeLimit,
        isAppleSilicon: Bool,
        operatingSystemVersion: OperatingSystemVersion
    ) -> Bool {
        !isPowerUIEightyOnly(
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion
        ) || limit == .eighty || limit == .oneHundred
    }

    public static func normalized(
        _ limit: FixedChargeLimit,
        isAppleSilicon: Bool,
        operatingSystemVersion: OperatingSystemVersion
    ) -> FixedChargeLimit {
        permits(
            limit,
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion
        ) ? limit : .eighty
    }
}

public enum ChargeProtectionMode: String, Codable, Equatable, Sendable {
    case unsupportedHardware
    case systemPreferred
    case softwareAvailable
    case softwareManaged
}

public struct ChargeProtectionConfiguration: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schema: Int
    public var enabled: Bool
    public var fixedLimit: FixedChargeLimit
    public var temporaryFullCharge: Bool
    /// Records the user's explicit choice of controller. On macOS 26.4 and
    /// later the helper accepts SMC control only in `softwareManaged` mode.
    public var managementMode: ChargeProtectionMode
    /// Controls only the optional per-user menu-bar presentation. It does not
    /// change helper enforcement, so hiding the icon never disables protection.
    public var showMenuBarStatus: Bool
    public var updatedAt: Date
    public var revision: UUID?

    public init(
        enabled: Bool = false,
        fixedLimit: FixedChargeLimit = .defaultValue,
        temporaryFullCharge: Bool = false,
        managementMode: ChargeProtectionMode = .softwareAvailable,
        showMenuBarStatus: Bool = true,
        updatedAt: Date = Date(),
        revision: UUID? = nil
    ) {
        self.schema = Self.schemaVersion
        self.enabled = enabled
        self.fixedLimit = fixedLimit
        self.temporaryFullCharge = temporaryFullCharge
        self.managementMode = managementMode
        self.showMenuBarStatus = showMenuBarStatus
        self.updatedAt = updatedAt
        self.revision = revision
    }

    public mutating func renewRevision(now: Date = Date()) {
        updatedAt = now
        revision = UUID()
    }

    public var isValid: Bool { schema == Self.schemaVersion }

    private enum CodingKeys: String, CodingKey {
        case schema, enabled, fixedLimit, temporaryFullCharge, managementMode, showMenuBarStatus, updatedAt, revision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        fixedLimit = try container.decode(FixedChargeLimit.self, forKey: .fixedLimit)
        temporaryFullCharge = try container.decode(Bool.self, forKey: .temporaryFullCharge)
        // Existing 1.1.0 configurations predate controller selection. The
        // app normalizes this legacy value against the current OS before it
        // can be enabled; the helper still rejects it on macOS 26.4+.
        managementMode = try container.decodeIfPresent(ChargeProtectionMode.self, forKey: .managementMode) ?? .softwareAvailable
        // v1.1.0 configurations created before this preference existed must
        // preserve the documented default instead of becoming unreadable.
        showMenuBarStatus = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarStatus) ?? true
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        revision = try container.decodeIfPresent(UUID.self, forKey: .revision)
    }
}

public enum ChargeProtectionAvailability: Equatable, Sendable {
    case unsupportedHardware
    case systemPreferred
    case softwareAvailable
    case softwareManaged

    public static func evaluate(
        isAppleSilicon: Bool,
        operatingSystemVersion: OperatingSystemVersion,
        userSelectedSoftwareManagement: Bool = false
    ) -> Self {
        guard isAppleSilicon else { return .unsupportedHardware }
        if nativeLimitAvailable(on: operatingSystemVersion) {
            return userSelectedSoftwareManagement ? .softwareManaged : .systemPreferred
        }
        return .softwareAvailable
    }

    public var permitsSoftwareControls: Bool {
        self == .softwareAvailable || self == .softwareManaged
    }

    public static func helperMayControl(
        isAppleSilicon: Bool,
        operatingSystemVersion: OperatingSystemVersion,
        configuration: ChargeProtectionConfiguration
    ) -> Bool {
        guard isAppleSilicon, configuration.enabled, configuration.isValid else { return false }
        return !nativeLimitAvailable(on: operatingSystemVersion) || configuration.managementMode == .softwareManaged
    }

    public static func nativeLimitAvailable(on version: OperatingSystemVersion) -> Bool {
        version.majorVersion > 26 || (version.majorVersion == 26 && version.minorVersion >= 4)
    }
}

public struct ChargeBatteryReading: Equatable, Sendable {
    public let percentage: Int
    public let fullyCharged: Bool
    public let adapterConnected: Bool

    public init(percentage: Int, fullyCharged: Bool, adapterConnected: Bool) {
        self.percentage = min(100, max(0, percentage))
        self.fullyCharged = fullyCharged
        self.adapterConnected = adapterConnected
    }
}

public enum ChargeActuation: String, Codable, Equatable, Sendable {
    case allowCharging
    case holdCharging
    case unchanged
}

public enum ChargeStateEvent: String, Codable, Equatable, Sendable {
    case none
    case beganHolding
    case resumedBelowLimit
    case resumedAfterLimitIncrease
    case temporaryFullCompleted
    case disabledRestored
    case adapterDisconnectedRestored
}

public struct ChargeStateDecision: Equatable, Sendable {
    public let actuation: ChargeActuation
    public let holdingAfterDecision: Bool
    public let temporaryFullChargeAfterDecision: Bool
    public let event: ChargeStateEvent

    public init(
        actuation: ChargeActuation,
        holdingAfterDecision: Bool,
        temporaryFullChargeAfterDecision: Bool,
        event: ChargeStateEvent
    ) {
        self.actuation = actuation
        self.holdingAfterDecision = holdingAfterDecision
        self.temporaryFullChargeAfterDecision = temporaryFullChargeAfterDecision
        self.event = event
    }
}

public struct ChargeProtectionStateMachine: Sendable {
    public init() {}

    public func decide(
        configuration: ChargeProtectionConfiguration,
        battery: ChargeBatteryReading,
        holdingLimit: FixedChargeLimit?
    ) -> ChargeStateDecision {
        let isCurrentlyHolding = holdingLimit != nil
        guard configuration.enabled else {
            return ChargeStateDecision(
                actuation: isCurrentlyHolding ? .allowCharging : .unchanged,
                holdingAfterDecision: false,
                temporaryFullChargeAfterDecision: false,
                event: isCurrentlyHolding ? .disabledRestored : .none
            )
        }

        guard battery.adapterConnected else {
            return ChargeStateDecision(
                actuation: isCurrentlyHolding ? .allowCharging : .unchanged,
                holdingAfterDecision: false,
                temporaryFullChargeAfterDecision: configuration.temporaryFullCharge,
                event: isCurrentlyHolding ? .adapterDisconnectedRestored : .none
            )
        }

        if configuration.temporaryFullCharge {
            if battery.fullyCharged || battery.percentage >= 100 {
                let shouldHold = battery.percentage >= configuration.fixedLimit.rawValue
                return ChargeStateDecision(
                    actuation: shouldHold ? .holdCharging : .allowCharging,
                    holdingAfterDecision: shouldHold,
                    temporaryFullChargeAfterDecision: false,
                    event: .temporaryFullCompleted
                )
            }
            return ChargeStateDecision(
                actuation: isCurrentlyHolding ? .allowCharging : .unchanged,
                holdingAfterDecision: false,
                temporaryFullChargeAfterDecision: true,
                event: .none
            )
        }

        let upper = configuration.fixedLimit.rawValue
        if battery.percentage >= upper {
            return ChargeStateDecision(
                actuation: isCurrentlyHolding ? .unchanged : .holdCharging,
                holdingAfterDecision: true,
                temporaryFullChargeAfterDecision: false,
                event: isCurrentlyHolding ? .none : .beganHolding
            )
        }
        // Raising the limit while the battery is below the new target must
        // release the old hold immediately and retain its distinct event.
        if let holdingLimit,
           configuration.fixedLimit.rawValue > holdingLimit.rawValue {
            return ChargeStateDecision(
                actuation: .allowCharging,
                holdingAfterDecision: false,
                temporaryFullChargeAfterDecision: false,
                event: .resumedAfterLimitIncrease
            )
        }
        // Battery percentages are integer readings. Resume as soon as the
        // reading falls below the selected limit (for example, 79% for an
        // 80% limit) so the control behaves like a fixed cap without a broad
        // and potentially confusing discharge band.
        if isCurrentlyHolding && battery.percentage < upper {
            return ChargeStateDecision(
                actuation: .allowCharging,
                holdingAfterDecision: false,
                temporaryFullChargeAfterDecision: false,
                event: .resumedBelowLimit
            )
        }
        return ChargeStateDecision(
            actuation: .unchanged,
            holdingAfterDecision: isCurrentlyHolding,
            temporaryFullChargeAfterDecision: false,
            event: .none
        )
    }
}

public enum ChargeControlMethod: String, Codable, Sendable {
    case powerUIOptimized80
    case chte
    case legacyCH0BCH0C
    case chieFallback
    case unavailable
}

/// Chooses an adapter-preserving runtime-probed SMC control path. CHTE inhibits
/// battery charging while leaving the power adapter available to the Mac.
/// The legacy CH0B/CH0C pair has the same behavior on older Apple Silicon
/// firmware. CHIE is deliberately not selected for ordinary charge limiting:
/// it isolates the adapter on some systems and makes macOS report that power
/// disappeared. The parameter remains for source compatibility with older
/// callers and for diagnostic comparisons.
public func preferredChargeControlMethod(
    chteSupported: Bool,
    legacyCH0BCH0CSupported: Bool,
    chieSupported: Bool
) -> ChargeControlMethod {
    if chteSupported { return .chte }
    if legacyCH0BCH0CSupported { return .legacyCH0BCH0C }
    _ = chieSupported
    return .unavailable
}

/// Distinguishes an actual removal from the short interval in which Finder or
/// an installer replaces an application bundle during an update.
public struct ApplicationRemovalMonitor: Sendable {
    public let graceInterval: TimeInterval
    private var missingSince: Date?

    public init(graceInterval: TimeInterval = 180) {
        self.graceInterval = graceInterval
    }

    public mutating func shouldCleanUp(applicationExists: Bool, now: Date = Date()) -> Bool {
        if applicationExists {
            missingSince = nil
            return false
        }
        guard let missingSince else {
            self.missingSince = now
            return false
        }
        return now.timeIntervalSince(missingSince) >= graceInterval
    }
}

public enum SystemChargeOverrideState: String, Codable, Sendable {
    case inactive
    case chargingToFull
    case awaitingConfirmation

    public var defersChargeControl: Bool { self != .inactive }
}

/// Tracks explicit system intent separately from this application's override.
/// A lost read cannot revoke a full-charge request we have already observed.
/// No SOC threshold (including 100%) can end it; only an explicit false read.
public struct SystemChargeOverrideTracker {
    public private(set) var state: SystemChargeOverrideState?

    public init() {}

    @discardableResult
    public mutating func observe(temporarilyDisabled: Bool?) -> SystemChargeOverrideState? {
        switch temporarilyDisabled {
        case true?: state = .chargingToFull
        case false?: state = .inactive
        case nil:
            state = state?.defersChargeControl == true ? .awaitingConfirmation : nil
        }
        return state
    }
}

public enum SystemCalibrationState: String, Codable, Sendable {
    case inactive
    case calibrating
    case awaitingConfirmation

    public var defersChargeControl: Bool { self != .inactive }
}

/// A negative gauging notification only ends the reported limit suspension;
/// it cannot establish "calibration completed" or "protection restored".
public struct SystemCalibrationTracker {
    public private(set) var state: SystemCalibrationState?

    public init() {}

    @discardableResult
    public mutating func observe(limitSuspended: Bool?) -> SystemCalibrationState? {
        switch limitSuspended {
        case true?: state = .calibrating
        case false?: state = .inactive
        case nil: state = state?.defersChargeControl == true ? .awaitingConfirmation : nil
        }
        return state
    }
}

public enum PowerUIOwnershipLeaseState: String, Codable, Equatable, Sendable {
    case preEngaging
    case activeEighty
    case restoredTopOff
    case deferredToSystem
}

public struct PowerUIOwnershipMarker: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let identifier = "com.chengxin.drivebatteryhealthviewer.chargehelper"

    public let schema: Int
    public let helperIdentifier: String
    public let targetPercentage: Int
    public let lastKnownBatteryPercentage: Int?
    public let leaseState: PowerUIOwnershipLeaseState

    public init(leaseState: PowerUIOwnershipLeaseState = .activeEighty, lastKnownBatteryPercentage: Int?) {
        self.schema = Self.schemaVersion
        self.helperIdentifier = Self.identifier
        self.targetPercentage = 80
        self.lastKnownBatteryPercentage = lastKnownBatteryPercentage
        self.leaseState = leaseState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        helperIdentifier = try container.decode(String.self, forKey: .helperIdentifier)
        targetPercentage = try container.decode(Int.self, forKey: .targetPercentage)
        lastKnownBatteryPercentage = try container.decodeIfPresent(Int.self, forKey: .lastKnownBatteryPercentage)
        leaseState = try container.decodeIfPresent(PowerUIOwnershipLeaseState.self, forKey: .leaseState) ?? .activeEighty
    }

    public var isValid: Bool {
        schema == Self.schemaVersion && helperIdentifier == Self.identifier &&
            targetPercentage == 80 && lastKnownBatteryPercentage.map { (0...100).contains($0) } != false
    }
}

public enum PowerUIOwnershipInspection: Equatable, Sendable {
    case unowned
    case owned(PowerUIOwnershipMarker)
    case corrupted(String)
}

public func inspectPowerUIOwnershipFile(at url: URL, requireRoot: Bool = true) -> PowerUIOwnershipInspection {
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else {
        return errno == ENOENT ? .unowned : .corrupted("Unable to open the ownership marker")
    }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var information = stat()
    guard fstat(descriptor, &information) == 0,
          information.st_mode & S_IFMT == S_IFREG, information.st_nlink == 1,
          !requireRoot || (information.st_uid == 0 && information.st_gid == 0),
          information.st_mode & 0o7777 == 0o600,
          (1...4096).contains(information.st_size) else {
        return .corrupted("Unsafe ownership marker metadata")
    }
    guard let data = try? file.read(upToCount: 4097), data.count <= 4096,
          let marker = try? JSONDecoder().decode(PowerUIOwnershipMarker.self, from: data),
          marker.isValid else {
        return .corrupted("Invalid ownership marker contents")
    }
    return .owned(marker)
}

public enum PowerUIOwnershipStore {
    public static func write(_ marker: PowerUIOwnershipMarker, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        var template = directory.appendingPathComponent(".powerui-owner.XXXXXX").path.utf8CString
        let descriptor = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard descriptor >= 0 else { throw posixError() }
        let temporaryPath = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { _ = unlink(temporaryPath) }
        guard fchmod(descriptor, 0o600) == 0 else { throw posixError() }
        if geteuid() == 0 {
            guard fchown(descriptor, 0, 0) == 0 else { throw posixError() }
        }
        try file.write(contentsOf: JSONEncoder().encode(marker))
        try file.synchronize()
        try file.close()
        guard rename(temporaryPath, url.path) == 0 else { throw posixError() }
        try syncDirectory(directory)
    }

    public static func remove(at url: URL) throws {
        guard unlink(url.path) == 0 || errno == ENOENT else { throw posixError() }
        try syncDirectory(url.deletingLastPathComponent())
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

public enum PowerUIOwnershipBaseline: Equatable, Sendable {
    case clean, restoredTopOff, system, unknown, other
}

/// A provisional marker is never accepted as authority, even after a restart.
public func acquirePowerUIOwnership(
    inspection: PowerUIOwnershipInspection,
    baseline: PowerUIOwnershipBaseline,
    percentage: Int,
    persist: (PowerUIOwnershipMarker) throws -> Void,
    retire: () throws -> Void,
    engage: (Bool) -> Bool,
    restore: () -> Bool
) throws -> Bool {
    guard (1..<100).contains(percentage), baseline != .system, baseline != .unknown else { return false }
    let ownsPolicy: Bool
    switch inspection {
    case .owned(let marker) where marker.leaseState == .activeEighty:
        ownsPolicy = baseline != .clean
    case .owned(let marker) where marker.leaseState == .restoredTopOff && baseline == .restoredTopOff:
        ownsPolicy = true
    case .unowned, .owned:
        guard baseline == .clean else { return false }
        ownsPolicy = false
    case .corrupted:
        return false
    }

    if !ownsPolicy {
        try persist(PowerUIOwnershipMarker(leaseState: .preEngaging, lastKnownBatteryPercentage: percentage))
    }
    guard engage(ownsPolicy) else {
        // The failed request gives no authority over the visible policy.
        if !ownsPolicy { try retire() }
        return false
    }
    do {
        try persist(PowerUIOwnershipMarker(lastKnownBatteryPercentage: percentage))
        return true
    } catch {
        if !ownsPolicy {
            // Only the newly acknowledged, in-process request authorizes this
            // restoration. Retire provisional evidence even if it fails.
            let restored = restore()
            try retire()
            if !restored { throw CocoaError(.fileWriteUnknown) }
        }
        throw error
    }
}

/// The caller verifies both parent directories before invoking this operation.
public func migratePowerUIOwnership(
    marker: URL, backup: URL, preparing: Bool, requireRoot: Bool = true,
    baseline: () -> PowerUIOwnershipBaseline
) throws {
    if preparing {
        switch inspectPowerUIOwnershipFile(at: marker, requireRoot: requireRoot) {
        case .unowned: return
        case .owned(let previous): try PowerUIOwnershipStore.write(previous, to: backup)
        case .corrupted: throw CocoaError(.fileReadCorruptFile)
        }
        return
    }

    let inspection = inspectPowerUIOwnershipFile(at: backup, requireRoot: requireRoot)
    if case .corrupted = inspection { throw CocoaError(.fileReadCorruptFile) }
    let current = inspectPowerUIOwnershipFile(at: marker, requireRoot: requireRoot)
    if case .corrupted = current { throw CocoaError(.fileReadCorruptFile) }
    if case .unowned = inspection, case .unowned = current { return }
    switch baseline() {
    case .clean, .system:
        try PowerUIOwnershipStore.remove(at: marker)
    case .restoredTopOff:
        guard case .owned(let previous) = inspection,
              previous.leaseState == .activeEighty || previous.leaseState == .restoredTopOff else {
            try PowerUIOwnershipStore.remove(at: marker)
            return
        }
        try PowerUIOwnershipStore.write(PowerUIOwnershipMarker(
            leaseState: .restoredTopOff, lastKnownBatteryPercentage: previous.lastKnownBatteryPercentage
        ), to: marker)
    case .unknown, .other:
        throw CocoaError(.fileReadUnknown)
    }
}

public let verifiedPowerUIMacOSBuilds: Set<String> = ["24H212"]
public func isVerifiedPowerUIMacOSBuild(_ buildVersion: String) -> Bool {
    verifiedPowerUIMacOSBuilds.contains(buildVersion)
}

public func currentOSBuildVersion() -> String? {
    var size: Int = 0
    sysctlbyname("kern.osversion", nil, &size, nil, 0)
    guard size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}

public struct PowerUIOverchargeMonitor: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case belowLimitScheduled
        case establishingHold
        case confirmedHolding
        case abnormalChargingPastLimit(String)
        case armedAt100
        case unmanaged
    }

    public private(set) var state: State = .unmanaged
    private var establishingStartedAt: ContinuousClock.Instant?
    private var baselinePercentageAtOrAbove80: Int?
    private var reassertAttempts: Int = 0
    private var engagedChargingStartedAt: ContinuousClock.Instant?

    public init() {}

    public mutating func reset() {
        state = .unmanaged
        establishingStartedAt = nil
        baselinePercentageAtOrAbove80 = nil
        reassertAttempts = 0
        engagedChargingStartedAt = nil
    }

    public mutating func update(
        batteryPercentage: Int,
        isCharging: Bool,
        checkpoint: Int32,
        engaged: Bool,
        managed: Bool,
        didAttemptReassert: Bool = false,
        now: ContinuousClock.Instant = .now
    ) -> State {
        // 100% Boundary
        if batteryPercentage >= 100 {
            establishingStartedAt = nil
            baselinePercentageAtOrAbove80 = nil
            reassertAttempts = 0
            engagedChargingStartedAt = nil
            if checkpoint == 2 && engaged {
                state = .confirmedHolding
                return .confirmedHolding
            } else {
                state = .armedAt100
                return .armedAt100
            }
        }

        // Below 80% limit
        if batteryPercentage < 80 {
            establishingStartedAt = nil
            baselinePercentageAtOrAbove80 = nil
            reassertAttempts = 0
            engagedChargingStartedAt = nil
            state = .belowLimitScheduled
            return .belowLimitScheduled
        }

        // Battery is >= 80% and < 100%
        // Case A: Holding confirmed and current stopped
        if checkpoint == 2 && engaged && !isCharging {
            establishingStartedAt = nil
            baselinePercentageAtOrAbove80 = nil
            reassertAttempts = 0
            engagedChargingStartedAt = nil
            state = .confirmedHolding
            return .confirmedHolding
        }

        // Case B: PowerUI says engaged (checkpoint 2, engaged=1), but hardware reports isCharging == true
        if checkpoint == 2 && engaged && isCharging {
            establishingStartedAt = nil
            baselinePercentageAtOrAbove80 = nil
            reassertAttempts = 0
            if let started = engagedChargingStartedAt {
                if now >= started.advanced(by: .seconds(60)) {
                    let msg = "PowerUI accepted the 80% request, but the battery is still charging past 80%"
                    state = .abnormalChargingPastLimit(msg)
                    return state
                }
            } else {
                engagedChargingStartedAt = now
            }
            state = .establishingHold
            return .establishingHold
        } else {
            engagedChargingStartedAt = nil
        }

        // Case C: Battery is >= 80%, not yet holding
        // If not charging (e.g. on AC but battery paused/idle), not actively overcharging
        if !isCharging {
            establishingStartedAt = nil
            baselinePercentageAtOrAbove80 = nil
            reassertAttempts = 0
            state = managed ? .establishingHold : .unmanaged
            return state
        }

        // Actively charging at >= 80% without confirmed hold
        if establishingStartedAt == nil {
            establishingStartedAt = now
            baselinePercentageAtOrAbove80 = batteryPercentage
            reassertAttempts = didAttemptReassert ? 1 : 0
        } else if didAttemptReassert {
            reassertAttempts += 1
        }

        // Check overcharge conditions:
        // 1. Net battery percentage increased by >= 2% while charging past 80%
        if let base = baselinePercentageAtOrAbove80, (batteryPercentage - base) >= 2 {
            let msg = managed
                ? "PowerUI accepted the 80% request, but the battery is still charging past 80%"
                : "The 80% limit is not managed by PowerUI and the battery is actively charging past 80%"
            state = .abnormalChargingPastLimit(msg)
            return state
        }

        // 2. Over 45 seconds AND >= 2 reassertion attempts without stopping charging
        // (Or 75 seconds timeout if retry backoff prevented multiple attempts)
        if let start = establishingStartedAt {
            if (now >= start.advanced(by: .seconds(45)) && reassertAttempts >= 2) ||
               now >= start.advanced(by: .seconds(75)) {
                let msg = managed
                    ? "PowerUI accepted the 80% request, but the battery is still charging past 80%"
                    : "The 80% limit is not managed by PowerUI and the battery is actively charging past 80%"
                state = .abnormalChargingPastLimit(msg)
                return state
            }
        }

        state = .establishingHold
        return .establishingHold
    }
}

public struct PowerUIProtectionCoordinator: Sendable {
    public struct Input: Equatable, Sendable {
        public var batteryPercentage: Int
        public var isCharging: Bool?
        public var adapterConnected: Bool
        public var systemAdapterConnected: Bool?
        public var checkpoint: Int32
        public var engaged: Bool
        public var temporarilyDisabled: Bool
        public var calibrationSuspended: Bool
        public var hasOwnership: Bool
        public var isHoldApplied: Bool
        public var pauseSignalsKnown: Bool
        public var powerUIActive: Bool

        public init(
            batteryPercentage: Int,
            isCharging: Bool?,
            adapterConnected: Bool,
            systemAdapterConnected: Bool?,
            checkpoint: Int32,
            engaged: Bool,
            temporarilyDisabled: Bool = false,
            calibrationSuspended: Bool = false,
            hasOwnership: Bool = true,
            isHoldApplied: Bool = false,
            pauseSignalsKnown: Bool = true,
            powerUIActive: Bool = true
        ) {
            self.batteryPercentage = batteryPercentage
            self.isCharging = isCharging
            self.adapterConnected = adapterConnected
            self.systemAdapterConnected = systemAdapterConnected
            self.checkpoint = checkpoint
            self.engaged = engaged
            self.temporarilyDisabled = temporarilyDisabled
            self.calibrationSuspended = calibrationSuspended
            self.hasOwnership = hasOwnership
            self.isHoldApplied = isHoldApplied
            self.pauseSignalsKnown = pauseSignalsKnown
            self.powerUIActive = powerUIActive
        }
    }

    public struct Decision: Equatable, Sendable {
        public var request: PowerUIRequestSchedule.Request?
        public var managed: Bool
        public var holding: Bool
        public var policyConfirmed: Bool
        public var overchargeState: PowerUIOverchargeMonitor.State
        public var errorMessage: String?
    }

    private var schedule = PowerUIRequestSchedule()
    private var overchargeMonitor = PowerUIOverchargeMonitor()

    private var rejectedRequest = false
    private var attemptedRecovery = false
    private var holdObservedAt: ContinuousClock.Instant?

    public init() {}

    public mutating func reset() {
        rejectedRequest = false
        attemptedRecovery = false
        holdObservedAt = nil
        schedule = PowerUIRequestSchedule()
        overchargeMonitor.reset()
    }

    public func isManaged(input: Input) -> Bool {
        guard input.hasOwnership, input.pauseSignalsKnown, input.powerUIActive,
              !input.temporarilyDisabled,
              !input.calibrationSuspended else { return false }
        let needsRecovery = PowerUIRequestSchedule.needsCheckpointRecovery(
            checkpoint: input.checkpoint,
            engaged: input.engaged,
            batteryPercentage: input.batteryPercentage
        )
        if needsRecovery { return false }
        return input.checkpoint == 1 || (input.checkpoint == 2 && input.engaged)
    }

    public mutating func record(
        _ request: PowerUIRequestSchedule.Request,
        accepted: Bool,
        observed input: Input,
        now: ContinuousClock.Instant = .now
    ) {
        guard input.adapterConnected, input.systemAdapterConnected == true,
              !input.temporarilyDisabled, !input.calibrationSuspended else {
            reset()
            return
        }
        if (80..<100).contains(input.batteryPercentage), policyConfirmed(input) {
            holdObservedAt = holdObservedAt ?? now
        }
        attemptedRecovery = request == .recover
        rejectedRequest = !accepted
        // Checkpoint 1 is sufficient while charging toward the limit. Once at
        // or above it, only Checkpoint 2 plus actual stopped charging ends retry.
        schedule.record(succeeded: accepted && policyConfirmed(input), now: now)
    }

    private func policyConfirmed(_ input: Input) -> Bool {
        guard input.adapterConnected, input.systemAdapterConnected == true, isManaged(input: input) else {
            return false
        }
        return input.batteryPercentage < 80 ||
            (input.batteryPercentage < 100 && input.isHoldApplied && input.isCharging == false)
    }

    public mutating func evaluate(
        input: Input,
        didAttemptReassert: Bool = false,
        now: ContinuousClock.Instant = .now
    ) -> Decision {
        guard input.adapterConnected, input.systemAdapterConnected == true, input.pauseSignalsKnown,
              !input.temporarilyDisabled, !input.calibrationSuspended else {
            if !input.adapterConnected || input.systemAdapterConnected == false ||
                input.temporarilyDisabled || input.calibrationSuspended {
                reset()
            } else {
                // An unreadable sample must not erase a retry already on backoff.
                holdObservedAt = nil
                overchargeMonitor.reset()
            }
            return Decision(request: nil, managed: false, holding: false, policyConfirmed: false,
                            overchargeState: .unmanaged, errorMessage: nil)
        }
        let managed = isManaged(input: input)
        let overchargeState: PowerUIOverchargeMonitor.State
        if let isCharging = input.isCharging {
            overchargeState = overchargeMonitor.update(
                batteryPercentage: input.batteryPercentage,
                isCharging: isCharging,
                checkpoint: input.checkpoint,
                engaged: input.engaged && managed,
                managed: managed,
                didAttemptReassert: attemptedRecovery || didAttemptReassert,
                now: now
            )
        } else {
            overchargeMonitor.reset()
            overchargeState = .unmanaged
        }
        attemptedRecovery = false
        let error: String?
        let abnormal: Bool
        if case .abnormalChargingPastLimit(let message) = overchargeState {
            error = message
            abnormal = true
        } else {
            abnormal = false
            error = rejectedRequest && !policyConfirmed(input) && input.batteryPercentage < 100
                ? "Native PowerUI 80% engagement failed" : nil
        }
        let request = schedule.request(
            adapterConnected: input.adapterConnected,
            systemAdapterConnected: input.systemAdapterConnected,
            batteryPercentage: input.batteryPercentage,
            managed: managed && !abnormal,
            checkpoint: input.checkpoint,
            engaged: input.engaged,
            now: now
        )
        let verified = !abnormal && policyConfirmed(input)
        if verified && input.batteryPercentage >= 80 {
            holdObservedAt = holdObservedAt ?? now
        } else {
            holdObservedAt = nil
        }
        // Require a second independent battery sample before reporting a hold.
        let holding = holdObservedAt.map { $0.duration(to: now) >= .seconds(4) } ?? false
        let confirmed = holding || (verified && input.batteryPercentage < 80)
        return Decision(request: request, managed: managed && !abnormal,
                        holding: holding, policyConfirmed: confirmed,
                        overchargeState: overchargeState, errorMessage: error)
    }
}

public struct ChargeProtectionStatus: Codable, Equatable, Sendable {
    public static let freshnessWindow: TimeInterval = 20

    /// Age zero is valid. The upper limit is exclusive and future reports
    /// provide no evidence of current state.
    public func isFresh(at now: Date, maximumAge: TimeInterval = freshnessWindow) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= 0 && age < maximumAge
    }

    public var helperVersion: String
    public var timestamp: Date
    public var installed: Bool
    public var enabled: Bool
    public var fixedLimit: FixedChargeLimit
    public var temporaryFullCharge: Bool
    public var configurationUpdatedAt: Date?
    public var configurationRevision: UUID?
    public var holding: Bool
    public var adapterConnected: Bool?
    public var batteryPercentage: Int?
    public var controlMethod: ChargeControlMethod
    public var lastError: String?
    /// Optional for compatibility with Helpers predating system-menu overrides.
    public var systemChargeOverride: SystemChargeOverrideState?
    public var systemCalibration: SystemCalibrationState?
    /// Native policy acknowledgement, independent of the saved configuration and of reaching 80%.
    public var powerUIPolicyConfirmed: Bool?

    public init(
        helperVersion: String,
        timestamp: Date = Date(),
        installed: Bool,
        enabled: Bool,
        fixedLimit: FixedChargeLimit,
        temporaryFullCharge: Bool,
        configurationUpdatedAt: Date? = nil,
        configurationRevision: UUID? = nil,
        holding: Bool,
        adapterConnected: Bool?,
        batteryPercentage: Int?,
        controlMethod: ChargeControlMethod,
        lastError: String? = nil,
        systemChargeOverride: SystemChargeOverrideState? = nil,
        systemCalibration: SystemCalibrationState? = nil,
        powerUIPolicyConfirmed: Bool? = nil
    ) {
        self.helperVersion = helperVersion
        self.timestamp = timestamp
        self.installed = installed
        self.enabled = enabled
        self.fixedLimit = fixedLimit
        self.temporaryFullCharge = temporaryFullCharge
        self.configurationUpdatedAt = configurationUpdatedAt
        self.configurationRevision = configurationRevision
        self.holding = holding
        self.adapterConnected = adapterConnected
        self.batteryPercentage = batteryPercentage
        self.controlMethod = controlMethod
        self.lastError = lastError
        self.systemChargeOverride = systemChargeOverride
        self.systemCalibration = systemCalibration
        self.powerUIPolicyConfirmed = powerUIPolicyConfirmed
    }
}

/// Share the same freshness and configuration checks across both interfaces.
public func resolvedSystemChargeOverride(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date(),
    maximumStatusAge: TimeInterval = ChargeProtectionStatus.freshnessWindow
) -> SystemChargeOverrideState? {
    matchingSystemControlStatus(configuration: configuration, status: status, now: now,
                                maximumStatusAge: maximumStatusAge)?.systemChargeOverride
}

public func resolvedSystemCalibration(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date(),
    maximumStatusAge: TimeInterval = ChargeProtectionStatus.freshnessWindow
) -> SystemCalibrationState? {
    matchingSystemControlStatus(configuration: configuration, status: status, now: now,
                                maximumStatusAge: maximumStatusAge)?.systemCalibration
}

private func matchingSystemControlStatus(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date,
    maximumStatusAge: TimeInterval
) -> ChargeProtectionStatus? {
    guard configuration.fixedLimit == .eighty,
          let status = matchingAppliedChargeStatus(configuration: configuration, status: status,
                                                  now: now, maximumStatusAge: maximumStatusAge),
          status.controlMethod == .powerUIOptimized80 else { return nil }
    return status
}

/// Match the applied revision, accounting for the on-disk ISO8601 precision.
public func matchingAppliedChargeStatus(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date(),
    maximumStatusAge: TimeInterval = ChargeProtectionStatus.freshnessWindow
) -> ChargeProtectionStatus? {
    guard configuration.enabled else { return nil }
    return matchingChargeConfigurationReport(configuration: configuration, status: status,
                                             now: now, maximumStatusAge: maximumStatusAge)
}

public func matchingChargeConfigurationReport(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date(),
    maximumStatusAge: TimeInterval = ChargeProtectionStatus.freshnessWindow
) -> ChargeProtectionStatus? {
    guard configuration.isValid,
          let status, status.installed, status.enabled == configuration.enabled,
          status.fixedLimit == configuration.fixedLimit,
          let appliedAt = status.configurationUpdatedAt, appliedAt <= now,
          status.configurationRevision == configuration.revision,
          abs(appliedAt.timeIntervalSince(configuration.updatedAt)) < 1,
          status.isFresh(at: now, maximumAge: maximumStatusAge) else { return nil }
    return status
}

public func hasCurrentChargeProtectionReport(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date()
) -> Bool {
    guard let status = matchingAppliedChargeStatus(configuration: configuration, status: status, now: now) else { return false }
    guard status.controlMethod != .unavailable,
          status.temporaryFullCharge == configuration.temporaryFullCharge else { return false }
    guard status.controlMethod == .powerUIOptimized80 else { return true }
    if configuration.temporaryFullCharge { return true }
    // A known pause is actionable even if the other signal is unknown.
    return status.systemCalibration?.defersChargeControl == true ||
        status.systemChargeOverride?.defersChargeControl == true ||
        (status.powerUIPolicyConfirmed != false &&
         status.systemCalibration == .inactive && status.systemChargeOverride == .inactive)
}

public func currentChargeProtectionError(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date()
) -> String? {
    guard let message = matchingChargeConfigurationReport(configuration: configuration, status: status, now: now)?
        .lastError?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else { return nil }
    return message
}

public func confirmsTemporaryFullCharge(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date()
) -> Bool {
    guard configuration.temporaryFullCharge,
          let report = matchingAppliedChargeStatus(configuration: configuration, status: status, now: now) else { return false }
    return report.temporaryFullCharge && report.lastError == nil && report.controlMethod != .unavailable
}

public func shouldPresentChargeLimitStatusItem(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date(),
    maximumStatusAge: TimeInterval = ChargeProtectionStatus.freshnessWindow
) -> Bool {
    guard configuration.fixedLimit != .oneHundred, !configuration.temporaryFullCharge,
          configuration.managementMode == .softwareAvailable || configuration.managementMode == .softwareManaged,
          let status = matchingAppliedChargeStatus(configuration: configuration, status: status,
                                                  now: now, maximumStatusAge: maximumStatusAge),
          !status.temporaryFullCharge, status.lastError == nil, status.controlMethod != .unavailable,
          status.holding, status.adapterConnected == true,
          let percentage = status.batteryPercentage,
          (configuration.fixedLimit.rawValue...100).contains(percentage),
          status.systemCalibration?.defersChargeControl != true,
          status.systemChargeOverride?.defersChargeControl != true else { return false }
    if status.controlMethod == .powerUIOptimized80 {
        return configuration.fixedLimit == .eighty && status.powerUIPolicyConfirmed != false &&
            status.systemCalibration == .inactive &&
            status.systemChargeOverride == .inactive
    }
    return true
}

public enum ChargeLimitHoldPosition: Equatable {
    case atLimit
    case aboveLimit
}

public func resolvedChargeLimitHoldPosition(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date()
) -> ChargeLimitHoldPosition? {
    guard shouldPresentChargeLimitStatusItem(configuration: configuration, status: status, now: now),
          let percentage = status?.batteryPercentage else { return nil }
    return percentage == configuration.fixedLimit.rawValue ? .atLimit : .aboveLimit
}

/// A fresh report can acknowledge the current configuration before PowerUI
/// reapplies its policy. At 100%, the helper waits for a representable reading.
public func pendingPowerUIPolicyReport(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date()
) -> ChargeProtectionStatus? {
    guard !configuration.temporaryFullCharge,
          let status = matchingAppliedChargeStatus(configuration: configuration, status: status, now: now),
          status.controlMethod == .powerUIOptimized80, !status.temporaryFullCharge,
          status.powerUIPolicyConfirmed == false, status.lastError == nil,
          status.systemCalibration == .inactive, status.systemChargeOverride == .inactive else { return nil }
    return status
}

public func shouldPresentPowerUIRecoveryStatusItem(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date()
) -> Bool {
    guard configuration.showMenuBarStatus,
          !configuration.temporaryFullCharge,
          let status = matchingAppliedChargeStatus(configuration: configuration, status: status, now: now),
          status.controlMethod == .powerUIOptimized80,
          status.adapterConnected == true,
          status.systemCalibration?.defersChargeControl != true,
          status.systemChargeOverride?.defersChargeControl != true else { return false }
    return status.powerUIPolicyConfirmed == false &&
        currentChargeProtectionError(configuration: configuration, status: status, now: now) != nil
}

public func shouldPresentCalibrationStatusItem(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date()
) -> Bool {
    configuration.showMenuBarStatus &&
        resolvedSystemCalibration(configuration: configuration, status: status, now: now)?.defersChargeControl == true
}

/// A separate adapter observation for presentation alongside the system reading.
public func helperReportsConnectedAdapter(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date()
) -> Bool {
    guard configuration.enabled, let status, status.installed, status.enabled,
          status.adapterConnected == true else { return false }
    return status.isFresh(at: now)
}
