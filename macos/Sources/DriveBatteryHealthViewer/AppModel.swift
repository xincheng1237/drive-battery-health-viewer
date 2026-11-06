import AppKit
import Foundation
import SwiftUI

enum HardwareRefreshReason: Equatable {
    case userInitiated
    case coldLaunch
    case resumedAfterExtendedBackground
    case lifecycleRecovery

    var permitsAutomaticHistorySave: Bool {
        switch self {
        case .userInitiated, .coldLaunch, .resumedAfterExtendedBackground:
            true
        case .lifecycleRecovery:
            false
        }
    }
}

enum BackgroundRefreshPolicy {
    static let checkpointInterval: TimeInterval = 24 * 60 * 60

    static func requiresCheckpoint(backgroundedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(backgroundedAt) >= checkpointInterval
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var destination: SidebarDestination? = .overview
    @Published private(set) var currentSnapshot: HealthSnapshot?
    @Published private(set) var history: [HistoryRecord] = []
    @Published var selectedHistoryID: UUID?
    @Published var selectedHistoryIDs: Set<UUID> = []
    @Published private(set) var isScanning = false
    @Published var alertMessage: String?
    @Published var transientMessage: String?
    @Published var showsChangelog = false
    @Published private(set) var showsVersionUpdatePrompt = false
    @Published var availableUpdate: AvailableAppUpdate?
    @Published private(set) var isCheckingForUpdates = false
    @Published var showsDiagnosticExport = false

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            MainMenuLocalizer.apply(language)
        }
    }
    @Published var hideSerials: Bool {
        didSet { defaults.set(hideSerials, forKey: Keys.hideSerials) }
    }
    @Published var historySaveMode: HistorySaveMode {
        didSet { defaults.set(historySaveMode.rawValue, forKey: Keys.historySaveMode) }
    }
    @Published var reportTextSize: Double {
        didSet { defaults.set(reportTextSize, forKey: Keys.reportTextSize) }
    }
    @Published var historyDirectory: URL {
        didSet {
            defaults.set(historyDirectory.path, forKey: Keys.historyDirectory)
            loadHistory()
        }
    }

    private let defaults: UserDefaults
    private let scanner: HardwareScanner
    private let releaseChecker: any AppReleaseChecking
    private let currentAppVersion: String
    let chargeProtection: ChargeProtectionManager
    private let diagnosticLogger: any DiagnosticLogging
    private let diagnosticExporter: DiagnosticLogExporter
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt = 0
    private var liveHardwareTask: Task<Void, Never>?
    private var liveDriveTemperatureTask: Task<Void, Never>?
    private var liveHardwareGeneration: UInt = 0

    init(
        defaults: UserDefaults = .standard,
        scanner: HardwareScanner = HardwareScanner(),
        releaseChecker: any AppReleaseChecking = GitHubReleaseChecker(),
        currentAppVersion: String? = nil,
        currentAppBuild: String? = nil,
        diagnosticLogger: any DiagnosticLogging = DiagnosticLogger.shared,
        diagnosticExporter: DiagnosticLogExporter = DiagnosticLogExporter(),
        chargeProtection: ChargeProtectionManager? = nil
    ) {
        let resolvedAppVersion = currentAppVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? applicationVersion
        let resolvedAppBuild = currentAppBuild
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "1"
        let previousAppVersion = defaults.string(forKey: Keys.lastLaunchedAppVersion)
        let previousReleaseIdentifier = defaults.string(forKey: Keys.lastLaunchedAppReleaseIdentifier)
        let hasExistingAppData = Keys.preexistingPreferenceKeys.contains {
            defaults.object(forKey: $0) != nil
        }
        showsVersionUpdatePrompt = VersionUpdatePromptPolicy.shouldPresent(
            previousReleaseIdentifier: previousReleaseIdentifier,
            legacyPreviousVersion: previousAppVersion,
            currentVersion: resolvedAppVersion,
            currentBuild: resolvedAppBuild,
            hasExistingAppData: hasExistingAppData
        )
        defaults.set(resolvedAppVersion, forKey: Keys.lastLaunchedAppVersion)
        if let releaseIdentifier = VersionUpdatePromptPolicy.releaseIdentifier(
            version: resolvedAppVersion,
            build: resolvedAppBuild
        ) {
            defaults.set(releaseIdentifier, forKey: Keys.lastLaunchedAppReleaseIdentifier)
        }
        self.defaults = defaults
        self.scanner = scanner
        self.releaseChecker = releaseChecker
        self.diagnosticLogger = diagnosticLogger
        self.diagnosticExporter = diagnosticExporter
        self.chargeProtection = chargeProtection ?? ChargeProtectionManager(
            defaults: defaults,
            logger: diagnosticLogger
        )
        self.currentAppVersion = resolvedAppVersion
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        hideSerials = defaults.object(forKey: Keys.hideSerials) as? Bool ?? true
        historySaveMode = HistorySaveMode(rawValue: defaults.string(forKey: Keys.historySaveMode) ?? "") ?? .refresh
        let size = defaults.double(forKey: Keys.reportTextSize)
        reportTextSize = size == 0 ? 13 : min(22, max(11, size))
        if let path = defaults.string(forKey: Keys.historyDirectory), !path.isEmpty {
            historyDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            historyDirectory = HistoryStore.defaultDirectory
        }
        loadHistory()
        self.chargeProtection.startMonitoring()
        diagnosticLogger.log(.info, category: "lifecycle", event: "model_initialized", message: "Application model initialized for version \(self.currentAppVersion).")
    }

    var selectedHistory: HistoryRecord? {
        guard let selectedHistoryID else { return history.first }
        return history.first { $0.id == selectedHistoryID }
    }

    var reportText: String? {
        currentSnapshot.map { ReportRenderer.render(snapshot: $0, language: language, hideSerials: hideSerials) }
    }

    var displayedAppVersion: String { currentAppVersion }

    func t(_ key: String) -> String { L10n.text(key, language) }

    func refresh() {
        performRefresh(reason: .userInitiated)
    }

    /// A cold launch is a meaningful report checkpoint. It may create one
    /// history record after the full hardware scan, according to the user's
    /// history-save setting. Lightweight live polling remains independent.
    func refreshForColdLaunch() {
        performRefresh(reason: .coldLaunch)
    }

    /// Returning after a full day in the background creates a new checkpoint
    /// using a complete scan, without treating intervening live values as
    /// reports of their own.
    func refreshAfterExtendedBackground() {
        performRefresh(reason: .resumedAfterExtendedBackground)
    }

    /// Performs an incidental lifecycle recovery without creating history.
    /// Wake/window recovery and the live battery/temperature monitors must
    /// never add report records on their own.
    func refreshWithoutSavingHistory() {
        performRefresh(reason: .lifecycleRecovery)
    }

    private func performRefresh(reason: HardwareRefreshReason) {
        guard !isScanning else { return }
        diagnosticLogger.log(.info, category: "hardware", event: "refresh_started", message: "A hardware refresh started.")
        isScanning = true
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.scanner.scan()
            guard !Task.isCancelled, self.refreshGeneration == generation else {
                if self.refreshGeneration == generation {
                    self.isScanning = false
                    self.refreshTask = nil
                }
                return
            }
            var merged = snapshot.preservingUnavailableValues(from: self.currentSnapshot)
            if self.chargeProtection.confirmsExternalPowerConnection {
                for index in merged.batteries.indices {
                    merged.batteries[index].externalConnected = true
                }
            }
            self.currentSnapshot = merged
            self.isScanning = false
            self.refreshTask = nil
            self.diagnosticLogger.log(
                snapshot.warnings.isEmpty ? .info : .warning,
                category: "hardware",
                event: "refresh_completed",
                message: "Hardware refresh completed with \(merged.drives.count) drive(s); battery present: \(!merged.batteries.isEmpty)."
            )
            if reason.permitsAutomaticHistorySave, self.historySaveMode == .refresh {
                self.saveHistory(snapshot: merged, source: .refresh)
            }
        }
    }

    func startLiveHardwareMonitoring() {
        if liveHardwareTask != nil, liveDriveTemperatureTask != nil { return }
        if liveHardwareTask == nil, liveDriveTemperatureTask == nil {
            liveHardwareGeneration &+= 1
        }
        let generation = liveHardwareGeneration
        if liveHardwareTask == nil {
            liveHardwareTask = Task { [weak self] in
                defer {
                    if let self, self.liveHardwareGeneration == generation {
                        self.liveHardwareTask = nil
                    }
                }
                while !Task.isCancelled {
                    guard let self else { return }
                    let battery = await self.scanner.readLiveBatteryState()
                    guard !Task.isCancelled, self.liveHardwareGeneration == generation else { return }
                    if let battery, let latestSnapshot = self.currentSnapshot {
                        var updated = latestSnapshot.updatingLiveHardwareState(
                            LiveHardwareState(battery: battery, driveTemperatures: [:])
                        )
                        if self.chargeProtection.confirmsExternalPowerConnection {
                            for index in updated.batteries.indices {
                                updated.batteries[index].externalConnected = true
                            }
                        }
                        self.currentSnapshot = updated
                    }
                    do {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } catch {
                        return
                    }
                }
            }
        }
        // NVMe temperature reads use a separate task because a controller or
        // bridge can occasionally block. Battery level and power state must
        // continue updating even while a drive interface is slow or stale.
        if liveDriveTemperatureTask == nil {
            liveDriveTemperatureTask = Task { [weak self] in
                defer {
                    if let self, self.liveHardwareGeneration == generation {
                        self.liveDriveTemperatureTask = nil
                    }
                }
                while !Task.isCancelled {
                    guard let self else { return }
                    let identifiers = self.currentSnapshot?.drives
                        .filter(\.supportsNativeNVMeLiveReading)
                        .map(\.deviceIdentifier) ?? []
                    let temperatures = await self.scanner.readLiveDriveTemperatures(
                        driveIdentifiers: identifiers
                    )
                    guard !Task.isCancelled, self.liveHardwareGeneration == generation else { return }
                    if !temperatures.isEmpty, let latestSnapshot = self.currentSnapshot {
                        self.currentSnapshot = latestSnapshot.updatingLiveHardwareState(
                            LiveHardwareState(battery: nil, driveTemperatures: temperatures)
                        )
                    }
                    do {
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                    } catch {
                        return
                    }
                }
            }
        }
    }

    func stopLiveHardwareMonitoring() {
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        isScanning = false
        liveHardwareGeneration &+= 1
        liveHardwareTask?.cancel()
        liveHardwareTask = nil
        liveDriveTemperatureTask?.cancel()
        liveDriveTemperatureTask = nil
    }

    func stopChargeProtectionMonitoring() {
        chargeProtection.stopMonitoring()
    }

    func copyCurrentReport() {
        guard let reportText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText, forType: .string)
        showTransient(t("copied"))
    }

    func exportCurrentReport(to url: URL) {
        guard let snapshot = currentSnapshot else { return }
        let text = ReportRenderer.render(snapshot: snapshot, language: language, hideSerials: hideSerials)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            if historySaveMode == .export {
                saveHistory(snapshot: snapshot, source: .export, exportPath: url.path)
            }
            showTransient(t("exported"))
        } catch {
            alertMessage = error.localizedDescription
            diagnosticLogger.log(.error, category: "report", event: "export_failed", message: "The current report could not be exported because the selected path was unavailable.")
        }
    }

    func presentExportCurrentReportPanel() {
        guard let snapshot = currentSnapshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        panel.nameFieldStringValue = "DriveBatteryHealth_\(formatter.string(from: snapshot.generatedAt)).txt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportCurrentReport(to: url)
        }
    }

    func openReportFolder() {
        try? FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(historyDirectory)
    }

    func increaseReportTextSize() {
        reportTextSize = min(22, reportTextSize + 1)
    }

    func decreaseReportTextSize() {
        reportTextSize = max(11, reportTextSize - 1)
    }

    func resetReportTextSize() {
        reportTextSize = 13
    }

    func checkForUpdates() {
        guard !isCheckingForUpdates else { return }
        Task { await checkForUpdatesNow() }
    }

    func dismissVersionUpdatePrompt() {
        showsVersionUpdatePrompt = false
    }

    func presentChangelogFromVersionUpdatePrompt() {
        showsVersionUpdatePrompt = false
        destination = .about
        // Let NavigationSplitView finish switching destinations before the
        // About view presents its sheet. This avoids a lost presentation on
        // the first click while keeping the hint completely nonmodal.
        DispatchQueue.main.async { [weak self] in
            self?.showsChangelog = true
        }
    }

    func checkForUpdatesNow() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        availableUpdate = nil
        defer { isCheckingForUpdates = false }

        do {
            let release = try await releaseChecker.latestStableRelease()
            guard let normalizedCurrentVersion = AppVersion.normalized(currentAppVersion),
                  let current = AppVersion(normalizedCurrentVersion),
                  let latest = AppVersion(release.version) else {
                throw UpdateCheckError.invalidRelease
            }
            if current < latest {
                availableUpdate = AvailableAppUpdate(
                    currentVersion: normalizedCurrentVersion,
                    version: release.version,
                    pageURL: release.pageURL
                )
            } else {
                alertMessage = L10n.format("alreadyLatestVersion", language, normalizedCurrentVersion)
            }
        } catch {
            alertMessage = t("updateCheckFailed")
            diagnosticLogger.log(.error, category: "update", event: "update_check_failed", message: "The update request or release response could not be processed.")
        }
    }

    func presentDiagnosticExport() {
        showsDiagnosticExport = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func uninstallApplication(deleteHistory: Bool) {
        let deleteSelectedHistoryData = { [weak self] in
            guard deleteHistory, let self else { return }
            let store = HistoryStore(directory: historyDirectory)
            for record in history { try? store.delete(record) }
            history.removeAll()
            selectedHistoryIDs.removeAll()
            selectedHistoryID = nil
        }
        chargeProtection.uninstallApplication(beforeRecycle: deleteSelectedHistoryData)
    }

    func exportDiagnostics(request: DiagnosticExportRequest, to destination: URL) throws {
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let context = DiagnosticExportContext(
            appVersion: currentAppVersion,
            buildVersion: buildVersion,
            selectedLanguage: L10n.effective(language).rawValue,
            helperInstalled: chargeProtection.isInstalled,
            protectionEnabled: chargeProtection.availability.permitsSoftwareControls ? chargeProtection.configuration.enabled : nil,
            fixedLimit: chargeProtection.availability.permitsSoftwareControls ? chargeProtection.configuration.fixedLimit.rawValue : nil
        )
        do {
            try diagnosticExporter.export(request: request, context: context, destination: destination)
            diagnosticLogger.log(.info, category: "diagnostics", event: "export_completed", message: "Diagnostic logs were exported successfully.")
        } catch {
            diagnosticLogger.log(.error, category: "diagnostics", event: "export_failed", message: "Diagnostic logs could not be exported.")
            throw error
        }
    }

    func deleteSelectedHistory() {
        guard let selectedHistoryID else { return }
        deleteHistory(ids: [selectedHistoryID])
    }

    func toggleHistorySelection(_ id: UUID) {
        if selectedHistoryIDs.contains(id) {
            selectedHistoryIDs.remove(id)
        } else {
            selectedHistoryIDs.insert(id)
        }
    }

    func selectAllHistory() {
        selectedHistoryIDs = Set(history.map(\.id))
    }

    func selectHistoryRange(from anchorID: UUID, through targetID: UUID) {
        guard let anchorIndex = history.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = history.firstIndex(where: { $0.id == targetID }) else { return }
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedHistoryIDs.formUnion(bounds.map { history[$0].id })
    }

    func clearHistorySelection() {
        selectedHistoryIDs.removeAll()
    }

    func deleteSelectedHistory(ids: Set<UUID>) {
        deleteHistory(ids: ids)
    }

    private func deleteHistory(ids: Set<UUID>) {
        let records = history.filter { ids.contains($0.id) }
        guard !records.isEmpty else { return }
        do {
            let store = HistoryStore(directory: historyDirectory)
            for record in records { try store.delete(record) }
            history.removeAll { ids.contains($0.id) }
            selectedHistoryIDs.subtract(ids)
            selectedHistoryID = history.first?.id
        } catch {
            alertMessage = error.localizedDescription
            diagnosticLogger.log(.error, category: "history", event: "delete_failed", message: "One or more selected history records could not be deleted.")
        }
    }

    /// Exports each selected history record as a UTF-8 text report into one
    /// newly-created folder inside the user-selected destination directory.
    func exportSelectedHistory(to destination: URL) {
        let records = history.filter { selectedHistoryIDs.contains($0.id) }
        guard !records.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folder = destination.appendingPathComponent(
            "DriveBatteryHealthViewer-Reports-\(formatter.string(from: Date()))",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let fileFormatter = DateFormatter()
            fileFormatter.locale = Locale(identifier: "en_US_POSIX")
            fileFormatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
            for record in records {
                let filename = "HHV_\(fileFormatter.string(from: record.snapshot.generatedAt))_\(record.id.uuidString).txt"
                let url = folder.appendingPathComponent(filename)
                let text = ReportRenderer.render(
                    snapshot: record.snapshot,
                    language: language,
                    hideSerials: hideSerials
                )
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            showTransient(t("batchExported"))
        } catch {
            alertMessage = error.localizedDescription
            diagnosticLogger.log(.error, category: "history", event: "batch_export_failed", message: "Selected history records could not be exported because the selected path was unavailable.")
        }
    }

    func loadHistory() {
        do {
            history = try HistoryStore(directory: historyDirectory).load()
            selectedHistoryIDs = selectedHistoryIDs.intersection(Set(history.map(\.id)))
            if selectedHistoryID == nil { selectedHistoryID = history.first?.id }
        } catch {
            history = []
            selectedHistoryIDs.removeAll()
            alertMessage = error.localizedDescription
            diagnosticLogger.log(.error, category: "history", event: "load_failed", message: "History records could not be read from the configured history directory.")
        }
    }

    private func saveHistory(snapshot: HealthSnapshot, source: HistorySource, exportPath: String? = nil) {
        do {
            let record = try HistoryStore(directory: historyDirectory).save(
                snapshot: snapshot,
                source: source,
                exportPath: exportPath,
                hideSerials: hideSerials
            )
            history.insert(record, at: 0)
            selectedHistoryID = record.id
        } catch {
            alertMessage = error.localizedDescription
            diagnosticLogger.log(.error, category: "history", event: "save_failed", message: "A history record could not be saved to the configured history directory.")
        }
    }

    private func showTransient(_ text: String) {
        transientMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            if transientMessage == text { transientMessage = nil }
        }
    }

    private enum Keys {
        static let language = "language"
        static let hideSerials = "hideSerials"
        static let historySaveMode = "historySaveMode"
        static let reportTextSize = "reportTextSize"
        static let historyDirectory = "historyDirectory"
        static let lastLaunchedAppVersion = "lastLaunchedAppVersion"
        static let lastLaunchedAppReleaseIdentifier = "lastLaunchedAppReleaseIdentifier"
        static let preexistingPreferenceKeys = [
            language, hideSerials, historySaveMode, reportTextSize, historyDirectory,
            "chargeProtectionSectionExpanded", "chargeProtectionLastNativeLimitBoundary"
        ]
    }
}
