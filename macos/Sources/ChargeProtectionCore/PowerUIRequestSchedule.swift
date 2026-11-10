/// Uses elapsed time that includes sleep, independent of wall-clock changes.
public struct PowerUIRequestSchedule {
    public enum Request: Equatable {
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
        managed: Bool,
        now: ContinuousClock.Instant = .now
    ) -> Request? {
        guard adapterConnected, retryAfter.map({ now >= $0 }) ?? true else { return nil }
        if !managed { return .recover }
        if let lastSuccess, lastSuccess.duration(to: now) < .seconds(4 * 60 * 60) { return nil }
        return .renew
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
