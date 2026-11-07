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
        guard configuration.isValid, configuration.enabled, !configuration.temporaryFullCharge,
              configuration.managementMode == .softwareAvailable || configuration.managementMode == .softwareManaged,
              configuration.fixedLimit != .oneHundred,
              let batteryPercentage, (configuration.fixedLimit.rawValue...100).contains(batteryPercentage),
              let status, status.installed, status.enabled, !status.temporaryFullCharge,
              status.fixedLimit == configuration.fixedLimit,
              let appliedAt = status.configurationUpdatedAt,
              abs(appliedAt.timeIntervalSince(configuration.updatedAt)) < 1,
              status.isFresh(at: now),
              status.lastError == nil, status.controlMethod != .unavailable,
              status.holding, status.adapterConnected == true,
              let helperPercentage = status.batteryPercentage,
              (configuration.fixedLimit.rawValue...100).contains(helperPercentage),
              status.systemCalibration?.defersChargeControl != true,
              status.systemChargeOverride?.defersChargeControl != true else { return .ordinary }

        // Native PowerUI can suspend the limit independently of the app.
        // Missing/unknown system observations cannot establish this cause.
        if status.controlMethod == .powerUIOptimized80,
           (configuration.fixedLimit != .eighty || status.systemCalibration != .inactive || status.systemChargeOverride != .inactive) {
            return .ordinary
        }
        return .chargeLimit
    }
}
