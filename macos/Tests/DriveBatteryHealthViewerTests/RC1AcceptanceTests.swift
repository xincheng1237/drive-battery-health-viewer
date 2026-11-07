import Foundation
import ChargeProtectionCore
import Testing
@testable import DriveBatteryHealthViewer
@testable import DriveBatteryChargeLimitAgent

@MainActor
@Suite("Independent RC1 acceptance", .serialized)
struct RC1AcceptanceTests {
    @Test func legacyPreferencesHistoryAndHelperWireFormat() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DBHV-RC1-QA-\(UUID())")
        let suite = "com.chengxin.dbhv.qa.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let history = directory.appendingPathComponent("history")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let legacyRecord = history.appendingPathComponent("v1.2-synthetic.hhv.json")
        let payload = Data("""
        {"id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","version":"1.2","source":"refresh",
         "snapshot":{"id":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB","generatedAt":"2026-11-06T08:00:00Z",
         "computerName":"QA fixture","drives":[],"batteries":[{"name":"QA battery","externalConnected":false,
         "isCharging":false,"healthState":"good","notes":[]}],"warnings":[]}}
        """.utf8)
        try payload.write(to: legacyRecord)
        defaults.set(history.path, forKey: "historyDirectory")
        defaults.set("en", forKey: "language")
        defaults.set(false, forKey: "hideSerials")
        defaults.set("export", forKey: "historySaveMode")
        defaults.set("extraLarge", forKey: "displaySize")
        defaults.set(18.0, forKey: "reportTextSize")
        defaults.set("1.2", forKey: "lastLaunchedAppVersion")
        defaults.set("1.2#35", forKey: "lastLaunchedAppReleaseIdentifier")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let config = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty, showMenuBarStatus: false)
        try encoder.encode(config).write(to: directory.appendingPathComponent("configuration.json"))
        let statusURL = directory.appendingPathComponent("status.json")
        let oldHelper = ChargeProtectionStatus(helperVersion: "1.1.2.1", installed: true, enabled: true,
            fixedLimit: .eighty, temporaryFullCharge: false, configurationUpdatedAt: config.updatedAt, holding: true,
            adapterConnected: true, batteryPercentage: 80, controlMethod: .chte)
        try encoder.encode(oldHelper).write(to: statusURL)
        let logger = DiagnosticLogger(directory: directory.appendingPathComponent("logs"))
        let os = OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 0)
        let manager = ChargeProtectionManager(defaults: defaults, logger: logger, isAppleSilicon: true,
            operatingSystemVersion: os, configurationDirectory: directory, statusURL: statusURL)
        let model = AppModel(defaults: defaults, currentAppVersion: "1.2.1", currentAppBuild: "36",
            diagnosticLogger: logger, chargeProtection: manager)
        defer { model.stopChargeProtectionMonitoring(); model.stopLiveHardwareMonitoring(); logger.flush() }
        #expect(model.showsVersionUpdatePrompt)
        #expect(model.language == .english)
        #expect(!model.hideSerials)
        #expect(model.historySaveMode == .export)
        #expect(model.displaySize == .extraLarge)
        #expect(model.reportTextSize == 18)
        #expect(model.history.first?.version == "1.2")
        #expect(model.history.first?.snapshot.batteries.first?.externalConnected == false)
        #expect(manager.status?.adapterConnected == true)
        #expect(manager.configuration.enabled && manager.configuration.fixedLimit == .eighty)
        #expect(!manager.configuration.showMenuBarStatus)
        model.selectAllHistory()
        let exports = directory.appendingPathComponent("exports")
        model.exportSelectedHistory(to: exports)
        let folders = try FileManager.default.contentsOfDirectory(at: exports, includingPropertiesForKeys: nil)
        let files = try FileManager.default.contentsOfDirectory(at: try #require(folders.first), includingPropertiesForKeys: nil)
        let report = try String(contentsOf: try #require(files.first), encoding: .utf8)
        #expect(report.split(separator: "\n").contains("\(L10n.text("connected", .english)): \(L10n.text("no", .english))"))
        #expect(try Data(contentsOf: legacyRecord) == payload)

        let agent = ChargeLimitAgentModel(configurationDirectory: directory, statusURL: statusURL, operatingSystemVersion: os)
        #expect(agent.configuration.enabled && agent.configuration.fixedLimit == .eighty)
        #expect(agent.status?.helperVersion == "1.1.2.1")
        #expect(!agent.shouldShowStatusItem)
        let reopened = AppModel(defaults: defaults, currentAppVersion: "1.2.1", currentAppBuild: "36",
            diagnosticLogger: logger, chargeProtection: manager)
        defer { reopened.stopChargeProtectionMonitoring(); reopened.stopLiveHardwareMonitoring() }
        #expect(!reopened.showsVersionUpdatePrompt)
        #expect(reopened.history.first?.snapshot.batteries.first?.externalConnected == false)
    }

    @Test func freshReportForPreviousConfigurationMustNotConfirmHold() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let config = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty, updatedAt: now)
        let status = ChargeProtectionStatus(helperVersion: "1.1.2.1", timestamp: now.addingTimeInterval(-2),
            installed: true, enabled: true, fixedLimit: .eighty, temporaryFullCharge: false,
            configurationUpdatedAt: now.addingTimeInterval(-8), holding: true, adapterConnected: true,
            batteryPercentage: 80, controlMethod: .chte)
        #expect(status.isFresh(at: now))
        #expect(!shouldPresentChargeLimitStatusItem(configuration: config, status: status, now: now))
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: config, status: status, now: now) != .limitReached)
    }

    @Test func freshPowerUIReportWithUnknownSystemPauseMustNotConfirmHold() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let config = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty, updatedAt: now)
        let status = ChargeProtectionStatus(helperVersion: "1.1.2.1", timestamp: now,
            installed: true, enabled: true, fixedLimit: .eighty, temporaryFullCharge: false,
            configurationUpdatedAt: now, holding: true, adapterConnected: true,
            batteryPercentage: 80, controlMethod: .powerUIOptimized80)
        #expect(!shouldPresentChargeLimitStatusItem(configuration: config, status: status, now: now))
    }

    @Test func bothSurfacesRecoverAfterCurrentEvidenceArrives() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let config = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty, updatedAt: now)
        var report = ChargeProtectionStatus(helperVersion: "fixture", timestamp: now, installed: true,
            enabled: true, fixedLimit: .eighty, temporaryFullCharge: false, configurationUpdatedAt: nil,
            holding: true, adapterConnected: true, batteryPercentage: 80, controlMethod: .powerUIOptimized80)
        func reason() -> BatteryPowerNoticeReason? {
            BatteryPowerNoticeReason.resolve(externalConnected: true, isCharging: false, batteryPercentage: 80,
                                             configuration: config, status: report, now: now)
        }
        #expect(reason() == .ordinary)
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: config, status: report, now: now) == .protectionUnconfirmed)
        report.configurationUpdatedAt = config.updatedAt
        report.systemCalibration = .inactive
        #expect(reason() == .ordinary)
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: config, status: report, now: now) == .protectionUnconfirmed)
        report.systemChargeOverride = .inactive
        #expect(reason() == .chargeLimit)
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: config, status: report, now: now) == .limitReached)
        report.systemCalibration = .calibrating
        report.systemChargeOverride = nil
        #expect(reason() == .ordinary)
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: config, status: report, now: now) == .systemCalibration)
    }

    @Test func sevenAgentTranslationsExist() {
        for language in [AgentLanguage.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese] {
            let title = AgentL10n.text("unconfirmed", language: language)
            #expect(!title.isEmpty && title != "unconfirmed")
            #expect(title != AgentL10n.active(80, language: language))
            if language != .english { #expect(title != AgentL10n.text("unconfirmed", language: .english)) }
        }
    }
}
