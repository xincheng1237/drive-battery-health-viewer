import AppKit
import CryptoKit
import Foundation
import Sparkle
import SwiftUI
import Testing
@testable import DriveBatteryHealthViewer

@Suite("Native window and signed updates")
struct UpdateAndWindowTests {
    private var package: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func updatePolicyRequiresSignedFeedAndArchiveAndExplicitUserAction() throws {
        let data = try Data(contentsOf: package.appendingPathComponent("Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(info["CFBundleShortVersionString"] as? String == applicationVersion)
        #expect(info["CFBundleVersion"] as? String == "36")
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SUSignedFeedFailureExpirationInterval"] as? Int == 0)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUScheduledCheckInterval"] as? Int == 604800)
        #expect(info["SUAllowsAutomaticUpdates"] as? Bool == false)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(info["SUEnableSystemProfiling"] as? Bool == false)
        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        let url = try #require(URL(string: info["SUFeedURL"] as? String ?? ""))
        #expect(url.scheme == "https" && url.host == "raw.githubusercontent.com")
    }

    @Test func publishedFeedAuthenticatesItsExactBytesAndLocalizedNotes() throws {
        let data = try Data(contentsOf: package.appendingPathComponent("updates/appcast.xml"))
        let text = try #require(String(data: data, encoding: .utf8))
        let regex = try NSRegularExpression(pattern: "edSignature: ([A-Za-z0-9+/=]+)\\nlength: ([0-9]+)")
        let match = try #require(regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)))
        let sigRange = try #require(Range(match.range(at: 1), in: text))
        let lenRange = try #require(Range(match.range(at: 2), in: text))
        let signature = try #require(Data(base64Encoded: String(text[sigRange])))
        let length = try #require(Int(text[lenRange]))
        let info = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: package.appendingPathComponent("Info.plist")), format: nil) as? [String: Any])
        let keyString = try #require(info["SUPublicEDKey"] as? String)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: #require(Data(base64Encoded: keyString)))
        #expect(length > 0 && length < data.count)
        let signed = Data(data.prefix(length))
        #expect(key.isValidSignature(signature, for: signed))
        var tampered = signed
        tampered[0] ^= 1
        #expect(!key.isValidSignature(signature, for: tampered))
        let document = try XMLDocument(data: data)
        let items = try document.nodes(forXPath: "/rss/channel/item")
        if items.isEmpty {
            #expect(try document.nodes(forXPath: "/rss/channel/description").first?.stringValue?.contains("withdrawn") == true)
            return
        }
        let descriptions = try document.nodes(forXPath: "/rss/channel/item/description")
        #expect(descriptions.count == 7)
        for language in ["en", "zh-Hans", "ru", "fr", "de", "ko", "ja"] {
            #expect(descriptions.contains { ($0 as? XMLElement)?.attribute(forName: "xml:lang")?.stringValue == language })
        }
        // The public signed feed still points to the published build.
        let version = "1.2"
        let build = "35"
        #expect(try document.nodes(forXPath: "/rss/channel/item/sparkle:version").first?.stringValue == build)
        #expect(try document.nodes(forXPath: "/rss/channel/item/sparkle:shortVersionString").first?.stringValue == version)
        let enclosure = try #require(document.nodes(forXPath: "/rss/channel/item/enclosure").first as? XMLElement)
        #expect(enclosure.attribute(forName: "url")?.stringValue == "https://github.com/xincheng1237/drive-battery-health-viewer/releases/download/v\(version)/DriveBatteryHealthViewer_v\(version)_build\(build)_macOS_Universal.zip")
    }

    @Test @MainActor func samePublicVersionUsesIncreasingBuildNumbers() {
        let comparator = SUStandardVersionComparator.default
        #expect(comparator.compareVersion("17", toVersion: "16") == .orderedDescending)
        #expect(comparator.compareVersion("17", toVersion: "17") == .orderedSame)
        #expect(comparator.compareVersion("17", toVersion: "18") == .orderedAscending)
    }

    @Test @MainActor
    func scheduledNoticeDoesNotNavigateAndDismissalSurvivesRestart() throws {
        let suite = "DBHV-updater-notice-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: folder) }
        defaults.set(folder.appendingPathComponent("history").path, forKey: "historyDirectory")
        let logger = UpdateTestLogger()
        func model(_ build: String, _ updater: UpdateTestUpdater) -> AppModel {
            let manager = ChargeProtectionManager(defaults: defaults, logger: logger,
                                                  configurationDirectory: folder.appendingPathComponent("charge"),
                                                  statusURL: folder.appendingPathComponent("helper.json"))
            return AppModel(defaults: defaults, updater: updater, currentAppVersion: "1.2.1",
                            currentAppBuild: build, diagnosticLogger: logger, chargeProtection: manager)
        }
        let old = model("36", UpdateTestUpdater())
        old.stopChargeProtectionMonitoring()
        let mock = UpdateTestUpdater()
        let first = model("37", mock)
        defer { first.stopChargeProtectionMonitoring() }
        first.destination = .history
        first.startAutomaticUpdateChecks()
        #expect(mock.starts == 1)
        let next = AvailableAppUpdate(version: "1.2.1", build: "38")
        mock.scheduledResult?(next)
        #expect(first.availableAppUpdate == next)
        #expect(first.overviewAvailableAppUpdate == nil)
        #expect(first.destination == .history && first.activeSheet == nil && first.alertMessage == nil)
        first.dismissVersionUpdatePrompt()
        #expect(first.overviewAvailableAppUpdate == next)
        first.dismissAvailableAppUpdate()
        mock.scheduledResult?(next)
        #expect(first.availableAppUpdate == nil)

        let afterRestart = UpdateTestUpdater()
        let second = model("37", afterRestart)
        defer { second.stopChargeProtectionMonitoring() }
        second.startAutomaticUpdateChecks()
        afterRestart.scheduledResult?(next)
        #expect(second.overviewAvailableAppUpdate == nil)
        let later = AvailableAppUpdate(version: "1.2.1", build: "39")
        afterRestart.scheduledResult?(later)
        #expect(second.overviewAvailableAppUpdate == later)
        second.checkForUpdates()
        #expect(afterRestart.manualChecks == 1)
        second.setAutomaticallyChecksForUpdates(false)
        #expect(!afterRestart.automaticallyChecks && second.availableAppUpdate == nil)
        afterRestart.scheduledResult?(later)
        #expect(second.availableAppUpdate == nil)
        second.checkForUpdates()
        #expect(afterRestart.manualChecks == 2)
    }

    @Test(arguments: [AppLanguage.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese])
    func automaticUpdateReminderKeysAreTranslated(_ language: AppLanguage) {
        let keys = ["automaticallyCheckForUpdates", "availableUpdateTitle", "availableUpdateMessage", "viewAvailableUpdate"]
        for key in keys {
            #expect(L10n.interface12Tables[language]?[key]?.isEmpty == false)
        }
        #expect(L10n.format("availableUpdateTitle", language, "1.2.1").contains("1.2.1"))
    }

    @Test(arguments: [AppLanguage.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese])
    func requestedReleaseNotesHaveNoImprovementSection(_ language: AppLanguage) throws {
        let release = try #require(ChangelogRelease.localized(for: language).first)
        #expect(release.sections.map(\.kind) == [.feature, .fix])
        #expect(release.sections.flatMap(\.items).count == 8)
        #expect(release.sections.first?.items.prefix(3) == [
            L10n.text("release12Design", language), L10n.text("release12Display", language), L10n.text("release12Settings", language)
        ][...])
        #expect(L10n.text("release112Updater", language) != "release112Updater")
        #expect(release.sections.last?.items == [L10n.text("release112PauseFix", language), L10n.text("release12QuitFix", language)])
        if language == .simplifiedChinese {
            #expect(release.sections.flatMap(\.items).contains("系统校准或临时允许充满时，不再错误地显示充电保护失败。"))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_EXPORT_CHANGELOG"] != nil))
    func exportActualReleaseNotesForSignedAppcast() throws {
        let languages: [AppLanguage] = [.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese]
        let result = languages.map { language -> [String: Any] in
            let release = ChangelogRelease.localized(for: language)[0]
            return ["language": language.rawValue, "version": release.version,
                    "sections": release.sections.map { ["title": $0.kind.title(for: language), "items": $0.items] }]
        }
        let output = try #require(ProcessInfo.processInfo.environment["DBHV_EXPORT_CHANGELOG"])
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
    }
}

@MainActor
private final class UpdateTestUpdater: AutomaticallyCheckingForUpdates {
    var canCheckForUpdates = true
    var availabilityChanged: ((Bool) -> Void)?
    var scheduledResult: ((AvailableAppUpdate?) -> Void)?
    var automaticallyChecks = true
    var starts = 0
    var manualChecks = 0
    func start() throws { starts += 1 }
    func checkForUpdates() throws { manualChecks += 1 }
}

private struct UpdateTestLogger: DiagnosticLogging {
    func log(_ severity: DiagnosticSeverity, category: String, event: String, message: String) {}
}
