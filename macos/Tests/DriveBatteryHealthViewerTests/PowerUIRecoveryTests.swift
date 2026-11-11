import ChargeProtectionCore
import Foundation
import Testing
@testable import DriveBatteryChargeLimitAgent
@testable import DriveBatteryHealthViewer

struct PowerUIRecoveryTests {
    @Test func expiredAndClearedRequestsRecoverAfterLongDisconnection() {
        let start = ContinuousClock.now
        var schedule = PowerUIRequestSchedule()
        schedule.record(succeeded: true, now: start)
        let reconnect = start.advanced(by: .seconds(25 * 60 * 60))
        #expect(schedule.request(adapterConnected: false, systemAdapterConnected: false, batteryPercentage: 70, managed: false, now: reconnect) == nil)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: false, now: reconnect) == .recover)
        schedule.record(succeeded: true, now: reconnect)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: true, now: reconnect) == nil)

        // A later system clear invalidates the policy even before the four-hour renewal.
        let cleared = reconnect.advanced(by: .seconds(60))
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: false, now: cleared) == .recover)
    }

    @Test func elapsedSleepAndHelperRestartRevalidatePolicy() {
        let start = ContinuousClock.now
        var schedule = PowerUIRequestSchedule()
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: false, now: start) == .recover)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: true, now: start) == .renew)
        schedule.record(succeeded: true, now: start)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: true,
                                 now: start.advanced(by: .seconds(14_399))) == nil)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: true,
                                 now: start.advanced(by: .seconds(14_400))) == .renew)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: false,
                                 now: start.advanced(by: .seconds(86_401))) == .recover)
    }

    @Test func boundedFailuresDoNotSpinAndSuccessfulRecoveryClearsBackoff() {
        let start = ContinuousClock.now
        var schedule = PowerUIRequestSchedule()
        var now = start
        for delay in [10, 30, 60, 120, 300, 300] {
            #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: false, now: now) == .recover)
            schedule.record(succeeded: false, now: now)
            #expect(schedule.hasFailed)
            #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: false,
                                     now: now.advanced(by: .seconds(delay - 1))) == nil)
            now = now.advanced(by: .seconds(delay))
        }
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: false, now: now) == .recover)
        schedule.record(succeeded: true, now: now)
        #expect(!schedule.hasFailed)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: true, now: now) == nil)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 70, managed: false, now: now) == .recover)
    }

    @Test func nativeRequestWaitsForRepresentableLevelAndMatchingAdapterSignals() {
        let schedule = PowerUIRequestSchedule()
        for managed in [false, true] {
            #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true,
                                     batteryPercentage: 100, managed: managed) == nil)
            #expect(schedule.request(adapterConnected: true, systemAdapterConnected: false,
                                     batteryPercentage: 99, managed: managed) == nil)
            #expect(schedule.request(adapterConnected: true, systemAdapterConnected: nil,
                                     batteryPercentage: 99, managed: managed) == nil)
            #expect(schedule.request(adapterConnected: false, systemAdapterConnected: true,
                                     batteryPercentage: 99, managed: managed) == nil)
        }
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true,
                                 batteryPercentage: 99, managed: false) == .recover)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true,
                                 batteryPercentage: 99, managed: true) == .renew)
    }

    @Test(arguments: AgentLanguage.allCases.filter { $0 != .system })
    func aboveLimitCopyMatchesAcrossSurfaces(_ language: AgentLanguage) throws {
        let appLanguage = try #require(AppLanguage(rawValue: language.rawValue))
        let copy = String(format: AgentL10n.text("aboveLimit", language: language), 80)
        #expect(copy.contains("80%"))
        #expect(copy != AgentL10n.reached(80, language: language))
        #expect(copy == L10n.format("chargeAboveLimit", appLanguage, 80))
    }

    @MainActor
    @Test func bothSurfacesShowRecoveryFailureAndConfirmedHold() {
        let now = Date()
        let config = ChargeProtectionConfiguration(
            enabled: true, fixedLimit: .eighty, showMenuBarStatus: true,
            updatedAt: now, revision: UUID()
        )
        var report = ChargeProtectionStatus(
            helperVersion: "test", timestamp: now, installed: true, enabled: true, fixedLimit: .eighty,
            temporaryFullCharge: false, configurationUpdatedAt: now, configurationRevision: config.revision,
            holding: false, adapterConnected: true, batteryPercentage: 92, controlMethod: .powerUIOptimized80,
            systemChargeOverride: .inactive, systemCalibration: .inactive, powerUIPolicyConfirmed: false
        )
        func reason() -> BatteryPowerNoticeReason? {
            BatteryPowerNoticeReason.resolve(externalConnected: true, isCharging: false, batteryPercentage: 92,
                                             configuration: config, status: report, now: now)
        }
        func agentState() -> ChargeLimitAgentPresentationState {
            .resolve(configuration: config, status: report, now: now)
        }

        #expect(!hasCurrentChargeProtectionReport(configuration: config, status: report, now: now))
        #expect(!shouldPresentPowerUIRecoveryStatusItem(configuration: config, status: report, now: now))
        #expect(pendingPowerUIPolicyReport(configuration: config, status: report, now: now) != nil)
        #expect(agentState() == .protectionUnconfirmed)
        #expect(reason() == .ordinary)
        report.lastError = "Native PowerUI 80% engagement failed"
        #expect(currentChargeProtectionError(configuration: config, status: report, now: now) == report.lastError)
        #expect(shouldPresentPowerUIRecoveryStatusItem(configuration: config, status: report, now: now))
        #expect(agentState() == .attentionRequired)
        #expect(reason() == .ordinary)
        report.lastError = nil
        report.powerUIPolicyConfirmed = true
        #expect(!shouldPresentPowerUIRecoveryStatusItem(configuration: config, status: report, now: now))
        #expect(agentState() == .protectionActive)
        #expect(reason() == .ordinary)
        report.holding = true
        #expect(agentState() == .aboveLimit)
        #expect(reason() == .aboveLimit)
        report.batteryPercentage = 100
        #expect(agentState() == .aboveLimit)
        report.batteryPercentage = 80
        #expect(agentState() == .limitReached)
        report.powerUIPolicyConfirmed = false
        #expect(agentState() == .protectionUnconfirmed)
        #expect(reason() == .ordinary)
        report.systemCalibration = .calibrating
        #expect(!shouldPresentPowerUIRecoveryStatusItem(configuration: config, status: report, now: now))
        #expect(agentState() == .systemCalibration)
        report.systemCalibration = .inactive
        report.systemChargeOverride = .chargingToFull
        #expect(!shouldPresentPowerUIRecoveryStatusItem(configuration: config, status: report, now: now))
        #expect(agentState() == .systemTemporaryFullCharge)
    }

    @Test func oneHundredPercentCheckpoint6DoesNotLoopAndRecoversAt99Percent() {
        let schedule = PowerUIRequestSchedule()
        // At 100%, schedule never requests recovery or renewal
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 100, managed: false) == nil)
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 100, managed: true) == nil)
        #expect(!needsCheckpointRecovery(checkpoint: 6, engaged: false, batteryPercentage: 100))

        // When discharged to 99%, recovery is immediately required
        #expect(needsCheckpointRecovery(checkpoint: 6, engaged: false, batteryPercentage: 99))
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 99, managed: false) == .recover)
    }

    @Test func crossingFrom79To80InCheckpoint1TriggersImmediateRecovery() {
        #expect(!needsCheckpointRecovery(checkpoint: 1, engaged: false, batteryPercentage: 79))
        #expect(needsCheckpointRecovery(checkpoint: 1, engaged: false, batteryPercentage: 80))
        let schedule = PowerUIRequestSchedule()
        #expect(schedule.request(adapterConnected: true, systemAdapterConnected: true, batteryPercentage: 80, managed: false) == .recover)
    }

    @Test func overchargeMonitorDistinguishesEstablishingHoldingAndAbnormalCharging() {
        var monitor = PowerUIOverchargeMonitor()
        let t0 = ContinuousClock.now

        // Below 80%
        #expect(monitor.update(batteryPercentage: 75, isCharging: true, checkpoint: 1, engaged: false, managed: true, now: t0) == .belowLimitScheduled)

        // At 80%, checkpoint 2 holding
        #expect(monitor.update(batteryPercentage: 80, isCharging: false, checkpoint: 2, engaged: true, managed: true, now: t0) == .confirmedHolding)

        // At 80%, checkpoint 1 still charging (establishing)
        #expect(monitor.update(batteryPercentage: 80, isCharging: true, checkpoint: 1, engaged: false, managed: true, now: t0) == .establishingHold)

        // After +2% net overcharge while still charging
        let overcharge = monitor.update(batteryPercentage: 82, isCharging: true, checkpoint: 1, engaged: false, managed: true, now: t0.advanced(by: .seconds(10)))
        if case .abnormalChargingPastLimit = overcharge {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected abnormalChargingPastLimit, got \(overcharge)")
        }

        // At 100% boundary
        monitor.reset()
        #expect(monitor.update(batteryPercentage: 100, isCharging: false, checkpoint: 1, engaged: false, managed: true, now: t0) == .armedAt100)
        #expect(monitor.update(batteryPercentage: 100, isCharging: false, checkpoint: 2, engaged: true, managed: true, now: t0) == .confirmedHolding)
    }

    @Test func ownershipInspectionDistinguishesUnownedOwnedRestoredTopOffAndCorrupted() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dbhv-test-owner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let ownerURL = tempDir.appendingPathComponent("powerui-owner.json")

        // Unowned when file does not exist
        #expect(inspectPowerUIOwnershipFile(at: ownerURL, requireRoot: false) == .unowned)

        // Owned activeEighty
        let marker = PowerUIOwnershipMarker(leaseState: .activeEighty, lastKnownBatteryPercentage: 80)
        let data = try JSONEncoder().encode(marker)
        try data.write(to: ownerURL)
        let inspection = inspectPowerUIOwnershipFile(at: ownerURL, requireRoot: false)
        if case .owned(let readMarker) = inspection {
            #expect(readMarker.leaseState == .activeEighty)
            #expect(readMarker.lastKnownBatteryPercentage == 80)
        } else {
            #expect(Bool(false), "Expected owned, got \(inspection)")
        }

        // Owned restoredTopOff
        let topOffMarker = PowerUIOwnershipMarker(leaseState: .restoredTopOff, lastKnownBatteryPercentage: 85)
        try JSONEncoder().encode(topOffMarker).write(to: ownerURL)
        if case .owned(let readMarker) = inspectPowerUIOwnershipFile(at: ownerURL, requireRoot: false) {
            #expect(readMarker.leaseState == .restoredTopOff)
            #expect(readMarker.lastKnownBatteryPercentage == 85)
        } else {
            #expect(Bool(false), "Expected owned restoredTopOff")
        }

        // Corrupted
        try "invalid json".write(to: ownerURL, atomically: true, encoding: .utf8)
        if case .corrupted = inspectPowerUIOwnershipFile(at: ownerURL, requireRoot: false) {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected corrupted")
        }
    }
}
