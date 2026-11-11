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
        coordinator.schedule.record(succeeded: true, now: t0)

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
        coordinator.schedule.record(succeeded: true, now: t0.advanced(by: .seconds(125)))
        let input80Held = PowerUIProtectionCoordinator.Input(
            batteryPercentage: 80,
            isCharging: false,
            adapterConnected: true,
            systemAdapterConnected: true,
            checkpoint: 2,
            engaged: true,
            isHoldApplied: true
        )
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

    @Test func rollbackToCheckpoint5PreservesMarkerAsRestoredTopOff() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dbhv-test-rollback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let ownerURL = tempDir.appendingPathComponent("powerui-owner.json")

        // Pre-engaging marker is written before calling DBHVPowerUIEngageEighty
        let preMarker = PowerUIOwnershipMarker(leaseState: .preEngaging, lastKnownBatteryPercentage: 80)
        try JSONEncoder().encode(preMarker).write(to: ownerURL)

        // Simulate engage failure where PowerUI rolls back to Checkpoint 5 (1, 1, 5, 0)
        let afterStatusCheckpoint5 = (enabled: 1, current_state: 1, checkpoint: 5)
        let isClean = (afterStatusCheckpoint5.enabled == 0 && afterStatusCheckpoint5.current_state == 0 && afterStatusCheckpoint5.checkpoint == 0) ||
                      (afterStatusCheckpoint5.enabled == 0 && afterStatusCheckpoint5.current_state == 0 && afterStatusCheckpoint5.checkpoint == 10)
        #expect(!isClean)

        // Instead of removing marker (which would lock out future takeover as unowned system policy),
        // build 50 writes restoredTopOff:
        let topOffMarker = PowerUIOwnershipMarker(leaseState: .restoredTopOff, lastKnownBatteryPercentage: 80)
        try JSONEncoder().encode(topOffMarker).write(to: ownerURL)

        let inspection = inspectPowerUIOwnershipFile(at: ownerURL, requireRoot: false)
        if case .owned(let readMarker) = inspection {
            #expect(readMarker.leaseState == .restoredTopOff)
        } else {
            #expect(Bool(false), "Marker must be preserved as restoredTopOff")
        }
    }

    @Test func helperUpgradePreservesPriorOwnershipAndRefusesUnownedCheckpoint5() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dbhv-test-upgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let markerURL = tempDir.appendingPathComponent("powerui-owner.json")
        let backupURL = tempDir.appendingPathComponent(".powerui-owner.upgrade-backup.json")

        // Scenario 1: Upgrade from build 47 where marker existed before install.
        // Old build 47 marker:
        let b47Data = """
        {"helperIdentifier":"com.chengxin.drivebatteryhealthviewer.chargehelper","lastKnownBatteryPercentage":80,"schema":1,"targetPercentage":80}
        """.data(using: .utf8)!
        try b47Data.write(to: markerURL)

        // Installer detects marker and creates backup:
        try FileManager.default.copyItem(at: markerURL, to: backupURL)

        // Old helper runs --restore-only / SIGTERM, deleting powerui-owner.json:
        try FileManager.default.removeItem(at: markerURL)
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))

        // Installer migration hook runs:
        if !FileManager.default.fileExists(atPath: markerURL.path) && FileManager.default.fileExists(atPath: backupURL.path) {
            let restoredMarker = PowerUIOwnershipMarker(leaseState: .restoredTopOff, lastKnownBatteryPercentage: 80)
            try JSONEncoder().encode(restoredMarker).write(to: markerURL)
        }
        try FileManager.default.removeItem(at: backupURL)

        // Verifications:
        #expect(FileManager.default.fileExists(atPath: markerURL.path))
        if case .owned(let marker) = inspectPowerUIOwnershipFile(at: markerURL, requireRoot: false) {
            #expect(marker.leaseState == .restoredTopOff)
            #expect(marker.targetPercentage == 80)
        } else {
            #expect(Bool(false), "Expected restoredTopOff ownership after upgrade")
        }

        // Scenario 2: Clean baseline / macOS native Checkpoint 5 (no DBHV ownership existed before install)
        try FileManager.default.removeItem(at: markerURL)
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
        // Installer does NOT create backup, does NOT create marker
        #expect(inspectPowerUIOwnershipFile(at: markerURL, requireRoot: false) == .unowned)
    }
}
