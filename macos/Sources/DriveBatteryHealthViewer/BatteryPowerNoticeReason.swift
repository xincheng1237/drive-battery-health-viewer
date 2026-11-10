import ChargeProtectionCore
import Foundation

/// Presentation only. Being plugged in with the setting enabled does not
/// establish why charging stopped; require a current, successful hold report.
enum BatteryPowerNoticeReason: Equatable {
    case ordinary
    case chargeLimit
    case aboveLimit

    var localizationKey: String {
        switch self {
        case .ordinary: return "powerConnectedNotCharging"
        case .chargeLimit: return "chargeProtectionHoldingNotice"
        case .aboveLimit: return "chargeAboveLimit"
        }
    }

    static func resolve(
        externalConnected: Bool?, isCharging: Bool?, batteryPercentage: Int?,
        configuration: ChargeProtectionConfiguration, status: ChargeProtectionStatus?,
        now: Date = Date()
    ) -> Self? {
        guard externalConnected == true, isCharging == false else { return nil }
        guard let batteryPercentage, (configuration.fixedLimit.rawValue...100).contains(batteryPercentage),
              let position = resolvedChargeLimitHoldPosition(configuration: configuration, status: status, now: now)
        else { return .ordinary }
        if batteryPercentage > configuration.fixedLimit.rawValue { return .aboveLimit }
        return position == .atLimit ? .chargeLimit : .ordinary
    }
}
