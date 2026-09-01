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

    public init(
        enabled: Bool = false,
        fixedLimit: FixedChargeLimit = .defaultValue,
        temporaryFullCharge: Bool = false,
        managementMode: ChargeProtectionMode = .softwareAvailable,
        showMenuBarStatus: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.schema = Self.schemaVersion
        self.enabled = enabled
        self.fixedLimit = fixedLimit
        self.temporaryFullCharge = temporaryFullCharge
        self.managementMode = managementMode
        self.showMenuBarStatus = showMenuBarStatus
        self.updatedAt = updatedAt
    }

    public var isValid: Bool { schema == Self.schemaVersion }

    private enum CodingKeys: String, CodingKey {
        case schema, enabled, fixedLimit, temporaryFullCharge, managementMode, showMenuBarStatus, updatedAt
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

public struct ChargeProtectionStatus: Codable, Equatable, Sendable {
    public var helperVersion: String
    public var timestamp: Date
    public var installed: Bool
    public var enabled: Bool
    public var fixedLimit: FixedChargeLimit
    public var temporaryFullCharge: Bool
    public var configurationUpdatedAt: Date?
    public var holding: Bool
    public var adapterConnected: Bool?
    public var batteryPercentage: Int?
    public var controlMethod: ChargeControlMethod
    public var lastError: String?

    public init(
        helperVersion: String,
        timestamp: Date = Date(),
        installed: Bool,
        enabled: Bool,
        fixedLimit: FixedChargeLimit,
        temporaryFullCharge: Bool,
        configurationUpdatedAt: Date? = nil,
        holding: Bool,
        adapterConnected: Bool?,
        batteryPercentage: Int?,
        controlMethod: ChargeControlMethod,
        lastError: String? = nil
    ) {
        self.helperVersion = helperVersion
        self.timestamp = timestamp
        self.installed = installed
        self.enabled = enabled
        self.fixedLimit = fixedLimit
        self.temporaryFullCharge = temporaryFullCharge
        self.configurationUpdatedAt = configurationUpdatedAt
        self.holding = holding
        self.adapterConnected = adapterConnected
        self.batteryPercentage = batteryPercentage
        self.controlMethod = controlMethod
        self.lastError = lastError
    }
}

public func shouldPresentChargeLimitStatusItem(
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?
) -> Bool {
    guard configuration.enabled, !configuration.temporaryFullCharge,
          let status, status.holding, status.adapterConnected == true else { return false }
    return (status.batteryPercentage ?? 0) >= configuration.fixedLimit.rawValue
}

/// Resolves the user-facing adapter state when a CHIE fallback deliberately
/// makes AppleSmartBattery report `ExternalConnected=false`. The helper has an
/// independent SMC adapter reading, but it is trusted only while protection is
/// enabled and the observation is recent; stale state can never make an
/// unplugged adapter appear connected.
public func resolvedExternalPowerConnection(
    systemReportedConnection: Bool,
    configuration: ChargeProtectionConfiguration,
    status: ChargeProtectionStatus?,
    now: Date = Date(),
    maximumStatusAge: TimeInterval = 20
) -> Bool {
    if systemReportedConnection { return true }
    guard configuration.enabled,
          let status,
          status.adapterConnected == true,
          abs(now.timeIntervalSince(status.timestamp)) < maximumStatusAge else { return false }
    return true
}
