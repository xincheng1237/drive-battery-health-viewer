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
            controlMethod: .powerUIOptimized80, systemChargeOverride: .chargingToFull
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
}
