import ChargeProtectionCore
import Foundation
import Testing
@testable import DriveBatteryHealthViewer

@Suite("Battery power notice cause")
struct BatteryPowerNoticeTests {
    enum Scenario: CaseIterable {
        case nativeHold, smcHold, iconHidden, roundedConfigurationDate, aboveWithHold, fullWithHold
        case settingOnly, belowLimit, belowHelperLimit, fullWithoutHold, disabledSetting, disabledHelper
        case temporaryFull, oldTemporaryFullStatus, missingStatus, staleStatus, futureStatus
        case oldConfiguration, missingConfigurationDate, changedLimit, holdFailed, missingControl
        case calibration, calibrationAwaitingConfirmation, systemFull, systemFullAwaitingConfirmation
        case unknownCalibration, unknownSystemOverride, nativeWrongLimit
        case charging, unplugged, unknownConnection, unknownCharging
        case missingPercentage, missingHelperPercentage, invalidPercentage, invalidHelperPercentage
        case noProtectionLimit, systemManaged, unsupportedMode
    }

    @Test(arguments: Scenario.allCases)
    func onlyConfirmedCurrentHoldCanExplainTheCause(_ scenario: Scenario) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var configuration = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty,
                                                          updatedAt: now.addingTimeInterval(-10))
        var status: ChargeProtectionStatus? = ChargeProtectionStatus(
            helperVersion: "test", timestamp: now, installed: true, enabled: true,
            fixedLimit: .eighty, temporaryFullCharge: false,
            configurationUpdatedAt: configuration.updatedAt, holding: true,
            adapterConnected: true, batteryPercentage: 80, controlMethod: .powerUIOptimized80,
            systemChargeOverride: .inactive, systemCalibration: .inactive)
        var external: Bool? = true
        var charging: Bool? = false
        var percentage: Int? = 80
        var expected: BatteryPowerNoticeReason? = .ordinary

        switch scenario {
        case .nativeHold: expected = .chargeLimit
        case .smcHold:
            status?.controlMethod = .chte
            status?.systemCalibration = nil
            status?.systemChargeOverride = nil
            expected = .chargeLimit
        case .iconHidden:
            configuration.showMenuBarStatus = false
            expected = .chargeLimit
        case .roundedConfigurationDate:
            configuration.updatedAt = configuration.updatedAt.addingTimeInterval(0.9)
            expected = .chargeLimit
        case .settingOnly: status?.holding = false
        case .belowLimit: percentage = 79
        case .belowHelperLimit: status?.batteryPercentage = 79
        case .aboveWithHold:
            percentage = 81
            status?.batteryPercentage = 81
            expected = .aboveLimit
        case .fullWithHold:
            percentage = 100
            status?.batteryPercentage = 100
            expected = .aboveLimit
        case .fullWithoutHold:
            percentage = 100
            status?.batteryPercentage = 100
            status?.holding = false
        case .disabledSetting: configuration.enabled = false
        case .disabledHelper: status?.enabled = false
        case .temporaryFull: configuration.temporaryFullCharge = true
        case .oldTemporaryFullStatus: status?.temporaryFullCharge = true
        case .missingStatus: status = nil
        case .staleStatus: status?.timestamp = now.addingTimeInterval(-20)
        case .futureStatus: status?.timestamp = now.addingTimeInterval(1)
        case .oldConfiguration: status?.configurationUpdatedAt = now.addingTimeInterval(-30)
        case .missingConfigurationDate: status?.configurationUpdatedAt = nil
        case .changedLimit: status?.fixedLimit = .ninety
        case .holdFailed: status?.lastError = "Native PowerUI 80% engagement failed"
        case .missingControl: status?.controlMethod = .unavailable
        case .calibration: status?.systemCalibration = .calibrating
        case .calibrationAwaitingConfirmation: status?.systemCalibration = .awaitingConfirmation
        case .systemFull: status?.systemChargeOverride = .chargingToFull
        case .systemFullAwaitingConfirmation: status?.systemChargeOverride = .awaitingConfirmation
        case .unknownCalibration: status?.systemCalibration = nil
        case .unknownSystemOverride: status?.systemChargeOverride = nil
        case .nativeWrongLimit:
            configuration.fixedLimit = .eightyFive
            status?.fixedLimit = .eightyFive
            percentage = 85
            status?.batteryPercentage = 85
        case .charging: charging = true; expected = nil
        case .unplugged: external = false; expected = nil
        case .unknownConnection: external = nil; expected = nil
        case .unknownCharging: charging = nil; expected = nil
        case .missingPercentage: percentage = nil
        case .missingHelperPercentage: status?.batteryPercentage = nil
        case .invalidPercentage: percentage = 101
        case .invalidHelperPercentage: status?.batteryPercentage = 101
        case .noProtectionLimit:
            configuration.fixedLimit = .oneHundred
            status?.fixedLimit = .oneHundred
            percentage = 100
            status?.batteryPercentage = 100
        case .systemManaged: configuration.managementMode = .systemPreferred
        case .unsupportedMode: configuration.managementMode = .unsupportedHardware
        }
        #expect(BatteryPowerNoticeReason.resolve(externalConnected: external, isCharging: charging,
            batteryPercentage: percentage, configuration: configuration, status: status, now: now) == expected)
    }

    @Test func ordinaryCopyIsRestoredAndConfirmedProtectionHasItsOwnExplanation() {
        #expect(L10n.text(BatteryPowerNoticeReason.ordinary.localizationKey, .simplifiedChinese) ==
                "已连接电源；当前电池已充满，或 macOS 根据当前状态暂时采用直接供电。")
        #expect(L10n.text(BatteryPowerNoticeReason.chargeLimit.localizationKey, .simplifiedChinese) ==
                "已连接电源，充电上限保护正在生效，当前暂停充电。")
        for language in AppLanguage.allCases {
            for reason in [BatteryPowerNoticeReason.ordinary, .chargeLimit] {
                #expect(L10n.text(reason.localizationKey, language) != reason.localizationKey)
            }
        }
    }
}
