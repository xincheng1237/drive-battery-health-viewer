import Foundation
import ChargeProtectionCore
import Testing
@testable import DriveBatteryHealthViewer
@testable import DriveBatteryChargeLimitAgent

@Suite("System-menu full-charge requests")
struct SystemChargeOverrideTests {
    func fixture(now: Date = Date()) -> (ChargeProtectionConfiguration, ChargeProtectionStatus) {
        var configuration = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty)
        configuration.updatedAt = now.addingTimeInterval(-10)
        let status = ChargeProtectionStatus(
            helperVersion: "test", timestamp: now, installed: true, enabled: true,
            fixedLimit: .eighty, temporaryFullCharge: false,
            configurationUpdatedAt: configuration.updatedAt,
            holding: false, adapterConnected: true, batteryPercentage: 80,
            controlMethod: .powerUIOptimized80, systemChargeOverride: .chargingToFull, systemCalibration: .inactive
        )
        return (configuration, status)
    }

    @Test func explicitSystemRequestIsSeparateFromAppRequest() {
        let (configuration, status) = fixture()
        #expect(!configuration.temporaryFullCharge)
        #expect(resolvedSystemChargeOverride(configuration: configuration, status: status) == .chargingToFull)
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .systemTemporaryFullCharge)
        #expect(configuration.enabled && configuration.fixedLimit == .eighty)
    }

    @Test func systemOverrideSuppressesOldHoldingIcon() {
        var (configuration, status) = fixture()
        status.holding = true // Old holding observation must not win.
        #expect(!shouldPresentChargeLimitStatusItem(configuration: configuration, status: status))
        configuration.temporaryFullCharge = true
        #expect(!shouldPresentChargeLimitStatusItem(configuration: configuration, status: status))
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .systemTemporaryFullCharge)
    }

    @Test(arguments: [80, 98, 100])
    func batteryPercentageDoesNotEndSystemRequest(_ percentage: Int) {
        var (configuration, status) = fixture()
        status.batteryPercentage = percentage
        #expect(resolvedSystemChargeOverride(configuration: configuration, status: status) == .chargingToFull)
    }

    @Test func unknownReadDefersControlUntilExplicitEnd() {
        var tracker = SystemChargeOverrideTracker()
        #expect(tracker.observe(temporarilyDisabled: nil) == nil)
        #expect(tracker.observe(temporarilyDisabled: true) == .chargingToFull)
        #expect(tracker.observe(temporarilyDisabled: nil) == .awaitingConfirmation)
        #expect(tracker.state?.defersChargeControl == true)
        #expect(tracker.observe(temporarilyDisabled: false) == .inactive)
        #expect(tracker.state?.defersChargeControl == false)
    }

    @Test func confirmationStateIsInformational() {
        var (configuration, status) = fixture()
        status.systemChargeOverride = .awaitingConfirmation
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .systemFullChargeAwaitingConfirmation)
        #expect(!shouldPresentChargeLimitStatusItem(configuration: configuration, status: status))
    }

    @Test func explicitEndReturnsToVerifiedNormalPresentation() {
        var (configuration, status) = fixture()
        status.systemChargeOverride = .inactive
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .protectionActive)
        status.holding = true
        #expect(shouldPresentChargeLimitStatusItem(configuration: configuration, status: status))
    }

    @Test func systemOverrideDoesNotHideIndependentFailure() {
        var (configuration, status) = fixture()
        status.lastError = "Unrelated verification failure"
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .attentionRequired)
        status.systemChargeOverride = nil
        status.lastError = "Native PowerUI 80% engagement failed"
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .attentionRequired)
    }

    @Test func staleFutureAndMismatchedReportsCannotClaimSystemOverride() {
        let now = Date()
        let (configuration, fresh) = fixture(now: now)
        for timestamp in [now.addingTimeInterval(-20), now.addingTimeInterval(2)] {
            var status = fresh
            status.timestamp = timestamp
            #expect(resolvedSystemChargeOverride(configuration: configuration, status: status, now: now) == nil)
        }
        var status = fresh
        status.configurationUpdatedAt = configuration.updatedAt.addingTimeInterval(-10)
        #expect(resolvedSystemChargeOverride(configuration: configuration, status: status, now: now) == nil)
        status = fresh
        status.controlMethod = .chte
        #expect(resolvedSystemChargeOverride(configuration: configuration, status: status, now: now) == nil)
        status = fresh
        status.configurationUpdatedAt = nil
        #expect(resolvedSystemChargeOverride(configuration: configuration, status: status, now: now) == nil)
    }

    @Test func disabledProtectionDoesNotPresentAnOverride() {
        var (configuration, status) = fixture()
        configuration.enabled = false
        #expect(resolvedSystemChargeOverride(configuration: configuration, status: status) == nil)
    }

    @Test func oldHelperStatusDecodesAndNewStatusRoundTrips() throws {
        let (_, status) = fixture()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoded = try encoder.encode(status)
        #expect(try decoder.decode(ChargeProtectionStatus.self, from: encoded).systemChargeOverride == .chargingToFull)
        var old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "systemChargeOverride")
        #expect(try decoder.decode(ChargeProtectionStatus.self, from: JSONSerialization.data(withJSONObject: old)).systemChargeOverride == nil)
    }

    @Test(arguments: [AppLanguage.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese])
    func mainAppMessagesAreLocalized(_ language: AppLanguage) {
        let full = L10n.format("systemFullChargeInProgress", language, 80)
        #expect(full.contains("80%"))
        #expect(!full.contains("%d"))
        #expect(full != "systemFullChargeInProgress")
        #expect(L10n.text("systemFullChargeAwaitingConfirmation", language) != "systemFullChargeAwaitingConfirmation")
    }

    @Test(arguments: [AgentLanguage.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese])
    func agentMessagesAreLocalized(_ language: AgentLanguage) {
        for key in ["systemFullActive", "systemFullPending", "systemFullDetail", "systemFullPendingDetail"] {
            #expect(AgentL10n.text(key, language: language) != key)
        }
    }

    @Test func awaitingConfirmationDoesNotClearOnConsecutiveNilReadingsWithoutReliableEvidence() {
        var tracker = SystemChargeOverrideTracker()
        #expect(tracker.observe(temporarilyDisabled: true) == .chargingToFull)
        #expect(tracker.observe(temporarilyDisabled: nil) == .awaitingConfirmation)
        #expect(tracker.observe(temporarilyDisabled: nil) == .awaitingConfirmation)
        #expect(tracker.observe(temporarilyDisabled: nil) == .awaitingConfirmation)
        #expect(tracker.observe(temporarilyDisabled: nil) == .awaitingConfirmation)
        #expect(tracker.state == .awaitingConfirmation)
        #expect(tracker.state?.defersChargeControl == true)
        // Only an explicit false read can reliably end the system override:
        #expect(tracker.observe(temporarilyDisabled: false) == .inactive)
        #expect(tracker.state == .inactive)
        #expect(tracker.state?.defersChargeControl == false)

        var calibrationTracker = SystemCalibrationTracker()
        #expect(calibrationTracker.observe(limitSuspended: true) == .calibrating)
        #expect(calibrationTracker.observe(limitSuspended: nil) == .awaitingConfirmation)
        #expect(calibrationTracker.observe(limitSuspended: nil) == .awaitingConfirmation)
        #expect(calibrationTracker.observe(limitSuspended: nil) == .awaitingConfirmation)
        #expect(calibrationTracker.observe(limitSuspended: nil) == .awaitingConfirmation)
        #expect(calibrationTracker.state == .awaitingConfirmation)
        #expect(calibrationTracker.state?.defersChargeControl == true)
        // Only an explicit false read can reliably end the limit suspension:
        #expect(calibrationTracker.observe(limitSuspended: false) == .inactive)
        #expect(calibrationTracker.state == .inactive)
        #expect(calibrationTracker.state?.defersChargeControl == false)
    }

    @MainActor
    @Test func menuBarStatusItemRemainsVisibleDuringSystemOverrideTemporaryFullAndAttentionRequired() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dbhv-test-agent-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let now = Date()
        let configDate = now.addingTimeInterval(-10)
        let config = ChargeProtectionConfiguration(
            enabled: true,
            fixedLimit: .eighty,
            managementMode: .softwareManaged,
            showMenuBarStatus: true,
            updatedAt: configDate
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(config).write(to: tempDir.appendingPathComponent("configuration.json"))

        let model = ChargeLimitAgentModel(
            configurationDirectory: tempDir,
            statusURL: tempDir.appendingPathComponent("status.json"),
            operatingSystemVersion: .init(majorVersion: 15, minorVersion: 8, patchVersion: 0)
        )

        var status = ChargeProtectionStatus(
            helperVersion: "test", timestamp: now, installed: true, enabled: true,
            fixedLimit: .eighty, temporaryFullCharge: false,
            configurationUpdatedAt: configDate,
            holding: false, adapterConnected: true, batteryPercentage: 80,
            controlMethod: .powerUIOptimized80, systemChargeOverride: .chargingToFull, systemCalibration: .inactive
        )

        // System Temporary Full Charge (visible)
        try? encoder.encode(status).write(to: tempDir.appendingPathComponent("status.json"))
        model.reload(now: now)
        #expect(model.shouldShowStatusItem)

        // System Calibration (visible)
        status.systemChargeOverride = .inactive
        status.systemCalibration = .calibrating
        try? encoder.encode(status).write(to: tempDir.appendingPathComponent("status.json"))
        model.reload(now: now)
        #expect(model.shouldShowStatusItem)

        // DBHV Temporary Full Charge (faded out / hidden per Codex build 48 design)
        status.systemCalibration = .inactive
        status.temporaryFullCharge = true
        model.toggleTemporaryFullCharge()
        status.configurationUpdatedAt = model.configuration.updatedAt
        status.configurationRevision = model.configuration.revision
        try? encoder.encode(status).write(to: tempDir.appendingPathComponent("status.json"))
        model.reload(now: now)
        #expect(!model.shouldShowStatusItem)

        // Attention Required (visible)
        model.toggleTemporaryFullCharge()
        status.temporaryFullCharge = false
        status.configurationUpdatedAt = model.configuration.updatedAt
        status.configurationRevision = model.configuration.revision
        status.lastError = "Native PowerUI 80% engagement failed"
        try? encoder.encode(status).write(to: tempDir.appendingPathComponent("status.json"))
        model.reload(now: now)
        #expect(model.shouldShowStatusItem)
    }

    @Test func unverifiedMacOS15_8BuildFailsClosedWithoutMutatingPowerUI() {
        #expect(isVerifiedPowerUIMacOSBuild("24H212"))
        #expect(!isVerifiedPowerUIMacOSBuild("24H211"))
        #expect(!isVerifiedPowerUIMacOSBuild("24A348"))
        #expect(!isVerifiedPowerUIMacOSBuild("23A344"))
        #expect(!isVerifiedPowerUIMacOSBuild(""))
    }
}
