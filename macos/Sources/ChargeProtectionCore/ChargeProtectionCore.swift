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

    public let schema: Int
    public let helperIdentifier: String
    public let targetPercentage: Int
    public let lastKnownBatteryPercentage: Int?
    public let leaseState: PowerUIOwnershipLeaseState

    public init(
        lastKnownBatteryPercentage: Int?,
        leaseState: PowerUIOwnershipLeaseState = .activeEighty,
        helperIdentifier: String = "com.drivebatteryhealthviewer.chargehelper"
    ) {
        self.schema = Self.schemaVersion
        self.helperIdentifier = helperIdentifier
        self.targetPercentage = 80
        self.lastKnownBatteryPercentage = lastKnownBatteryPercentage.flatMap {
            (0...100).contains($0) ? $0 : nil
        }
        self.leaseState = leaseState
    }

    public init(
        leaseState: PowerUIOwnershipLeaseState = .activeEighty,
        lastKnownBatteryPercentage: Int?,
        helperIdentifier: String = "com.drivebatteryhealthviewer.chargehelper"
    ) {
        self.init(
            lastKnownBatteryPercentage: lastKnownBatteryPercentage,
            leaseState: leaseState,
            helperIdentifier: helperIdentifier
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schema = try container.decode(Int.self, forKey: .schema)
        self.helperIdentifier = try container.decode(String.self, forKey: .helperIdentifier)
        self.targetPercentage = try container.decode(Int.self, forKey: .targetPercentage)
        self.lastKnownBatteryPercentage = try container.decodeIfPresent(Int.self, forKey: .lastKnownBatteryPercentage)
        self.leaseState = try container.decodeIfPresent(PowerUIOwnershipLeaseState.self, forKey: .leaseState) ?? .activeEighty
    }

    public var isValid: Bool {
        schema == Self.schemaVersion &&
            !helperIdentifier.isEmpty &&
            targetPercentage == 80 &&
            lastKnownBatteryPercentage.map { (0...100).contains($0) } != false
    }
}

public enum PowerUIOwnershipInspection: Equatable, Sendable {
    case unowned
    case owned(PowerUIOwnershipMarker)
    case corrupted(String)
}

public func inspectPowerUIOwnershipFile(at url: URL, requireRoot: Bool = true) -> PowerUIOwnershipInspection {
    var information = stat()
    guard lstat(url.path, &information) == 0 else {
        return .unowned
    }
    guard (information.st_mode & S_IFMT) == S_IFREG else {
        return .corrupted("Not a regular file")
    }
    if requireRoot && information.st_uid != 0 {
        return .corrupted("File not owned by root (uid \(information.st_uid))")
    }
    if (information.st_mode & 0o022) != 0 {
        return .corrupted("Insecure permissions on marker file (\(String(information.st_mode, radix: 8)))")
    }
    guard let data = try? Data(contentsOf: url) else {
        return .corrupted("Unable to read marker file data")
    }
    guard let marker = try? JSONDecoder().decode(PowerUIOwnershipMarker.self, from: data) else {
        return .corrupted("Invalid JSON format in marker file")
    }
    guard marker.isValid else {
        return .corrupted("Marker contents failed validation")
    }
    return .owned(marker)
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
        now: ContinuousClock.Instant = .now
    ) -> State {
        guard managed else {
            reset()
            return .unmanaged
        }

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
        if checkpoint == 2 && engaged && !isCharging {
            establishingStartedAt = nil
            baselinePercentageAtOrAbove80 = nil
            reassertAttempts = 0
            engagedChargingStartedAt = nil
            state = .confirmedHolding
            return .confirmedHolding
        }

        // Check if engaged is true but isCharging is still true (PMU current settling)
        if checkpoint == 2 && engaged && isCharging {
            if let started = engagedChargingStartedAt {
                if now >= started.advanced(by: .seconds(60)) {
                    let msg = "PowerUI accepted the 80% request, but the battery is still charging past 80%"
                    state = .abnormalChargingPastLimit(msg)
                    return state
                }
            } else {
                engagedChargingStartedAt = now
            }
        } else {
            engagedChargingStartedAt = nil
        }

        // If not engaged or still settling
        if establishingStartedAt == nil {
            establishingStartedAt = now
            baselinePercentageAtOrAbove80 = batteryPercentage
            reassertAttempts = 1
        } else {
            reassertAttempts += 1
        }

        // Check overcharge conditions:
        // 1. Net battery percentage increased by >= 2% while charging past 80%
        if let base = baselinePercentageAtOrAbove80, isCharging && (batteryPercentage - base) >= 2 {
            let msg = "PowerUI accepted the 80% request, but the battery is still charging past 80%"
            state = .abnormalChargingPastLimit(msg)
            return state
        }

        // 2. Over 45 seconds or >= 3 re-assert attempts without disengaging
        if let start = establishingStartedAt, isCharging {
            if now >= start.advanced(by: .seconds(45)) || reassertAttempts > 3 {
                let msg = "PowerUI accepted the 80% request, but the battery is still charging past 80%"
                state = .abnormalChargingPastLimit(msg)
                return state
            }
        }

        state = .establishingHold
        return .establishingHold
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
