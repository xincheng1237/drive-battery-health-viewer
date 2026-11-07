import ChargeProtectionCore
import Foundation

/// Presentation only. Being plugged in with the setting enabled does not
/// establish why charging stopped; require a current, successful hold report.
enum BatteryPowerNoticeReason: Equatable {
    case ordinary
    case chargeLimit

    var localizationKey: String {
        self == .chargeLimit ? "chargeProtectionHoldingNotice" : "powerConnectedNotCharging"
    }

    static func resolve(
        externalConnected: Bool?, isCharging: Bool?, batteryPercentage: Int?,
        configuration: ChargeProtectionConfiguration, status: ChargeProtectionStatus?,
        now: Date = Date()
    ) -> Self? {
        guard externalConnected == true, isCharging == false else { return nil }
        guard let batteryPercentage, (configuration.fixedLimit.rawValue...100).contains(batteryPercentage),
              shouldPresentChargeLimitStatusItem(configuration: configuration, status: status, now: now)
        else { return .ordinary }
        return .chargeLimit
    }
}
