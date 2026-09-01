import AppKit
import ChargeProtectionCore
import Darwin
import Foundation

#if arch(arm64)
private let dbhvCurrentArchitectureIsAppleSilicon = true
#else
private let dbhvCurrentArchitectureIsAppleSilicon = false
#endif

@MainActor
final class ChargeProtectionManager: ObservableObject {
    static let sectionExpandedDefaultsKey = "chargeProtectionSectionExpanded"
    static let lastNativeLimitBoundaryDefaultsKey = "chargeProtectionLastNativeLimitBoundary"
    static let helperIdentifier = "com.chengxin.drivebatteryhealthviewer.chargehelper"
    static let helperExecutablePath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
    static let launchDaemonPath = "/Library/LaunchDaemons/\(helperIdentifier).plist"
    static let systemDirectory = URL(
        fileURLWithPath: "/Library/Application Support/DriveBatteryHealthViewer/ChargeProtection",
        isDirectory: true
    )
    static let statusURL = systemDirectory.appendingPathComponent("status.json")
    static let powerUIOwnerURL = systemDirectory.appendingPathComponent("powerui-owner.json")
    static let helperLogURL = URL(
        fileURLWithPath: "/Library/Logs/DriveBatteryHealthViewer/charge-helper.jsonl"
    )
    static let statusAgentIdentifier = "com.chengxin.drivebatteryhealthviewer.chargelimitagent"
    static let statusAgentDirectoryName = "ChargeLimitAgent"

    @Published private(set) var configuration: ChargeProtectionConfiguration
    @Published private(set) var status: ChargeProtectionStatus?
    @Published private(set) var isInstalled = false
    @Published private(set) var hasInstalledComponents = false
    @Published private(set) var isBusy = false
    @Published private(set) var isSectionExpanded: Bool
    @Published private(set) var availability: ChargeProtectionAvailability
    @Published private(set) var isPreparingSoftwareMode = false
    @Published var hasConfirmedSystemPreparation = false
    @Published private(set) var showsUpgradeMigrationPrompt = false
    @Published var showsHelperUpdateAuthorizationPrompt = false
    @Published var errorMessage: String?

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let logger: any DiagnosticLogging
    private let configurationURL: URL
    private var pollingTask: Task<Void, Never>?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let isAppleSilicon: Bool
    private let operatingSystemVersion: OperatingSystemVersion

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        logger: any DiagnosticLogging = DiagnosticLogger.shared,
        isAppleSilicon: Bool = dbhvCurrentArchitectureIsAppleSilicon,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        configurationDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.logger = logger
        self.isAppleSilicon = isAppleSilicon
        self.operatingSystemVersion = operatingSystemVersion
        let directory = configurationDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DriveBatteryHealthViewer/ChargeProtection", isDirectory: true)
        configurationURL = directory.appendingPathComponent("configuration.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded = Self.loadConfiguration(from: configurationURL, decoder: decoder) ?? ChargeProtectionConfiguration()
        loaded.fixedLimit = ChargeLimitCapabilityPolicy.normalized(
            loaded.fixedLimit,
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion
        )
        if ChargeLimitCapabilityPolicy.isPowerUIEightyOnly(
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion
        ), loaded.enabled, loaded.fixedLimit == .oneHundred {
            loaded.enabled = false
            loaded.temporaryFullCharge = false
        }
        let nativeBoundary = Self.isNativeChargeLimitOS(operatingSystemVersion)
        let previousBoundary = defaults.object(forKey: Self.lastNativeLimitBoundaryDefaultsKey) as? Bool
        let crossedIntoNativeLimit = isAppleSilicon && nativeBoundary && previousBoundary == false && loaded.enabled
        let resolvedAvailability: ChargeProtectionAvailability

        if !isAppleSilicon {
            resolvedAvailability = .unsupportedHardware
            loaded.managementMode = .unsupportedHardware
            loaded.enabled = false
            loaded.temporaryFullCharge = false
        } else if !nativeBoundary {
            resolvedAvailability = .softwareAvailable
            loaded.managementMode = .softwareAvailable
        } else if loaded.managementMode == .softwareManaged && !crossedIntoNativeLimit {
            resolvedAvailability = .softwareManaged
        } else {
            resolvedAvailability = .systemPreferred
            loaded.managementMode = .systemPreferred
            loaded.enabled = false
            loaded.temporaryFullCharge = false
        }
        if crossedIntoNativeLimit {
            showsUpgradeMigrationPrompt = true
            loaded.managementMode = .systemPreferred
            loaded.enabled = false
            loaded.temporaryFullCharge = false
        }
        availability = resolvedAvailability
        loaded.updatedAt = Date()
        configuration = loaded

        if let stored = defaults.object(forKey: Self.sectionExpandedDefaultsKey) as? Bool {
            isSectionExpanded = stored
        } else {
            let initialExpansion = resolvedAvailability == .softwareAvailable
            isSectionExpanded = initialExpansion
            defaults.set(initialExpansion, forKey: Self.sectionExpandedDefaultsKey)
        }
        try? Self.writeSecureConfiguration(loaded, to: configurationURL, encoder: encoder, fileManager: fileManager)
        defaults.set(nativeBoundary, forKey: Self.lastNativeLimitBoundaryDefaultsKey)
        reloadStatus()
    }

    deinit { pollingTask?.cancel() }

    var selectedLimit: FixedChargeLimit {
        get { configuration.fixedLimit }
        set { setLimit(newValue) }
    }

    /// Under the macOS 15.8 PowerUI policy, 80% is the only enforceable cap and
    /// 100% is the explicit no-protection/normal-charging choice.
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

    func isLimitSelectable(_ percentage: Int) -> Bool {
        guard availability.permitsSoftwareControls else { return false }
        guard let limit = FixedChargeLimit(validated: percentage) else { return false }
        return ChargeLimitCapabilityPolicy.permits(
            limit,
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion
        )
    }

    var shouldShowLimitReachedStatusItem: Bool {
        availability.permitsSoftwareControls && configuration.showMenuBarStatus && shouldPresentChargeLimitStatusItem(
            configuration: configuration,
            status: status
        )
    }

    /// macOS must authenticate only when enabling would install or replace the
    /// root-owned helper. Ordinary enable/disable operations with the current
    /// helper remain immediate and do not show an explanatory prompt.
    var requiresAdministratorAuthorizationToEnable: Bool {
        guard availability.permitsSoftwareControls else { return false }
        return Self.requiresAdministratorAuthorizationForEnable(
            isInstalled: isInstalled,
            installedHelperMatchesBundledHelper: installedHelperMatchesBundledHelper
        )
    }

    nonisolated static func requiresAdministratorAuthorizationForEnable(
        isInstalled: Bool,
        installedHelperMatchesBundledHelper: Bool
    ) -> Bool {
        !isInstalled || !installedHelperMatchesBundledHelper
    }

    func requiresAdministratorAuthorizationToSelectLimit(_ percentage: Int) -> Bool {
        guard !configuration.enabled,
              isLimitSelectable(percentage) else { return false }
        if isPowerUIEightyOnly, percentage == FixedChargeLimit.oneHundred.rawValue {
            return false
        }
        return requiresAdministratorAuthorizationToEnable
    }

    /// The helper reads the adapter through its SMC path even when CHIE/CHTE
    /// intentionally makes AppleSmartBattery publish ExternalConnected=false.
    /// Accept only a fresh positive observation; a stale helper status must
    /// never make an unplugged adapter appear connected.
    var confirmsExternalPowerConnection: Bool {
        resolvedExternalPowerConnection(
            systemReportedConnection: false,
            configuration: configuration,
            status: status
        )
    }

    func startMonitoring() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.reloadStatus()
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }

    func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func enable() {
        guard availability.permitsSoftwareControls, !isBusy else { return }
        errorMessage = nil
        if isPowerUIEightyOnly, configuration.fixedLimit == .oneHundred {
            configuration.fixedLimit = .eighty
        }
        if isInstalled && installedHelperMatchesBundledHelper {
            updateConfiguration { configuration in
                if self.isPowerUIEightyOnly,
                   configuration.fixedLimit == .oneHundred {
                    configuration.fixedLimit = .eighty
                }
                configuration.enabled = true
                configuration.temporaryFullCharge = false
            }
            ensureStatusAgentInstalled()
            logger.log(.info, category: "charge", event: "user_enabled", message: "The user enabled charge protection.")
        } else {
            installHelper(enableAfterInstallation: true)
        }
    }

    /// A DMG drag replacement cannot update a root-owned helper by itself.
    /// Request one authenticated replacement on the first launch of a build
    /// whose bundled helper differs from the installed copy. Replacement also
    /// runs while protection is disabled, but preserves that disabled state.
    func requestInstalledHelperUpdateAuthorizationIfNeeded() {
        guard availability.permitsSoftwareControls,
              isInstalled,
              !installedHelperMatchesBundledHelper,
              !isBusy else { return }
        showsHelperUpdateAuthorizationPrompt = true
    }

    func continueInstalledHelperUpdate() {
        guard showsHelperUpdateAuthorizationPrompt else { return }
        showsHelperUpdateAuthorizationPrompt = false
        ensureInstalledHelperIsCurrent()
    }

    func ensureInstalledHelperIsCurrent() {
        guard availability.permitsSoftwareControls,
              isInstalled,
              !installedHelperMatchesBundledHelper,
              !isBusy else { return }
        installHelper(enableAfterInstallation: configuration.enabled)
    }

    func disable() {
        guard availability.permitsSoftwareControls, !isBusy else { return }
        errorMessage = nil
        updateConfiguration { configuration in
            configuration.enabled = false
            configuration.temporaryFullCharge = false
        }
        logger.log(.info, category: "charge", event: "user_disabled", message: "The user disabled charge protection.")
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? enable() : disable()
    }

    func setLimit(_ limit: FixedChargeLimit) {
        guard availability.permitsSoftwareControls,
              isLimitSelectable(limit.rawValue) else { return }
        let changed = configuration.fixedLimit != limit
        updateConfiguration { configuration in
            configuration.fixedLimit = limit
            configuration.temporaryFullCharge = false
            if self.isPowerUIEightyOnly, limit == .oneHundred {
                configuration.enabled = false
            }
        }
        if changed {
            logger.log(.info, category: "charge", event: "limit_changed", message: "The fixed charge limit changed to \(limit.rawValue) percent.")
        }
    }

    func selectDisplayedLimit(_ percentage: Int) {
        logger.log(
            .info,
            category: "charge",
            event: "limit_selection_requested",
            message: "The user selected the \(percentage) percent charge option."
        )
        guard availability.permitsSoftwareControls, !isBusy else { return }
        guard let limit = FixedChargeLimit(validated: percentage) else { return }
        guard isLimitSelectable(percentage) else { return }
        setLimit(limit)
        if isPowerUIEightyOnly, limit == .oneHundred { return }
        if !configuration.enabled { enable() }
    }

    func setSectionExpanded(_ expanded: Bool) {
        guard isSectionExpanded != expanded else { return }
        isSectionExpanded = expanded
        defaults.set(expanded, forKey: Self.sectionExpandedDefaultsKey)
    }

    func toggleSectionExpanded() {
        setSectionExpanded(!isSectionExpanded)
    }

    func setMenuBarStatusVisible(_ visible: Bool) {
        guard availability.permitsSoftwareControls else { return }
        updateConfiguration { $0.showMenuBarStatus = visible }
        logger.log(
            .info,
            category: "charge",
            event: "menu_bar_status_changed",
            message: visible
                ? "Charge-limit menu-bar status was enabled."
                : "Charge-limit menu-bar status was disabled."
        )
    }

    func beginTemporaryFullCharge() {
        guard configuration.enabled, availability.permitsSoftwareControls,
              configuration.fixedLimit != .oneHundred else { return }
        updateConfiguration { $0.temporaryFullCharge = true }
        logger.log(.info, category: "charge", event: "temporary_full_started", message: "A one-time full charge was requested.")
    }

    func cancelTemporaryFullCharge() {
        guard configuration.temporaryFullCharge else { return }
        updateConfiguration { $0.temporaryFullCharge = false }
        logger.log(.info, category: "charge", event: "temporary_full_cancelled", message: "The one-time full charge was cancelled.")
    }

    func openSystemBatterySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func beginSoftwareModePreparation() {
        guard availability == .systemPreferred else { return }
        hasConfirmedSystemPreparation = false
        isPreparingSoftwareMode = true
    }

    func cancelSoftwareModePreparation() {
        isPreparingSoftwareMode = false
        hasConfirmedSystemPreparation = false
    }

    func completeSoftwareModePreparation() {
        guard availability == .systemPreferred, isPreparingSoftwareMode,
              hasConfirmedSystemPreparation else { return }
        updateConfiguration {
            $0.managementMode = .softwareManaged
            $0.enabled = false
            $0.temporaryFullCharge = false
        }
        availability = .softwareManaged
        isPreparingSoftwareMode = false
        hasConfirmedSystemPreparation = false
        showsUpgradeMigrationPrompt = false
        logger.log(
            .info,
            category: "charge",
            event: "software_management_selected",
            message: "The user explicitly selected software-managed charging."
        )
    }

    func switchToSystemPreferred(openSettings: Bool = true) {
        guard isAppleSilicon, Self.isNativeChargeLimitOS(operatingSystemVersion) else { return }
        updateConfiguration {
            $0.enabled = false
            $0.temporaryFullCharge = false
            $0.managementMode = .systemPreferred
        }
        availability = .systemPreferred
        isPreparingSoftwareMode = false
        hasConfirmedSystemPreparation = false
        showsUpgradeMigrationPrompt = false
        logger.log(
            .info,
            category: "charge",
            event: "system_management_selected",
            message: "Software charge control was stopped and macOS management was selected."
        )
        if openSettings { openSystemBatterySettings() }
    }

    func continueSoftwareAfterUpgrade() {
        guard showsUpgradeMigrationPrompt else { return }
        showsUpgradeMigrationPrompt = false
        availability = .systemPreferred
        beginSoftwareModePreparation()
        setSectionExpanded(true)
    }

    func uninstall() {
        guard !isBusy, hasInstalledComponents else { return }
        errorMessage = nil
        configuration.enabled = false
        configuration.temporaryFullCharge = false
        configuration.updatedAt = Date()
        try? persistConfiguration()

        guard rootComponentsPresent else {
            finishChargeComponentUninstall()
            return
        }
        guard let script = bundledInstallScriptURL else {
            errorMessage = "The charge helper uninstaller is missing."
            return
        }
        runAdministratorScript(
            script: script,
            arguments: ["uninstall", configurationURL.path, String(getuid())]
        ) { [weak self] success, message in
            guard let self else { return }
            if success {
                self.finishChargeComponentUninstall()
            } else {
                self.errorMessage = message
                self.logger.log(.error, category: "charge", event: "helper_uninstall_failed", message: "The charge helper could not be uninstalled.")
            }
        }
    }

    /// Completes removal in the current user's domain only after the privileged
    /// helper has restored normal charging and removed its launchd job. The
    /// status Agent must stop before its configuration directory is deleted so
    /// it cannot recreate a stale configuration during teardown.
    private func finishChargeComponentUninstall() {
        guard !isBusy else { return }
        isBusy = true
        let installer = bundledStatusAgentInstallerURL
        let chargeDirectory = configurationURL.deletingLastPathComponent()
        Task { [weak self] in
            guard let self else { return }
            let agentResult: (status: Int32, error: String)
            if let installer {
                agentResult = await Task.detached {
                    Self.runUserScript(installer, arguments: ["uninstall"])
                }.value
            } else if self.userAgentComponentsPresent {
                agentResult = (127, "The menu-bar agent uninstaller is missing.")
            } else {
                agentResult = (0, "")
            }

            var removalError = agentResult.error
            if agentResult.status == 0, self.fileManager.fileExists(atPath: chargeDirectory.path) {
                do {
                    try self.fileManager.removeItem(at: chargeDirectory)
                } catch {
                    removalError = error.localizedDescription
                }
            }
            self.reloadStatus()
            self.isBusy = false

            let removalComplete = agentResult.status == 0 &&
                !self.fileManager.fileExists(atPath: chargeDirectory.path) &&
                !self.hasInstalledComponents
            if removalComplete {
                self.status = nil
                self.logger.log(
                    .info,
                    category: "charge",
                    event: "helper_uninstalled",
                    message: "Normal charging was restored and all charge-helper and menu-bar components were removed."
                )
            } else {
                self.errorMessage = DiagnosticLogger.redact(
                    removalError.isEmpty
                        ? "Some charge-helper components could not be removed."
                        : removalError
                )
                self.logger.log(
                    .error,
                    category: "charge",
                    event: "helper_uninstall_incomplete",
                    message: "Charge-helper removal left one or more installed components."
                )
            }
        }
    }

    /// Removes every executable component installed by the application before
    /// moving the app itself to Trash. User-created history reports are kept.
    func uninstallApplication(beforeRecycle: (() -> Void)? = nil) {
        guard !isBusy else { return }
        errorMessage = nil
        configuration.enabled = false
        configuration.temporaryFullCharge = false
        configuration.updatedAt = Date()
        try? persistConfiguration()

        let finish: () -> Void = { [weak self] in
            self?.finishApplicationUninstall(beforeRecycle: beforeRecycle)
        }
        guard rootComponentsPresent else {
            finish()
            return
        }
        guard let script = bundledInstallScriptURL else {
            errorMessage = "The charge helper uninstaller is missing."
            return
        }
        runAdministratorScript(
            script: script,
            arguments: ["uninstall", configurationURL.path, String(getuid())]
        ) { [weak self] success, message in
            guard let self else { return }
            if success { finish() }
            else { self.errorMessage = message }
        }
    }

    private func finishApplicationUninstall(beforeRecycle: (() -> Void)?) {
        let installer = bundledStatusAgentInstallerURL
        let chargeDirectory = configurationURL.deletingLastPathComponent()
        let logDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DriveBatteryHealthViewer", isDirectory: true)
        let applicationURL = Bundle.main.bundleURL
        let bundleIdentifier = Bundle.main.bundleIdentifier
        Task { [weak self] in
            guard let self else { return }
            let agentResult: (status: Int32, error: String)
            if let installer {
                agentResult = await Task.detached {
                    Self.runUserScript(installer, arguments: ["uninstall"])
                }.value
            } else if self.userAgentComponentsPresent {
                agentResult = (127, "The menu-bar agent uninstaller is missing.")
            } else {
                agentResult = (0, "")
            }
            guard agentResult.status == 0 else {
                self.errorMessage = DiagnosticLogger.redact(
                    agentResult.error.isEmpty
                        ? "The menu-bar charge Agent could not be removed completely."
                        : agentResult.error
                )
                return
            }
            do {
                if self.fileManager.fileExists(atPath: chargeDirectory.path) {
                    try self.fileManager.removeItem(at: chargeDirectory)
                }
                if self.fileManager.fileExists(atPath: logDirectory.path) {
                    try self.fileManager.removeItem(at: logDirectory)
                }
            } catch {
                self.errorMessage = error.localizedDescription
                return
            }
            if let bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            }
            beforeRecycle?()
            NSWorkspace.shared.recycle([applicationURL]) { _, error in
                Task { @MainActor [weak self] in
                    if let error { self?.errorMessage = error.localizedDescription }
                    else { NSApp.terminate(nil) }
                }
            }
        }
    }

    private func installHelper(enableAfterInstallation: Bool) {
        guard !isBusy else { return }
        errorMessage = nil
        guard let script = bundledInstallScriptURL,
              let helper = bundledHelperURL else {
            errorMessage = "The charge helper installation resources are missing."
            logger.log(.error, category: "charge", event: "helper_resources_missing", message: "Charge helper installation resources were missing.")
            return
        }
        do {
            if enableAfterInstallation,
               isPowerUIEightyOnly,
               configuration.fixedLimit == .oneHundred {
                configuration.fixedLimit = .eighty
            }
            configuration.enabled = enableAfterInstallation
            if enableAfterInstallation { configuration.temporaryFullCharge = false }
            configuration.updatedAt = Date()
            try persistConfiguration()
        } catch {
            configuration.enabled = false
            errorMessage = error.localizedDescription
            logger.log(.error, category: "charge", event: "configuration_write_failed", message: "The charge protection configuration could not be saved.")
            return
        }
        let arguments = [
            "install",
            helper.path,
            String(getuid()),
            fileManager.homeDirectoryForCurrentUser.path,
            configurationURL.path,
            Bundle.main.bundleURL.path
        ]
        runAdministratorScript(script: script, arguments: arguments) { [weak self] success, message in
            guard let self else { return }
            self.reloadStatus()
            if success && self.isInstalled {
                self.ensureStatusAgentInstalled()
                self.logger.log(
                    .info,
                    category: "charge",
                    event: "helper_installed",
                    message: enableAfterInstallation
                        ? "The current charge helper was installed and charge protection was enabled."
                        : "The current charge helper replaced the older installed helper while protection remained disabled."
                )
            } else {
                self.configuration.enabled = false
                try? self.persistConfiguration()
                self.errorMessage = message ?? "The charge helper could not be installed."
                let detail = DiagnosticLogger.redact(message ?? "No installer error text was returned.")
                self.logger.log(.error, category: "charge", event: "helper_install_failed", message: "The charge helper could not be installed: \(detail)")
            }
        }
    }

    private func updateConfiguration(_ mutate: (inout ChargeProtectionConfiguration) -> Void) {
        var updated = configuration
        mutate(&updated)
        updated.fixedLimit = ChargeLimitCapabilityPolicy.normalized(
            updated.fixedLimit,
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: operatingSystemVersion
        )
        updated.updatedAt = Date()
        guard updated.isValid else { return }
        do {
            configuration = updated
            try persistConfiguration()
        } catch {
            errorMessage = error.localizedDescription
            logger.log(.error, category: "charge", event: "configuration_write_failed", message: "The charge protection configuration could not be saved.")
        }
    }

    private func persistConfiguration() throws {
        try Self.writeSecureConfiguration(configuration, to: configurationURL, encoder: encoder, fileManager: fileManager)
    }

    private func reloadStatus() {
        isInstalled = fileManager.fileExists(atPath: Self.launchDaemonPath) &&
            fileManager.fileExists(atPath: Self.helperExecutablePath)
        hasInstalledComponents = rootComponentsPresent || userAgentComponentsPresent
        // The independent per-user menu-bar agent can change the limit while
        // the main application is open. Adopt only a newer, validated file so
        // both interfaces remain in sync without either process overwriting a
        // more recent user action.
        if var diskConfiguration = Self.loadConfiguration(from: configurationURL, decoder: decoder),
           diskConfiguration.updatedAt > configuration.updatedAt {
            let normalized = ChargeLimitCapabilityPolicy.normalized(
                diskConfiguration.fixedLimit,
                isAppleSilicon: isAppleSilicon,
                operatingSystemVersion: operatingSystemVersion
            )
            let disablesPowerUIHundred = isPowerUIEightyOnly &&
                diskConfiguration.enabled && normalized == .oneHundred
            if normalized != diskConfiguration.fixedLimit || disablesPowerUIHundred {
                diskConfiguration.fixedLimit = normalized
                if disablesPowerUIHundred {
                    diskConfiguration.enabled = false
                    diskConfiguration.temporaryFullCharge = false
                }
                diskConfiguration.updatedAt = Date()
                try? Self.writeSecureConfiguration(
                    diskConfiguration,
                    to: configurationURL,
                    encoder: encoder,
                    fileManager: fileManager
                )
            }
            configuration = diskConfiguration
        }
        if let data = try? Data(contentsOf: Self.statusURL),
           let decoded = try? decoder.decode(ChargeProtectionStatus.self, from: data) {
            status = decoded
            if let helperConfigurationDate = decoded.configurationUpdatedAt,
               helperConfigurationDate >= configuration.updatedAt,
               decoded.temporaryFullCharge != configuration.temporaryFullCharge {
                configuration.temporaryFullCharge = decoded.temporaryFullCharge
                configuration.updatedAt = helperConfigurationDate
                try? persistConfiguration()
            }
        } else {
            status = nil
        }
    }

    private var bundledInstallScriptURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("ChargeProtection/install-charge-helper.sh"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/ChargeProtection/install-charge-helper.sh")
        ].compactMap { $0 }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private var rootComponentsPresent: Bool {
        fileManager.fileExists(atPath: Self.launchDaemonPath) ||
            fileManager.fileExists(atPath: Self.helperExecutablePath) ||
            fileManager.fileExists(atPath: Self.statusURL.path) ||
            fileManager.fileExists(atPath: Self.powerUIOwnerURL.path) ||
            fileManager.fileExists(atPath: Self.helperLogURL.path)
    }

    private var userAgentComponentsPresent: Bool {
        let home = fileManager.homeDirectoryForCurrentUser
        let directory = home.appendingPathComponent(
            "Library/Application Support/DriveBatteryHealthViewer/\(Self.statusAgentDirectoryName)",
            isDirectory: true
        )
        let launchAgent = home.appendingPathComponent(
            "Library/LaunchAgents/\(Self.statusAgentIdentifier).plist"
        )
        return fileManager.fileExists(atPath: directory.path) ||
            fileManager.fileExists(atPath: launchAgent.path)
    }

    private var bundledHelperURL: URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DriveBatteryChargeHelper"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/arm64-apple-macosx/release/DriveBatteryChargeHelper")
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private var installedHelperMatchesBundledHelper: Bool {
        guard let bundledHelperURL,
              let bundled = try? Data(contentsOf: bundledHelperURL, options: .mappedIfSafe),
              let installed = try? Data(
                contentsOf: URL(fileURLWithPath: Self.helperExecutablePath),
                options: .mappedIfSafe
              ) else { return false }
        return bundled == installed
    }

    /// Installs a non-privileged per-user menu-bar agent. The root helper remains
    /// solely responsible for SMC access; this process only reads the public
    /// status file and writes the current user's validated configuration file.
    func ensureStatusAgentInstalled() {
        guard availability.permitsSoftwareControls, isInstalled,
              let installer = bundledStatusAgentInstallerURL,
              let executable = bundledStatusAgentURL else { return }
        Task.detached(priority: .utility) { [logger] in
            let result = Self.runUserScript(
                installer,
                arguments: ["install", executable.path]
            )
            if result.status != 0 {
                logger.log(
                    .warning,
                    category: "charge",
                    event: "status_agent_install_failed",
                    message: "The optional charge-limit menu-bar agent could not be installed."
                )
            }
        }
    }

    private var bundledStatusAgentURL: URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DriveBatteryChargeLimitAgent"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/arm64-apple-macosx/release/DriveBatteryChargeLimitAgent")
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private var bundledStatusAgentInstallerURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("ChargeProtection/install-charge-limit-agent.sh"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/ChargeProtection/install-charge-limit-agent.sh")
        ].compactMap { $0 }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private nonisolated static func runUserScript(
        _ script: URL,
        arguments: [String]
    ) -> (status: Int32, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path] + arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let error = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            return (process.terminationStatus, error)
        } catch {
            return (127, error.localizedDescription)
        }
    }

    private func runAdministratorScript(
        script: URL,
        arguments: [String],
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard !isBusy else { return }
        isBusy = true
        Task { [weak self] in
            let result = await Task.detached { () -> (Bool, String?) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            let commandText = Self.administratorCommand(script: script.path, arguments: arguments)
            process.arguments = [
                "-e", "on run argv",
                "-e", "do shell script (item 1 of argv) with administrator privileges",
                "-e", "end run",
                "--", commandText
            ]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()
            var success = false
            var message: String?
            do {
                try process.run()
                process.waitUntilExit()
                success = process.terminationStatus == 0
                if !success {
                    message = String(
                        data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    )?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                message = error.localizedDescription
            }
                return (success, message)
            }.value
            guard let self else { return }
            self.isBusy = false
            completion(result.0, DiagnosticLogger.redact(result.1 ?? ""))
        }
    }

    /// Builds one fully quoted command before entering AppleScript. Keeping the
    /// AppleScript handler to a single argv lookup avoids locale/runtime quirks
    /// in list slicing (which previously failed with error -1708 on Chinese
    /// macOS before the privileged installer was ever launched).
    nonisolated static func administratorCommand(script: String, arguments: [String]) -> String {
        ([script] + arguments).map(shellQuote).joined(separator: " ")
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func loadConfiguration(from url: URL, decoder: JSONDecoder) -> ChargeProtectionConfiguration? {
        guard let data = try? Data(contentsOf: url),
              let configuration = try? decoder.decode(ChargeProtectionConfiguration.self, from: data),
              configuration.isValid else { return nil }
        return configuration
    }

    nonisolated static func isNativeChargeLimitOS(_ version: OperatingSystemVersion) -> Bool {
        version.majorVersion > 26 || (version.majorVersion == 26 && version.minorVersion >= 4)
    }

    private static func writeSecureConfiguration(
        _ configuration: ChargeProtectionConfiguration,
        to url: URL,
        encoder: JSONEncoder,
        fileManager: FileManager
    ) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try encoder.encode(configuration)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

}
