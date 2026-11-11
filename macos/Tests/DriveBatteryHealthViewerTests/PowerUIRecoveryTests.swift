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
        try PowerUIOwnershipStore.write(marker, to: ownerURL)
        let inspection = inspectPowerUIOwnershipFile(at: ownerURL, requireRoot: false)
        if case .owned(let readMarker) = inspection {
            #expect(readMarker.leaseState == .activeEighty)
            #expect(readMarker.lastKnownBatteryPercentage == 80)
        } else {
            #expect(Bool(false), "Expected owned, got \(inspection)")
        }

        // Owned restoredTopOff
        let topOffMarker = PowerUIOwnershipMarker(leaseState: .restoredTopOff, lastKnownBatteryPercentage: 85)
        try PowerUIOwnershipStore.write(topOffMarker, to: ownerURL)
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

    @Test func coordinatorTransits79To80Checkpoint1To2WithAccurateUIPresentation() {
        var coordinator = PowerUIProtectionCoordinator()
        let t0 = ContinuousClock.now

        // At 78% in Checkpoint 1 (charging towards 80%): managed = true, no recovery request, policyConfirmed = true
        let input78 = PowerUIProtectionCoordinator.Input(
            batteryPercentage: 78,
            isCharging: true,
            adapterConnected: true,
            systemAdapterConnected: true,
            checkpoint: 1,
            engaged: false
        )
        let d78 = coordinator.evaluate(input: input78, now: t0)
        #expect(d78.managed == true)
        #expect(d78.request == .renew) // Initial unrecorded schedule requests first engagement/renew
        #expect(d78.policyConfirmed == true)
        #expect(d78.holding == false)
        #expect(d78.overchargeState == .belowLimitScheduled)

        // Record initial success
        coordinator.record(.renew, accepted: true, observed: input78, now: t0)

        // At 79%: throttled by 4-hour window, request is nil, policyConfirmed = true
        let input79 = PowerUIProtectionCoordinator.Input(
            batteryPercentage: 79,
            isCharging: true,
            adapterConnected: true,
            systemAdapterConnected: true,
            checkpoint: 1,
            engaged: false
        )
        let d79 = coordinator.evaluate(input: input79, now: t0.advanced(by: .seconds(60)))
        #expect(d79.managed == true)
        #expect(d79.request == nil)
        #expect(d79.policyConfirmed == true)
        #expect(d79.holding == false)
        #expect(d79.overchargeState == .belowLimitScheduled)

        // At 80% in Checkpoint 1 (engaged == false):
        // MUST trigger immediate .recover request, and policyConfirmed MUST be false!
        let input80 = PowerUIProtectionCoordinator.Input(
            batteryPercentage: 80,
            isCharging: true,
            adapterConnected: true,
            systemAdapterConnected: true,
            checkpoint: 1,
            engaged: false
        )
        let d80 = coordinator.evaluate(input: input80, didAttemptReassert: true, now: t0.advanced(by: .seconds(120)))
        #expect(d80.managed == false) // Needs recovery, so managed is false!
        #expect(d80.request == .recover) // Immediate recovery request generated!
        #expect(d80.policyConfirmed == false) // UI presents waiting for confirmation, NOT false active!
        #expect(d80.holding == false)
        #expect(d80.overchargeState == .establishingHold)

        let config = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty)
        let statusUnconfirmed = ChargeProtectionStatus(
            helperVersion: "1.1.2.3",
            installed: true,
            enabled: true,
            fixedLimit: .eighty,
            temporaryFullCharge: false,
            configurationUpdatedAt: config.updatedAt,
            configurationRevision: config.revision,
            holding: false,
            adapterConnected: true,
            batteryPercentage: 80,
            controlMethod: .powerUIOptimized80,
            systemChargeOverride: .inactive,
            systemCalibration: .inactive,
            powerUIPolicyConfirmed: d80.policyConfirmed
        )
        #expect(!hasCurrentChargeProtectionReport(configuration: config, status: statusUnconfirmed))
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: config, status: statusUnconfirmed) == .protectionUnconfirmed)

        // Recovery succeeds: system enters Checkpoint 2 (engaged == true, isCharging == false)
        let input80Held = PowerUIProtectionCoordinator.Input(
            batteryPercentage: 80,
            isCharging: false,
            adapterConnected: true,
            systemAdapterConnected: true,
            checkpoint: 2,
            engaged: true,
            isHoldApplied: true
        )
        coordinator.record(.recover, accepted: true, observed: input80Held, now: t0.advanced(by: .seconds(125)))
        let d80Held = coordinator.evaluate(input: input80Held, now: t0.advanced(by: .seconds(130)))
        #expect(d80Held.managed == true)
        #expect(d80Held.holding == true)
        #expect(d80Held.policyConfirmed == true)
        #expect(d80Held.overchargeState == .confirmedHolding)

        // Check Agent presentation for held: resolves to .limitReached
        let statusHeld = ChargeProtectionStatus(
            helperVersion: "1.1.2.3",
            installed: true,
            enabled: true,
            fixedLimit: .eighty,
            temporaryFullCharge: false,
            configurationUpdatedAt: config.updatedAt,
            configurationRevision: config.revision,
            holding: true,
            adapterConnected: true,
            batteryPercentage: 80,
            controlMethod: .powerUIOptimized80,
            systemChargeOverride: .inactive,
            systemCalibration: .inactive,
            powerUIPolicyConfirmed: d80Held.policyConfirmed
        )
        #expect(hasCurrentChargeProtectionReport(configuration: config, status: statusHeld))
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: config, status: statusHeld) == .limitReached)
    }

    @Test func overchargeMonitorTracksUnmanagedOverchargeAndAvoidsPremature15sAlarm() {
        var monitor = PowerUIOverchargeMonitor()
        let t0 = ContinuousClock.now

        // 1. Unmanaged state (managed == false, e.g. expired to Checkpoint 6 or unmanaged initial failure)
        // At 82%, isCharging == true: MUST track establishingHold, not reset to .unmanaged!
        #expect(monitor.update(
            batteryPercentage: 82,
            isCharging: true,
            checkpoint: 6,
            engaged: false,
            managed: false,
            didAttemptReassert: true,
            now: t0
        ) == .establishingHold)

        // Net percentage jump of +2% while unmanaged: fires abnormalChargingPastLimit immediately
        let overchargeUnmanaged = monitor.update(
            batteryPercentage: 84,
            isCharging: true,
            checkpoint: 6,
            engaged: false,
            managed: false,
            didAttemptReassert: false,
            now: t0.advanced(by: .seconds(10))
        )
        if case .abnormalChargingPastLimit(let msg) = overchargeUnmanaged {
            #expect(msg.contains("not managed by PowerUI"))
        } else {
            #expect(Bool(false), "Expected unmanaged overcharge alarm, got \(overchargeUnmanaged)")
        }

        // 2. Managed state in Checkpoint 1 at 80%
        monitor.reset()
        // Poll 1 at t = 0 (first reassert)
        #expect(monitor.update(
            batteryPercentage: 80,
            isCharging: true,
            checkpoint: 1,
            engaged: false,
            managed: true,
            didAttemptReassert: true,
            now: t0
        ) == .establishingHold)

        // Poll 2 at t = 5s (no reassert)
        #expect(monitor.update(
            batteryPercentage: 80,
            isCharging: true,
            checkpoint: 1,
            engaged: false,
            managed: true,
            didAttemptReassert: false,
            now: t0.advanced(by: .seconds(5))
        ) == .establishingHold)

        // Poll 3 at t = 10s (reassert retry)
        #expect(monitor.update(
            batteryPercentage: 80,
            isCharging: true,
            checkpoint: 1,
            engaged: false,
            managed: true,
            didAttemptReassert: true,
            now: t0.advanced(by: .seconds(10))
        ) == .establishingHold)

        // Poll 4 at t = 15s: In build 49, this falsely tripped overcharge!
        // In build 50: MUST stay in .establishingHold because 45s has not elapsed!
        #expect(monitor.update(
            batteryPercentage: 80,
            isCharging: true,
            checkpoint: 1,
            engaged: false,
            managed: true,
            didAttemptReassert: false,
            now: t0.advanced(by: .seconds(15))
        ) == .establishingHold)

        // Poll at t = 44s: still within 45s window
        #expect(monitor.update(
            batteryPercentage: 80,
            isCharging: true,
            checkpoint: 1,
            engaged: false,
            managed: true,
            didAttemptReassert: false,
            now: t0.advanced(by: .seconds(44))
        ) == .establishingHold)

        // Poll at t = 45s with >= 2 reassertions completed: accurately trips .abnormalChargingPastLimit!
        let overchargeTrip = monitor.update(
            batteryPercentage: 80,
            isCharging: true,
            checkpoint: 1,
            engaged: false,
            managed: true,
            didAttemptReassert: false,
            now: t0.advanced(by: .seconds(45))
        )
        if case .abnormalChargingPastLimit(let msg) = overchargeTrip {
            #expect(msg.contains("PowerUI accepted the 80% request, but the battery is still charging"))
        } else {
            #expect(Bool(false), "Expected overcharge trip at 45s, got \(overchargeTrip)")
        }
    }

    @Test func legacyBuild47MarkerDecodesAndRetainsOwnership() throws {
        // Build 47 marker had schema 1 without leaseState
        let legacyJSON = """
        {
            "schema": 1,
            "helperIdentifier": "com.chengxin.drivebatteryhealthviewer.chargehelper",
            "targetPercentage": 80,
            "lastKnownBatteryPercentage": 75
        }
        """
        let data = try #require(legacyJSON.data(using: .utf8))
        let marker = try JSONDecoder().decode(PowerUIOwnershipMarker.self, from: data)
        #expect(marker.schema == 1)
        #expect(marker.helperIdentifier == "com.chengxin.drivebatteryhealthviewer.chargehelper")
        #expect(marker.targetPercentage == 80)
        #expect(marker.lastKnownBatteryPercentage == 75)
        #expect(marker.leaseState == .activeEighty) // Defaults to .activeEighty
        #expect(marker.isValid)
    }

    @Test func acceptedCheckpointOneAt80BacksOffUntilHardwareConfirmsHold() {
        let now = ContinuousClock.now
        var input = PowerUIProtectionCoordinator.Input(
            batteryPercentage: 80, isCharging: true, adapterConnected: true, systemAdapterConnected: true,
            checkpoint: 1, engaged: false
        )
        var coordinator = PowerUIProtectionCoordinator()
        #expect(coordinator.evaluate(input: input, now: now).request == .recover)
        coordinator.record(.recover, accepted: true, observed: input, now: now)
        let waiting = coordinator.evaluate(input: input, now: now.advanced(by: .seconds(5)))
        #expect(waiting.request == nil)
        #expect(waiting.errorMessage == nil)
        #expect(!waiting.policyConfirmed)
        #expect(coordinator.evaluate(input: input, now: now.advanced(by: .seconds(10))).request == .recover)

        input.checkpoint = 2
        input.engaged = true
        input.isHoldApplied = true
        input.isCharging = false
        coordinator.record(.recover, accepted: true, observed: input, now: now.advanced(by: .seconds(10)))
        let transient = coordinator.evaluate(input: input, now: now.advanced(by: .seconds(11)))
        #expect(!transient.holding && !transient.policyConfirmed)
        let holding = coordinator.evaluate(input: input, now: now.advanced(by: .seconds(15)))
        #expect(holding.holding && holding.policyConfirmed)
        #expect(holding.request == nil)
    }

    @Test func engagedControllerWithSustainedChargingBypassesRenewalInterval() {
        let now = ContinuousClock.now
        var input = PowerUIProtectionCoordinator.Input(
            batteryPercentage: 81, isCharging: false, adapterConnected: true, systemAdapterConnected: true,
            checkpoint: 2, engaged: true, isHoldApplied: true
        )
        var coordinator = PowerUIProtectionCoordinator()
        coordinator.record(.renew, accepted: true, observed: input, now: now)
        input.isCharging = true
        let first = coordinator.evaluate(input: input, now: now)
        #expect(first.request == nil && !first.policyConfirmed && first.errorMessage == nil)
        let abnormal = coordinator.evaluate(input: input, now: now.advanced(by: .seconds(60)))
        #expect(abnormal.request == .recover && !abnormal.holding && !abnormal.policyConfirmed)
        #expect(abnormal.errorMessage != nil)
        coordinator.record(.recover, accepted: true, observed: input, now: now.advanced(by: .seconds(60)))
        #expect(coordinator.evaluate(input: input, now: now.advanced(by: .seconds(65))).request == nil)

        input.isCharging = nil
        let missingTelemetry = coordinator.evaluate(input: input, now: now.advanced(by: .seconds(66)))
        #expect(!missingTelemetry.policyConfirmed)
        input.pauseSignalsKnown = false
        let unknown = coordinator.evaluate(input: input, now: now.advanced(by: .seconds(120)))
        #expect(!unknown.policyConfirmed && unknown.request == nil)
    }

    @Test func firstAcquisitionDoesNotClaimSystemPolicyAfterFailedRequest() throws {
        var inspection: PowerUIOwnershipInspection = .unowned
        var calls: [String] = []
        func attempt(_ baseline: PowerUIOwnershipBaseline) throws -> Bool {
            try acquirePowerUIOwnership(
                inspection: inspection, baseline: baseline, percentage: 80,
                persist: { marker in calls.append(marker.leaseState.rawValue); inspection = .owned(marker) },
                retire: { calls.append("retire"); inspection = .unowned },
                engage: { owned in calls.append("engage-owned=\(owned)"); return false },
                restore: { calls.append("restore"); return true }
            )
        }
        #expect(try !attempt(.unknown))
        #expect(try !attempt(.restoredTopOff))
        #expect(calls.isEmpty)
        #expect(try !attempt(.clean))
        #expect(calls == ["preEngaging", "engage-owned=false", "retire"])
        #expect(inspection == .unowned)
        #expect(try !attempt(.restoredTopOff))
        #expect(calls == ["preEngaging", "engage-owned=false", "retire"])
    }

    @Test func failedOwnershipPromotionCannotReportSuccess() {
        var calls: [String] = []
        #expect(throws: CocoaError.self) {
            try acquirePowerUIOwnership(
                inspection: .unowned, baseline: .clean, percentage: 79,
                persist: { marker in
                    calls.append(marker.leaseState.rawValue)
                    if marker.leaseState == .activeEighty { throw CocoaError(.fileWriteNoPermission) }
                },
                retire: { calls.append("retire") },
                engage: { owned in calls.append("engage-owned=\(owned)"); return true },
                restore: { calls.append("restore"); return true }
            )
        }
        #expect(calls == ["preEngaging", "engage-owned=false", "activeEighty", "restore", "retire"])
    }

    @Test func markerStoreReportsReplacementAndRemovalFailures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("marker.json")
        let record = PowerUIOwnershipMarker(lastKnownBatteryPercentage: 80)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
        #expect(throws: POSIXError.self) { try PowerUIOwnershipStore.write(record, to: marker) }
        #expect(throws: POSIXError.self) { try PowerUIOwnershipStore.remove(at: marker) }
        let missingParent = marker.appendingPathComponent("missing/record.json")
        #expect(throws: POSIXError.self) { try PowerUIOwnershipStore.write(record, to: missingParent) }
        try FileManager.default.removeItem(at: marker)
        try PowerUIOwnershipStore.write(record, to: marker)
        #expect(inspectPowerUIOwnershipFile(at: marker, requireRoot: false) == .owned(record))
        let symlink = directory.appendingPathComponent("symbolic-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: marker)
        guard case .corrupted = inspectPowerUIOwnershipFile(at: symlink, requireRoot: false) else {
            Issue.record("The marker inspection accepted a symbolic link")
            return
        }
        try PowerUIOwnershipStore.remove(at: marker)
        #expect(inspectPowerUIOwnershipFile(at: marker, requireRoot: false) == .unowned)
    }
}
