import Foundation

enum ReportRenderer {
    static func render(snapshot: HealthSnapshot, language: AppLanguage, hideSerials: Bool) -> String {
        var lines: [String] = []
        lines.append("\(L10n.text("appName", language)) v\(applicationVersion)")
        lines.append("\(L10n.text("generated", language)): \(snapshot.generatedAt.formattedReportDate(locale: Locale(identifier: L10n.effective(language).rawValue)))")
        lines.append("\(L10n.text("computer", language)): \(snapshot.computerName)")
        lines.append("")
        lines.append("==================== \(L10n.text("drives", language)) ====================")

        if snapshot.drives.isEmpty { lines.append(L10n.text("noDrives", language)) }
        for (index, drive) in snapshot.drives.enumerated() {
            lines.append("")
            lines.append("[\(L10n.text("drives", language)) \(index + 1) · \(drive.deviceIdentifier)]")
            append(&lines, L10n.text("model", language), drive.model, language)
            append(&lines, L10n.text("capacity", language), drive.capacityBytes > 0 ? drive.capacityBytes.formattedStorage : nil, language)
            append(&lines, L10n.text("protocol", language), drive.protocolName, language)
            append(&lines, L10n.text("firmware", language), drive.firmware, language)
            append(&lines, L10n.text("serialNumber", language), serial(drive.serialNumber, hidden: hideSerials), language)
            append(&lines, L10n.text("smartStatus", language), drive.smartStatus, language)
            append(&lines, L10n.text("lifeRemaining", language), drive.lifeRemainingPercent.map { L10n.format("percent", language, $0) }, language)
            append(&lines, L10n.text("temperature", language), drive.temperatureCelsius.map { String(format: "%.1f °C", $0) }, language)
            append(&lines, L10n.text("powerOnHours", language), drive.powerOnHours.map { L10n.format("hours", language, $0) }, language)
            append(&lines, L10n.text("powerCycles", language), drive.powerCycles.map(String.init), language)
            append(&lines, L10n.text("totalRead", language), drive.bytesRead.map { $0.formattedStorage }, language)
            append(&lines, L10n.text("totalWritten", language), drive.bytesWritten.map { $0.formattedStorage }, language)
            append(&lines, L10n.text("unsafeShutdowns", language), drive.unsafeShutdowns.map(String.init), language)
            append(&lines, L10n.text("mediaErrors", language), drive.mediaErrors.map(String.init), language)
        }

        lines.append("")
        lines.append("==================== \(L10n.text("batteries", language)) ====================")
        if snapshot.batteries.isEmpty { lines.append(L10n.text("noBattery", language)) }
        for (index, battery) in snapshot.batteries.enumerated() {
            lines.append("")
            lines.append("[\(L10n.text("batteries", language)) \(index + 1)]")
            append(&lines, L10n.text("model", language), battery.name, language)
            append(&lines, L10n.text("manufacturer", language), battery.manufacturer, language)
            append(&lines, L10n.text("serialNumber", language), serial(battery.serialNumber, hidden: hideSerials), language)
            let type = battery.chemistry == "InternalBattery" ? L10n.text("internalBattery", language) : battery.chemistry
            append(&lines, L10n.text("chemistry", language), type, language)
            append(&lines, L10n.text("designCapacity", language), battery.designCapacityMAh.map { formattedBatteryCapacity($0, voltageMillivolts: battery.designVoltageMillivolts ?? battery.voltageMillivolts, language: language) }, language)
            append(&lines, L10n.text("fullChargeCapacity", language), battery.fullChargeCapacityMAh.map { formattedBatteryCapacity($0, voltageMillivolts: battery.designVoltageMillivolts ?? battery.voltageMillivolts, language: language) }, language)
            append(&lines, L10n.text("health", language), battery.healthPercent.map { L10n.format("percent", language, $0) }, language)
            append(&lines, L10n.text("currentCharge", language), battery.currentCapacityPercent.map { L10n.format("percent", language, Double($0)) }, language)
            append(&lines, L10n.text("cycleCount", language), battery.cycleCount.map(String.init), language)
            append(&lines, L10n.text("temperature", language), battery.temperatureCelsius.map { String(format: "%.1f °C", $0) }, language)
            append(&lines, L10n.text("batteryVoltage", language), battery.voltageMillivolts.map { formattedBatteryVoltage($0, language: language) }, language)
            append(&lines, L10n.text("charging", language), battery.isCharging.map { L10n.text($0 ? "yes" : "no", language) }, language)
            append(&lines, L10n.text("connected", language), battery.externalConnected.map { L10n.text($0 ? "yes" : "no", language) }, language)
        }

        lines.append("")
        lines.append("==================== \(L10n.text("systemNotes", language)) ====================")
        lines.append(L10n.text("readOnlyNote", language))
        lines.append(L10n.text("systemLimitations", language))
        if !snapshot.batteries.isEmpty { lines.append(L10n.text("batteryHealthExplanation", language)) }
        if hideSerials { lines.append(L10n.text("privacyNotice", language)) }
        lines.append(contentsOf: snapshot.warnings)
        return lines.joined(separator: "\n")
    }

    private static func append(_ lines: inout [String], _ label: String, _ value: String?, _ language: AppLanguage) {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("\(label): \((normalized?.isEmpty == false ? normalized : nil) ?? L10n.text("unavailable", language))")
    }

    private static func serial(_ value: String?, hidden: Bool) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return hidden ? "••••••••" : value
    }
}
