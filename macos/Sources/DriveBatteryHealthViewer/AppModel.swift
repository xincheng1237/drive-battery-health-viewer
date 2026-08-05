import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var destination: SidebarDestination? = .overview
    @Published private(set) var currentSnapshot: HealthSnapshot?
    @Published private(set) var history: [HistoryRecord] = []
    @Published var selectedHistoryID: UUID?
    @Published private(set) var isScanning = false
    @Published var alertMessage: String?
    @Published var transientMessage: String?

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
    private var liveHardwareTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, scanner: HardwareScanner = HardwareScanner()) {
        self.defaults = defaults
        self.scanner = scanner
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

    func deleteSelectedHistory() {
        guard let record = selectedHistory else { return }
        do {
            try HistoryStore(directory: historyDirectory).delete(record)
            history.removeAll { $0.id == record.id }
            selectedHistoryID = history.first?.id
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func loadHistory() {
        do {
            history = try HistoryStore(directory: historyDirectory).load()
            if selectedHistoryID == nil { selectedHistoryID = history.first?.id }
        } catch {
            history = []
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
