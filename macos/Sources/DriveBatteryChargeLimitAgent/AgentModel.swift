import ChargeProtectionCore
import Foundation

enum AgentLanguage: String, CaseIterable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case russian = "ru"
    case french = "fr"
    case german = "de"
    case korean = "ko"
    case japanese = "ja"

    static func current() -> Self {
        let stored = UserDefaults(suiteName: "com.chengxin.drive-battery-health-viewer")?
            .string(forKey: "language")
        let selected = stored.flatMap(Self.init(rawValue:)) ?? .system
        guard selected == .system else { return selected }
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

enum AgentL10n {
    private static let values: [AgentLanguage: [String: String]] = [
        .english: [
            "reached": "Charge limit reached (%d%%)",
            "active": "Charge protection enabled (%d%% limit)",
            "temporaryFullActive": "Charging to full this time",
            "attention": "Charge protection needs attention",
            "adjust": "Adjust fixed charge limit",
            "full": "Charge to Full This Time",
            "cancelFull": "Cancel Full Charge",
            "fixed": "Fixed charge limit",
            "menuBar": "Show in Menu Bar",
            "only80": "macOS 15.8: Native 80% limit only",
            "only80Disabled": "Choose 80%, or 100% to turn protection off."
        ],
        .simplifiedChinese: [
            "reached": "已到达设定电量（%d%%）",
            "active": "充电保护已启用（上限 %d%%）",
            "temporaryFullActive": "本次正在充满",
            "attention": "充电保护需要处理",
            "adjust": "调整固定充电上限",
            "full": "本次充满",
            "cancelFull": "取消本次充满",
            "fixed": "固定充电上限",
            "menuBar": "菜单栏显示",
            "only80": "macOS 15.8：仅支持 Apple 原生 80% 上限",
            "only80Disabled": "请选择 80%，或选择 100% 关闭充电保护。"
        ],
        .russian: [
            "reached": "Достигнут предел заряда (%d%%)",
            "active": "Защита зарядки включена (предел %d%%)",
            "temporaryFullActive": "Выполняется разовая полная зарядка",
            "attention": "Требуется проверить защиту зарядки",
            "adjust": "Изменить постоянный предел",
            "full": "Зарядить полностью один раз",
            "cancelFull": "Отменить полный заряд",
            "fixed": "Постоянный предел заряда",
            "menuBar": "Показывать в меню", "only80": "macOS 15.8: только нативный предел 80%", "only80Disabled": "Выберите 80% или 100%, чтобы отключить защиту."
        ],
        .french: [
            "reached": "Limite de charge atteinte (%d%%)",
            "active": "Protection de charge activée (limite de %d %%)",
            "temporaryFullActive": "Charge complète en cours pour cette fois",
            "attention": "La protection de charge nécessite votre attention",
            "adjust": "Modifier la limite fixe",
            "full": "Charger complètement cette fois",
            "cancelFull": "Annuler la charge complète",
            "fixed": "Limite de charge fixe",
            "menuBar": "Afficher dans la barre", "only80": "macOS 15.8 : limite native de 80 % uniquement", "only80Disabled": "Choisissez 80 %, ou 100 % pour désactiver la protection."
        ],
        .german: [
            "reached": "Ladegrenze erreicht (%d%%)",
            "active": "Ladeschutz aktiviert (Grenze: %d %%)",
            "temporaryFullActive": "Dieses Mal wird vollständig geladen",
            "attention": "Ladeschutz erfordert Aufmerksamkeit",
            "adjust": "Feste Ladegrenze anpassen",
            "full": "Diesmal vollständig laden",
            "cancelFull": "Vollständiges Laden abbrechen",
            "fixed": "Feste Ladegrenze",
            "menuBar": "In Menüleiste zeigen", "only80": "macOS 15.8: nur native 80-%-Grenze", "only80Disabled": "80 % wählen oder mit 100 % den Ladeschutz ausschalten."
        ],
        .korean: [
            "reached": "설정한 충전량에 도달함(%d%%)",
            "active": "충전 보호가 켜짐(한도 %d%%)",
            "temporaryFullActive": "이번에는 완전 충전 중",
            "attention": "충전 보호를 확인해야 함",
            "adjust": "고정 충전 한도 조절",
            "full": "이번에 완전히 충전",
            "cancelFull": "완전 충전 취소",
            "fixed": "고정 충전 한도",
            "menuBar": "메뉴 막대에 표시", "only80": "macOS 15.8: 기본 80% 한도만 지원", "only80Disabled": "80%를 선택하거나 100%로 보호를 끄십시오."
        ],
        .japanese: [
            "reached": "設定した充電量に到達（%d%%）",
            "active": "充電保護が有効（上限 %d%%）",
            "temporaryFullActive": "今回だけ満充電中",
            "attention": "充電保護の確認が必要です",
            "adjust": "固定充電上限を調整",
            "full": "今回だけ満充電",
            "cancelFull": "満充電をキャンセル",
            "fixed": "固定充電上限",
            "menuBar": "メニューバーに表示", "only80": "macOS 15.8：ネイティブ 80% 上限のみ対応", "only80Disabled": "80% を選ぶか、100% で充電保護をオフにします。"
        ]
    ]

    static func text(_ key: String, language: AgentLanguage) -> String {
        values[language]?[key] ?? values[.english]?[key] ?? key
    }

    static func reached(_ limit: Int, language: AgentLanguage) -> String {
        String(format: text("reached", language: language), limit)
    }

    static func active(_ limit: Int, language: AgentLanguage) -> String {
        String(format: text("active", language: language), limit)
    }
}

enum ChargeLimitAgentPresentationState: Equatable {
    case protectionActive
    case limitReached
    case temporaryFullCharge
    case attentionRequired

    static func resolve(
        configuration: ChargeProtectionConfiguration,
        status: ChargeProtectionStatus?
    ) -> Self {
        if let error = status?.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return .attentionRequired
        }
        if configuration.temporaryFullCharge { return .temporaryFullCharge }
        if shouldPresentChargeLimitStatusItem(configuration: configuration, status: status) {
            return .limitReached
        }
        return .protectionActive
    }
}

@MainActor
final class ChargeLimitAgentModel: ObservableObject {
    static let statusURL = URL(
        fileURLWithPath: "/Library/Application Support/DriveBatteryHealthViewer/ChargeProtection/status.json"
    )

    @Published private(set) var configuration = ChargeProtectionConfiguration()
    @Published private(set) var status: ChargeProtectionStatus?
    @Published private(set) var language = AgentLanguage.current()

    private let fileManager: FileManager
    private let configurationURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let isAppleSilicon: Bool
    private let operatingSystemVersion: OperatingSystemVersion
    private var pollingTask: Task<Void, Never>?
    private var lastObservedConfigurationDate: Date?
    private var lastLanguagePreference: AgentLanguage?

    init(
        fileManager: FileManager = .default,
        configurationDirectory: URL? = nil,
        isAppleSilicon: Bool = true,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) {
        self.fileManager = fileManager
        self.isAppleSilicon = isAppleSilicon
        self.operatingSystemVersion = operatingSystemVersion
        let directory = configurationDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/DriveBatteryHealthViewer/ChargeProtection",
                isDirectory: true
            )
        configurationURL = directory.appendingPathComponent("configuration.json")
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        reload()
    }

    deinit { pollingTask?.cancel() }

    var displayedLimitPercentage: Int {
        if isPowerUIEightyOnly {
            return configuration.enabled
                ? FixedChargeLimit.eighty.rawValue
                : FixedChargeLimit.oneHundred.rawValue
        }
        return configuration.enabled ? configuration.fixedLimit.rawValue : 100
    }

    var isPowerUIEightyOnly: Bool {
        ChargeLimitCapabilityPolicy.isPowerUIEightyOnly(
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion
        )
    }

    var availability: ChargeProtectionAvailability {
        ChargeProtectionAvailability.evaluate(
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion,
            userSelectedSoftwareManagement: configuration.managementMode == .softwareManaged
        )
    }

    func isLimitSelectable(_ percentage: Int) -> Bool {
        guard availability.permitsSoftwareControls else { return false }
        guard let limit = FixedChargeLimit(validated: percentage) else { return false }
        return ChargeLimitCapabilityPolicy.permits(
            limit,
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion
        )
    }

    var shouldShowStatusItem: Bool {
        // The icon represents the enabled protection feature, not a brief
        // threshold event. Keeping one stable NSStatusItem also avoids losing
        // its menu-bar position while power and battery state fluctuate.
        availability.permitsSoftwareControls &&
            configuration.showMenuBarStatus && configuration.enabled
    }

    var presentationState: ChargeLimitAgentPresentationState {
        .resolve(configuration: configuration, status: status)
    }

    var statusItemLabel: String {
        switch presentationState {
        case .protectionActive:
            return AgentL10n.active(configuration.fixedLimit.rawValue, language: language)
        case .limitReached:
            return AgentL10n.reached(configuration.fixedLimit.rawValue, language: language)
        case .temporaryFullCharge:
            return AgentL10n.text("temporaryFullActive", language: language)
        case .attentionRequired:
            return AgentL10n.text("attention", language: language)
        }
    }

    func startMonitoring() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.reload()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
    }

    func selectDisplayedLimit(_ percentage: Int) {
        guard availability.permitsSoftwareControls else { return }
        guard let limit = FixedChargeLimit(validated: percentage) else { return }
        guard isLimitSelectable(percentage) else { return }
        updateConfiguration {
            $0.fixedLimit = limit
            $0.temporaryFullCharge = false
            $0.enabled = !(isPowerUIEightyOnly && limit == .oneHundred)
        }
    }

    func toggleTemporaryFullCharge() {
        guard availability.permitsSoftwareControls,
              configuration.enabled, configuration.fixedLimit != .oneHundred else { return }
        updateConfiguration { $0.temporaryFullCharge.toggle() }
    }

    func setMenuBarStatusVisible(_ visible: Bool) {
        guard availability.permitsSoftwareControls else { return }
        updateConfiguration { $0.showMenuBarStatus = visible }
    }

    private func reload() {
        let currentLanguage = AgentLanguage.current()
        if lastLanguagePreference != currentLanguage {
            language = currentLanguage
            lastLanguagePreference = currentLanguage
        }
        if let data = try? Data(contentsOf: configurationURL),
           var decoded = try? decoder.decode(ChargeProtectionConfiguration.self, from: data),
           decoded.isValid {
            decoded.fixedLimit = ChargeLimitCapabilityPolicy.normalized(
                decoded.fixedLimit,
                isAppleSilicon: isAppleSilicon,
                operatingSystemVersion: operatingSystemVersion
            )
            if isPowerUIEightyOnly, decoded.enabled, decoded.fixedLimit == .oneHundred {
                decoded.enabled = false
                decoded.temporaryFullCharge = false
            }
            if lastObservedConfigurationDate != decoded.updatedAt {
                configuration = decoded
                lastObservedConfigurationDate = decoded.updatedAt
            }
        }
        if let data = try? Data(contentsOf: Self.statusURL),
           let decoded = try? decoder.decode(ChargeProtectionStatus.self, from: data) {
            if status != decoded { status = decoded }
        } else {
            if status != nil { status = nil }
        }
    }

    private func updateConfiguration(
        _ mutation: (inout ChargeProtectionConfiguration) -> Void
    ) {
        var updated = configuration
        mutation(&updated)
        updated.fixedLimit = ChargeLimitCapabilityPolicy.normalized(
            updated.fixedLimit,
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion
        )
        updated.updatedAt = Date()
        guard updated.isValid else { return }
        do {
            let directory = configurationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try encoder.encode(updated).write(to: configurationURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
            configuration = updated
            lastObservedConfigurationDate = updated.updatedAt
        } catch {
            // The root helper fails safe and restores normal charging if it can
            // no longer read a valid configuration. This UI never weakens file
            // permissions in order to make a failed write succeed.
        }
    }
}
