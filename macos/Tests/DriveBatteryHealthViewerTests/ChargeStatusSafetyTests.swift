import ChargeProtectionCore
import Combine
import Foundation
import Testing
@testable import DriveBatteryHealthViewer
@testable import DriveBatteryChargeLimitAgent

@Suite("Charge status evidence")
@MainActor
struct ChargeStatusSafetyTests {
    @Test(arguments: [false, nil] as [Bool?])
    func refreshHistoryAndExportKeepSystemPowerReading(_ connected: Bool?) async throws {
        let fixture = try ChargeStatusFixture()
        defer { fixture.cleanUp() }
        let scanner = SyntheticHardware(connected: connected)
        let model = fixture.model(scanner: scanner)
        defer { model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring() }

        #expect(model.chargeProtection.status?.adapterConnected == true)
        model.refresh()
        try await waitUntil { !model.isScanning && model.currentSnapshot != nil }
        #expect(model.currentSnapshot?.batteries.first?.externalConnected == connected)
        let history = HistoryStore(directory: model.historyDirectory)
        let record = try #require(try history.load().first)
        #expect(record.source == .refresh)
        #expect(record.snapshot.batteries.first?.externalConnected == connected)

        model.historySaveMode = .export
        let reportURL = fixture.directory.appendingPathComponent("report.txt")
        model.exportCurrentReport(to: reportURL)
        let report = try String(contentsOf: reportURL, encoding: .utf8)
        let label = L10n.text("connected", .english)
        let value = L10n.text(connected == nil ? "unavailable" : "no", .english)
        #expect(report.split(separator: "\n").contains("\(label): \(value)"))
        let exported = try #require(try history.load().first { $0.source == .export })
        #expect(exported.snapshot.batteries.first?.externalConnected == connected)
    }

    @Test
    func livePollingDoesNotReplaceSystemPowerReading() async throws {
        let fixture = try ChargeStatusFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model(scanner: SyntheticHardware(connected: true))
        defer { model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring() }
        model.refresh()
        try await waitUntil { !model.isScanning && model.currentSnapshot != nil }
        model.startLiveHardwareMonitoring()
        try await waitUntil { model.currentSnapshot?.batteries.first?.currentCapacityPercent == 82 }
        #expect(model.currentSnapshot?.batteries.first?.externalConnected == false)
        #expect(model.history.count == 1)
        #expect(model.history.first?.snapshot.batteries.first?.externalConnected == true)
    }

    @Test(arguments: [0.001, 0, -19.999, -20, -20.001, -3600] as [TimeInterval])
    func statusAgeBoundaries(_ offset: TimeInterval) {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let config = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty, updatedAt: now)
        var status = sampleChargeStatus(at: now.addingTimeInterval(offset))
        status.configurationUpdatedAt = now
        let expected = offset <= 0 && offset > -20
        #expect(shouldPresentChargeLimitStatusItem(configuration: config, status: status, now: now) == expected)
        #expect(helperReportsConnectedAdapter(configuration: config, status: status, now: now) == expected)
        status.controlMethod = .powerUIOptimized80
        status.configurationUpdatedAt = now
        status.systemChargeOverride = .chargingToFull
        status.systemCalibration = .calibrating
        #expect((resolvedSystemChargeOverride(configuration: config, status: status, now: now) != nil) == expected)
        #expect((resolvedSystemCalibration(configuration: config, status: status, now: now) != nil) == expected)
    }

    @Test
    func oldOrFutureStatusCannotKeepAnErrorOrReplayFullCharge() throws {
        let fixture = try ChargeStatusFixture()
        defer { fixture.cleanUp() }
        let manager = fixture.manager()
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        var stale = sampleChargeStatus(at: now.addingTimeInterval(-20))
        stale.configurationUpdatedAt = now.addingTimeInterval(-30)
        stale.temporaryFullCharge = true
        stale.lastError = "Synthetic stale error"
        try fixture.write(stale)
        manager.reloadStatus(now: now)
        #expect(manager.status == nil)
        #expect(!manager.configuration.temporaryFullCharge)

        try fixture.write(sampleChargeStatus(at: now.addingTimeInterval(1)))
        manager.reloadStatus(now: now)
        #expect(manager.status == nil)

        #expect(manager.showsHelperStatusUnconfirmed)
        #expect(!manager.shouldShowLimitReachedStatusItem)
        #expect(!manager.hasHelperAdapterObservation)

        var current = sampleChargeStatus(at: now)
        current.configurationUpdatedAt = now
        current.configurationRevision = manager.configuration.revision
        try fixture.write(current)
        manager.reloadStatus(now: now)
        #expect(manager.status?.timestamp == now)
        #expect(!manager.showsHelperStatusUnconfirmed)
        // The same on-disk report must stop counting when the window expires.
        manager.reloadStatus(now: now.addingTimeInterval(20))
        #expect(manager.showsHelperStatusUnconfirmed)

        try Data("broken".utf8).write(to: fixture.statusURL)
        manager.reloadStatus(now: now)
        #expect(manager.status == nil)
        #expect(manager.showsHelperStatusUnconfirmed)
        try FileManager.default.removeItem(at: fixture.statusURL)
        manager.reloadStatus(now: now)
        #expect(manager.showsHelperStatusUnconfirmed)

        // This changes only the isolated configuration file.
        manager.disable()
        #expect(!manager.configuration.enabled)
        #expect(!manager.showsHelperStatusUnconfirmed)
    }

    @Test
    func identicalHelperPollsPublishOnlyChangedValues() throws {
        let fixture = try ChargeStatusFixture()
        defer { fixture.cleanUp() }
        let manager = fixture.manager()
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        var report = sampleChargeStatus(at: now)
        report.configurationRevision = manager.configuration.revision
        try fixture.write(report)
        manager.reloadStatus(now: now)
        var emissions = 0
        let subscription = manager.objectWillChange.sink { emissions += 1 }
        defer { subscription.cancel() }
        for _ in 0..<1000 { manager.reloadStatus(now: now) }
        print("IDENTICAL_HELPER_POLLS=1000 MANAGER_PUBLICATIONS=\(emissions)")
        #expect(emissions == 0)
        #expect(manager.status?.timestamp == now)
        let beforeChange = emissions
        report.holding = false
        try fixture.write(report)
        manager.reloadStatus(now: now)
        #expect(emissions > beforeChange)
        #expect(manager.status?.holding == false)
        report.timestamp = now.addingTimeInterval(1)
        try fixture.write(report)
        manager.reloadStatus(now: now.addingTimeInterval(1))
        #expect(manager.status?.timestamp == report.timestamp)
        manager.reloadStatus(now: now.addingTimeInterval(20))
        #expect(manager.status != nil)
        manager.reloadStatus(now: now.addingTimeInterval(21))
        #expect(manager.status == nil)
    }

    @Test
    func agentExpiresAnUnchangedStatusFileAndRecovers() throws {
        let fixture = try ChargeStatusFixture()
        defer { fixture.cleanUp() }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        var current = sampleChargeStatus(at: now)
        current.configurationUpdatedAt = fixture.configurationDate
        try fixture.write(current)
        let agent = ChargeLimitAgentModel(configurationDirectory: fixture.directory, statusURL: fixture.statusURL,
                                          operatingSystemVersion: .init(majorVersion: 15, minorVersion: 7, patchVersion: 0))
        agent.reload(now: now)
        #expect(agent.shouldShowStatusItem)
        #expect(agent.status?.timestamp == now)

        agent.reload(now: now.addingTimeInterval(20))
        #expect(agent.status == nil)
        #expect(!agent.shouldShowStatusItem)
        #expect(agent.presentationState == .protectionUnconfirmed)
        #expect(agent.statusItemLabel == AgentL10n.text("unconfirmed", language: agent.language))
        #expect(ChargeLimitAgentPresentationState.resolve(
            configuration: agent.configuration, status: sampleChargeStatus(at: now),
            now: now.addingTimeInterval(20)
        ) == .protectionUnconfirmed)

        current.timestamp = now.addingTimeInterval(20)
        try fixture.write(current)
        agent.reload(now: now.addingTimeInterval(20))
        #expect(agent.status?.timestamp == now.addingTimeInterval(20))
        #expect(ChargeLimitAgentPresentationState.resolve(
            configuration: agent.configuration, status: agent.status,
            now: now.addingTimeInterval(20)
        ) == .aboveLimit)
    }

    @Test
    func unknownPowerFieldsDoNotInheritAnOlderReading() async {
        let previous = await SyntheticHardware(connected: true).scan()
        var next = await SyntheticHardware(connected: nil).scan()
        next.batteries[0].isCharging = nil
        let merged = next.preservingUnavailableValues(from: previous)
        #expect(merged.batteries.first?.externalConnected == nil)
        #expect(merged.batteries.first?.isCharging == nil)

        next.warnings = ["Battery information: fixture read failure"]
        next.batteries = []
        let failed = next.preservingUnavailableValues(from: previous)
        #expect(failed.batteries.first?.name == previous.batteries.first?.name)
        #expect(failed.batteries.first?.externalConnected == nil)
        #expect(failed.batteries.first?.isCharging == nil)
    }

    @Test(arguments: AppLanguage.allCases.filter { $0 != .system })
    func chargeObservationAndUnconfirmedNoticeAreLocalized(_ language: AppLanguage) {
        for key in ["helperAdapterObservation", "helperStatusUnconfirmed"] {
            #expect(L10n.interface12Tables[language]?[key]?.isEmpty == false)
        }
    }

    @Test
    func removedOverviewNotesStayRemoved() throws {
        let macOS = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let views = try String(contentsOf: macOS.appendingPathComponent("Sources/DriveBatteryHealthViewer/Views.swift"), encoding: .utf8)
        // The report renderer and drive working-time help retain their explanations.
        let start = try #require(views.range(of: "struct OverviewView"))
        let end = try #require(views.range(of: "\nstruct ", range: start.upperBound..<views.endIndex))
        let overview = views[start.lowerBound..<end.lowerBound]
        for key in ["overviewLimitations", "driveWorkingTimeExplanation", "batteryHealthExplanation"] {
            #expect(!overview.contains("\"\(key)\""))
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(4)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

private struct SyntheticHardware: HardwareScanning {
    let connected: Bool?

    func scan() async -> HealthSnapshot {
        let battery = BatteryInfo(name: "Fixture battery", currentCapacityPercent: 81,
                                  isCharging: false, externalConnected: connected,
                                  healthState: .good, notes: [])
        return HealthSnapshot(computerName: "Fixture Mac", drives: [], batteries: [battery])
    }

    func readLiveBatteryState() async -> BatteryLiveState? {
        BatteryLiveState(chargePercent: 82, isCharging: false, externalConnected: false, temperatureCelsius: nil)
    }

    func readLiveDriveTemperatures(driveIdentifiers: [String]) async -> [String: Double] { [:] }
}

private func sampleChargeStatus(at date: Date) -> ChargeProtectionStatus {
    ChargeProtectionStatus(helperVersion: "fixture", timestamp: date, installed: true, enabled: true,
                           fixedLimit: .eighty, temporaryFullCharge: false, configurationUpdatedAt: date, holding: true,
                           adapterConnected: true, batteryPercentage: 82, controlMethod: .chieFallback)
}

@MainActor
private struct ChargeStatusFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DBHV-charge-tests-\(UUID())")
    let suite = "DBHV-charge-tests-\(UUID())"
    let defaults: UserDefaults
    let configurationDate = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    var statusURL: URL { directory.appendingPathComponent("status.json") }

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("en", forKey: "language")
        defaults.set(directory.appendingPathComponent("history").path, forKey: "historyDirectory")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let config = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty, updatedAt: configurationDate)
        try encoder.encode(config).write(to: directory.appendingPathComponent("configuration.json"))
        try write(sampleChargeStatus(at: Date()))
    }

    func manager() -> ChargeProtectionManager {
        ChargeProtectionManager(defaults: defaults, logger: QuietChargeTestLogger(), isAppleSilicon: true,
                                operatingSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 0),
                                configurationDirectory: directory, statusURL: statusURL)
    }

    func model(scanner: any HardwareScanning) -> AppModel {
        AppModel(defaults: defaults, scanner: scanner, diagnosticLogger: QuietChargeTestLogger(), chargeProtection: manager())
    }

    func write(_ status: ChargeProtectionStatus) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(status).write(to: statusURL, options: .atomic)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct QuietChargeTestLogger: DiagnosticLogging {
    func log(_ severity: DiagnosticSeverity, category: String, event: String, message: String) {}
}
