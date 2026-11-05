import ChargeProtectionCore
import SwiftUI

/// Also rendered directly by preview tests; no scanning or Helper installation.
struct SystemChargingPauseNotice: View {
    let calibration: SystemCalibrationState?
    let override: SystemChargeOverrideState?
    let limit: Int
    let language: AppLanguage

    var body: some View {
        if let message {
            Label(message, systemImage: isCalibration ? "arrow.triangle.2.circlepath" : "battery.100percent.bolt")
                .font(.footnote)
                .foregroundStyle(.blue)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isCalibration: Bool { calibration?.defersChargeControl == true }

    var message: String? {
        if isCalibration {
            return calibration == .awaitingConfirmation
                ? L10n.text("systemCalibrationAwaitingConfirmation", language)
                : L10n.format("systemCalibrationInProgress", language, limit)
        }
        if override?.defersChargeControl == true {
            return override == .awaitingConfirmation
                ? L10n.text("systemFullChargeAwaitingConfirmation", language)
                : L10n.format("systemFullChargeInProgress", language, limit)
        }
        return nil
    }
}
