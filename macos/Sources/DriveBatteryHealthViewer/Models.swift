import Foundation

let applicationVersion = "1.0.5"

enum HealthState: String, Codable, Sendable {
    case good
    case warning
    case critical
    case unknown
}

struct DriveInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String { deviceIdentifier }
    let deviceIdentifier: String
    var model: String
    var serialNumber: String?
    var firmware: String?
    var protocolName: String?
    var capacityBytes: UInt64
    var smartStatus: String?
    var healthState: HealthState
    var lifeRemainingPercent: Double?
    var temperatureCelsius: Double?
    var powerOnHours: UInt64?
    var powerCycles: UInt64?
    var bytesRead: UInt64?
    var bytesWritten: UInt64?
    var unsafeShutdowns: UInt64?
    var mediaErrors: UInt64?
    var isSolidState: Bool?
    var isInternal: Bool?
    var notes: [String]
}

struct BatteryInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String { serialNumber ?? name }
    var name: String
    var manufacturer: String?
    var serialNumber: String?
    var chemistry: String?
    var designCapacityMAh: Int?
    var fullChargeCapacityMAh: Int?
    var currentCapacityPercent: Int?
    var cycleCount: Int?
    var healthPercent: Double?
    var capacityRatioPercent: Double?
    var voltageMillivolts: Int?
    var designVoltageMillivolts: Int?
    var temperatureCelsius: Double?
    var isCharging: Bool?
    var externalConnected: Bool?
    var healthState: HealthState
    var notes: [String]
}

func formattedBatteryCapacity(_ milliampHours: Int, voltageMillivolts: Int?, language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: L10n.effective(language).rawValue)
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    let capacity = formatter.string(from: NSNumber(value: milliampHours)) ?? String(milliampHours)
    guard let voltageMillivolts, voltageMillivolts > 0 else { return "\(capacity) mAh" }
    let wattHours = Double(milliampHours) * Double(voltageMillivolts) / 1_000_000
    let wattFormatter = NumberFormatter()
    wattFormatter.locale = formatter.locale
    wattFormatter.numberStyle = .decimal
    wattFormatter.minimumFractionDigits = 2
    wattFormatter.maximumFractionDigits = 2
    let watts = wattFormatter.string(from: NSNumber(value: wattHours)) ?? String(format: "%.2f", wattHours)
    return "\(capacity) mAh / \(watts) Wh"
}

func formattedBatteryVoltage(_ millivolts: Int, language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: L10n.effective(language).rawValue)
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let volts = Double(millivolts) / 1_000
    return "\(formatter.string(from: NSNumber(value: volts)) ?? String(format: "%.2f", volts)) V"
}

struct HealthSnapshot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var generatedAt: Date
    var computerName: String
    var drives: [DriveInfo]
    var batteries: [BatteryInfo]
    var warnings: [String]

    init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        computerName: String,
        drives: [DriveInfo],
        batteries: [BatteryInfo],
        warnings: [String] = []
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.computerName = computerName
        self.drives = drives
        self.batteries = batteries
        self.warnings = warnings
    }
}

extension HealthSnapshot {
    /// A transient system/driver read failure must not erase values that were
    /// successfully read earlier for the same connected device.
    func preservingUnavailableValues(from previous: HealthSnapshot?) -> HealthSnapshot {
        guard let previous else { return self }
        var merged = self
        merged.drives = drives.map { fresh in
            guard let old = previous.drives.first(where: { $0.deviceIdentifier == fresh.deviceIdentifier }) else {
                return fresh
            }
            var value = fresh
            if value.model.isEmpty || value.model == value.deviceIdentifier { value.model = old.model }
            value.serialNumber = value.serialNumber ?? old.serialNumber
            value.firmware = value.firmware ?? old.firmware
            value.protocolName = value.protocolName ?? old.protocolName
            if value.capacityBytes == 0 { value.capacityBytes = old.capacityBytes }
            value.smartStatus = value.smartStatus ?? old.smartStatus
            if value.healthState == .unknown { value.healthState = old.healthState }
            value.lifeRemainingPercent = value.lifeRemainingPercent ?? old.lifeRemainingPercent
            value.temperatureCelsius = value.temperatureCelsius ?? old.temperatureCelsius
            value.powerOnHours = value.powerOnHours ?? old.powerOnHours
            value.powerCycles = value.powerCycles ?? old.powerCycles
            value.bytesRead = value.bytesRead ?? old.bytesRead
            value.bytesWritten = value.bytesWritten ?? old.bytesWritten
            value.unsafeShutdowns = value.unsafeShutdowns ?? old.unsafeShutdowns
            value.mediaErrors = value.mediaErrors ?? old.mediaErrors
            value.isSolidState = value.isSolidState ?? old.isSolidState
            value.isInternal = value.isInternal ?? old.isInternal
            return value
        }
        merged.batteries = batteries.map { fresh in
            guard let old = previous.batteries.first(where: {
                if let serial = fresh.serialNumber, let oldSerial = $0.serialNumber { return serial == oldSerial }
                return fresh.name == $0.name
            }) else { return fresh }
            var value = fresh
            value.manufacturer = value.manufacturer ?? old.manufacturer
            value.serialNumber = value.serialNumber ?? old.serialNumber
            value.chemistry = value.chemistry ?? old.chemistry
            value.designCapacityMAh = value.designCapacityMAh ?? old.designCapacityMAh
            value.fullChargeCapacityMAh = value.fullChargeCapacityMAh ?? old.fullChargeCapacityMAh
            value.currentCapacityPercent = value.currentCapacityPercent ?? old.currentCapacityPercent
            value.cycleCount = value.cycleCount ?? old.cycleCount
            value.healthPercent = value.healthPercent ?? old.healthPercent
            value.capacityRatioPercent = value.capacityRatioPercent ?? old.capacityRatioPercent
            value.voltageMillivolts = value.voltageMillivolts ?? old.voltageMillivolts
            value.designVoltageMillivolts = value.designVoltageMillivolts ?? old.designVoltageMillivolts
            value.temperatureCelsius = value.temperatureCelsius ?? old.temperatureCelsius
            value.isCharging = value.isCharging ?? old.isCharging
            value.externalConnected = value.externalConnected ?? old.externalConnected
            if value.healthState == .unknown { value.healthState = old.healthState }
            return value
        }
        return merged
    }

    func updatingLiveHardwareState(_ state: LiveHardwareState) -> HealthSnapshot {
        var updated = self
        for index in updated.drives.indices {
            if let temperature = state.driveTemperatures[updated.drives[index].deviceIdentifier] {
                updated.drives[index].temperatureCelsius = temperature
            }
        }
        if let battery = state.battery {
            for index in updated.batteries.indices {
                updated.batteries[index].currentCapacityPercent = battery.chargePercent
                updated.batteries[index].isCharging = battery.isCharging
                updated.batteries[index].externalConnected = battery.externalConnected
                if let temperature = battery.temperatureCelsius {
                    updated.batteries[index].temperatureCelsius = temperature
                }
            }
        }
        return updated
    }
}

enum HistorySource: String, Codable, Sendable {
    case refresh
    case export
}

struct HistoryRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var version: String
    var source: HistorySource
    var snapshot: HealthSnapshot
    var exportPath: String?

    init(
        id: UUID = UUID(),
        version: String = applicationVersion,
        source: HistorySource,
        snapshot: HealthSnapshot,
        exportPath: String? = nil
    ) {
        self.id = id
        self.version = version
        self.source = source
        self.snapshot = snapshot
        self.exportPath = exportPath
    }
}

enum HistorySaveMode: String, CaseIterable, Codable, Sendable {
    case refresh
    case export
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case russian = "ru"
    case french = "fr"
    case german = "de"
    case korean = "ko"
    case japanese = "ja"

    var id: String { rawValue }

    static func detected() -> AppLanguage {
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if identifier.hasPrefix("zh") { return .simplifiedChinese }
        if identifier.hasPrefix("ru") { return .russian }
        if identifier.hasPrefix("fr") { return .french }
        if identifier.hasPrefix("de") { return .german }
        if identifier.hasPrefix("ko") { return .korean }
        if identifier.hasPrefix("ja") { return .japanese }
        return .english
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case overview
    case history
    case settings
    case about

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

extension UInt64 {
    var formattedStorage: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(clamping: self))
    }
}

extension Date {
    func formattedReportDate(locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: self)
    }
}
