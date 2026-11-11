/// Uses elapsed time that includes sleep, independent of wall-clock changes.
public struct PowerUIRequestSchedule: Sendable {
    public enum Request: Equatable, Sendable {
        case recover
        case renew
    }

    private var lastSuccess: ContinuousClock.Instant?
    private var retryAfter: ContinuousClock.Instant?
    private var failures = 0

    public var hasFailed: Bool { failures > 0 }

    public init() {}

    public func request(
        adapterConnected: Bool,
        systemAdapterConnected: Bool?,
        batteryPercentage: Int,
        managed: Bool,
        checkpoint: Int32? = nil,
        engaged: Bool? = nil,
        now: ContinuousClock.Instant = .now
    ) -> Request? {
        guard adapterConnected, systemAdapterConnected == true, (1..<100).contains(batteryPercentage),
              retryAfter.map({ now >= $0 }) ?? true else { return nil }
        let effectiveManaged: Bool
        if let checkpoint, let engaged {
            effectiveManaged = managed && !Self.needsCheckpointRecovery(checkpoint: checkpoint, engaged: engaged, batteryPercentage: batteryPercentage)
        } else {
            effectiveManaged = managed
        }
        if !effectiveManaged { return .recover }
        if let lastSuccess, lastSuccess.duration(to: now) < .seconds(4 * 60 * 60) { return nil }
        return .renew
    }

    public static func needsCheckpointRecovery(
        checkpoint: Int32,
        engaged: Bool,
        batteryPercentage: Int = 80
    ) -> Bool {
        guard (1..<100).contains(batteryPercentage) else { return false }
        if batteryPercentage >= 80 {
            return !engaged && (checkpoint == 0 || checkpoint == 1 || checkpoint == 2 || checkpoint == 5 || checkpoint == 6)
        } else {
            return !engaged && (checkpoint == 0 || checkpoint == 5 || checkpoint == 6)
        }
    }

    public func needsCheckpointRecovery(
        checkpoint: Int32,
        engaged: Bool,
        batteryPercentage: Int = 80
    ) -> Bool {
        Self.needsCheckpointRecovery(checkpoint: checkpoint, engaged: engaged, batteryPercentage: batteryPercentage)
    }

    public mutating func record(succeeded: Bool, now: ContinuousClock.Instant = .now) {
        if succeeded {
            lastSuccess = now
            failures = 0
            retryAfter = nil
        } else {
            let retryDelays = [10, 30, 60, 120, 300]
            let delay = retryDelays[failures]
            failures = min(failures + 1, retryDelays.count - 1)
            retryAfter = now.advanced(by: .seconds(delay))
        }
    }
}

public func needsCheckpointRecovery(
    checkpoint: Int32,
    engaged: Bool,
    batteryPercentage: Int = 80
) -> Bool {
    PowerUIRequestSchedule.needsCheckpointRecovery(checkpoint: checkpoint, engaged: engaged, batteryPercentage: batteryPercentage)
}
