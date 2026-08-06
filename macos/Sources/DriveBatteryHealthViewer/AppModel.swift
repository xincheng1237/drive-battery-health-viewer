import AppKit
import Foundation
import SwiftUI

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
    @Published var availableUpdate: AvailableAppUpdate?
    @Published private(set) var isCheckingForUpdates = false

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
    private var liveHardwareTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        scanner: HardwareScanner = HardwareScanner(),
        releaseChecker: any AppReleaseChecking = GitHubReleaseChecker(),
        currentAppVersion: String? = nil
    ) {
        self.defaults = defaults
        self.scanner = scanner
        self.releaseChecker = releaseChecker
        self.currentAppVersion = currentAppVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? applicationVersion
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
    }

    var selectedHistory: HistoryRecord? {
        guard let selectedHistoryID else { return history.first }
        return history.first { $0.id == selectedHistoryID }
    }

    var reportText: String? {
        currentSnapshot.map { ReportRenderer.render(snapshot: $0, language: language, hideSerials: hideSerials) }
    }

    func t(_ key: String) -> String { L10n.text(key, language) }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let snapshot = await scanner.scan()
            let merged = snapshot.preservingUnavailableValues(from: currentSnapshot)
            currentSnapshot = merged
            isScanning = false
            if historySaveMode == .refresh {
                saveHistory(snapshot: merged, source: .refresh)
            }
        }
    }

    func startLiveHardwareMonitoring() {
        guard liveHardwareTask == nil else { return }
        liveHardwareTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let snapshot = self.currentSnapshot {
                    let state = await self.scanner.readLiveHardwareState(
                        driveIdentifiers: snapshot.drives.map(\.deviceIdentifier)
                    )
                    if let latestSnapshot = self.currentSnapshot {
                        self.currentSnapshot = latestSnapshot.updatingLiveHardwareState(state)
                    }
                }
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func stopLiveHardwareMonitoring() {
        liveHardwareTask?.cancel()
        liveHardwareTask = nil
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
    }
}
