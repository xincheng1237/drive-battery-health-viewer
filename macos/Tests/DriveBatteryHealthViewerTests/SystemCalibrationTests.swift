import AppKit
import Foundation
import SwiftUI
import ChargeProtectionCore
import Testing
@testable import DriveBatteryHealthViewer
@testable import DriveBatteryChargeLimitAgent

@Suite("System calibration recognition")
struct SystemCalibrationTests {
    func fixture(now: Date = Date()) -> (ChargeProtectionConfiguration, ChargeProtectionStatus) {
        var configuration = ChargeProtectionConfiguration(enabled: true, fixedLimit: .eighty)
        configuration.updatedAt = now.addingTimeInterval(-10)
        let status = ChargeProtectionStatus(
            helperVersion: "test", timestamp: now, installed: true, enabled: true,
            fixedLimit: .eighty, temporaryFullCharge: false,
            configurationUpdatedAt: configuration.updatedAt,
            holding: false, adapterConnected: true, batteryPercentage: 80,
            controlMethod: .powerUIOptimized80,
            systemChargeOverride: .inactive, systemCalibration: .calibrating
        )
        return (configuration, status)
    }

    @Test func calibrationHasItsOwnReasonAndIcon() {
        let (configuration, status) = fixture()
        #expect(resolvedSystemCalibration(configuration: configuration, status: status) == .calibrating)
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .systemCalibration)
        #expect(shouldPresentCalibrationStatusItem(configuration: configuration, status: status))
        #expect(!shouldPresentChargeLimitStatusItem(configuration: configuration, status: status))
        #expect(!configuration.temporaryFullCharge)
    }

    @Test(arguments: [46, 80, 91, 100])
    func percentageCannotEstablishOrEndCalibration(_ percentage: Int) {
        var (configuration, status) = fixture()
        status.batteryPercentage = percentage
        #expect(resolvedSystemCalibration(configuration: configuration, status: status) == .calibrating)
        status.systemCalibration = nil
        #expect(resolvedSystemCalibration(configuration: configuration, status: status) == nil)
        #expect(!shouldPresentCalibrationStatusItem(configuration: configuration, status: status))
    }

    @Test func explicitPauseWinsOverOldHoldingAndFullChargeClaims() {
        var (configuration, status) = fixture()
        status.holding = true
        status.systemChargeOverride = .chargingToFull
        #expect(!shouldPresentChargeLimitStatusItem(configuration: configuration, status: status))
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .systemCalibration)
    }

    @Test func unknownReadRetainsPauseUntilConfirmedButNeverClaimsCompletion() {
        var tracker = SystemCalibrationTracker()
        #expect(tracker.observe(limitSuspended: nil) == nil)
        #expect(tracker.observe(limitSuspended: true) == .calibrating)
        #expect(tracker.observe(limitSuspended: nil) == .awaitingConfirmation)
        #expect(tracker.state?.defersChargeControl == true)
        #expect(tracker.observe(limitSuspended: false) == .inactive)
        var (configuration, status) = fixture()
        status.systemCalibration = tracker.state
        #expect(!shouldPresentCalibrationStatusItem(configuration: configuration, status: status))
        #expect(!shouldPresentChargeLimitStatusItem(configuration: configuration, status: status))
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .protectionActive)
    }

    @Test func waitingStateIsVisibleAndKeepsTheConfiguredLimit() {
        var (configuration, status) = fixture()
        status.systemCalibration = .awaitingConfirmation
        status.adapterConnected = false
        #expect(shouldPresentCalibrationStatusItem(configuration: configuration, status: status))
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .systemCalibrationAwaitingConfirmation)
        #expect(configuration.fixedLimit == .eighty)
        configuration.showMenuBarStatus = false
        #expect(!shouldPresentCalibrationStatusItem(configuration: configuration, status: status))
    }

    @Test func staleOrMismatchedReportsCannotBecomeCalibration() {
        let now = Date()
        var (configuration, status) = fixture(now: now)
        status.timestamp = now.addingTimeInterval(-21)
        #expect(!shouldPresentCalibrationStatusItem(configuration: configuration, status: status, now: now))
        status.timestamp = now.addingTimeInterval(2)
        #expect(resolvedSystemCalibration(configuration: configuration, status: status, now: now) == nil)
        status.timestamp = now
        status.configurationUpdatedAt = configuration.updatedAt.addingTimeInterval(-5)
        #expect(resolvedSystemCalibration(configuration: configuration, status: status, now: now) == nil)
        status.configurationUpdatedAt = configuration.updatedAt
        configuration.enabled = false
        #expect(resolvedSystemCalibration(configuration: configuration, status: status, now: now) == nil)
    }

    @Test func unrelatedFailuresAreNotRelabeledAsCalibration() {
        var (configuration, status) = fixture()
        status.systemCalibration = nil
        status.lastError = "Native PowerUI 80% engagement failed"
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .attentionRequired)
        status.systemCalibration = .calibrating
        #expect(ChargeLimitAgentPresentationState.resolve(configuration: configuration, status: status) == .attentionRequired)
    }

    @Test func oldStatusRemainsDecodableAndNewReasonRoundTrips() throws {
        let (_, status) = fixture()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoded = try encoder.encode(status)
        #expect(try decoder.decode(ChargeProtectionStatus.self, from: encoded).systemCalibration == .calibrating)
        var old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "systemCalibration")
        old.removeValue(forKey: "systemChargeOverride")
        #expect(try decoder.decode(ChargeProtectionStatus.self, from: JSONSerialization.data(withJSONObject: old)).systemCalibration == nil)
    }

    @Test @MainActor func loopGlyphKeepsNativeGeometryAndDiffersFromHolding() throws {
        let image = ChargeLimitAgentStatusItemController.calibratingImage()
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 24, height: 16))
        let holding = try #require(ChargeLimitAgentStatusItemController.reachedLimitImage())
        #expect(image.tiffRepresentation != holding.tiffRepresentation)
    }

    @Test(arguments: [AppLanguage.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese])
    func calibrationCopyAndReleaseNotesAreLocalized(_ language: AppLanguage) {
        let message = L10n.format("systemCalibrationInProgress", language, 80)
        #expect(message.contains("80%") && !message.contains("%d"))
        for key in ["systemCalibrationAwaitingConfirmation", "release112Calibration", "release112SystemFull", "release112PauseFix"] {
            #expect(L10n.text(key, language) != key)
        }
        let release = ChangelogRelease.localized(for: language)
        #expect(release.first?.version == "1.2")
        #expect(release.contains { $0.version == "1.1" })
    }

    @Test(arguments: [AgentLanguage.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese])
    func agentCalibrationCopyIsLocalized(_ language: AgentLanguage) {
        for key in ["calibrationActive", "calibrationPending", "calibrationDetail", "calibrationPendingDetail"] {
            #expect(AgentL10n.text(key, language: language) != key)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_RENDER_PREVIEWS"] != nil))
    @MainActor func renderActualNoticeAndGlyphPreviews() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DBHV_RENDER_PREVIEWS"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let languages: [AppLanguage] = [.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese]
        for (index, language) in languages.enumerated() {
            for dark in [false, true] {
                for state in 0..<3 {
                    let notice = SystemChargingPauseNotice(
                        calibration: state == 0 ? .calibrating : state == 1 ? .awaitingConfirmation : nil,
                        override: state == 2 ? .chargingToFull : nil,
                        limit: 80, language: language
                    )
                    let renderer = ImageRenderer(content: notice
                        .frame(width: 298, alignment: .leading).padding(16)
                        .background(dark ? Color(nsColor: .darkGray) : .white)
                        .environment(\.colorScheme, dark ? .dark : .light))
                    renderer.scale = 2
                    let image = try #require(renderer.cgImage)
                    #expect(image.width == 660)
                    #expect(image.height > 40 && image.height < 360)
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    let data = try #require(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("notice-\(index)-\(dark ? "dark" : "light")-\(state).png"))
                }
            }
        }
        let glyph = ChargeLimitAgentStatusItemController.calibratingImage()
        let tiff = try #require(glyph.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("calibration-glyph.png"))
        let enlarged = ImageRenderer(content: Image(nsImage: glyph).renderingMode(.original)
            .resizable().frame(width: 240, height: 160).padding(24).background(.white))
        enlarged.scale = 2
        let enlargedImage = try #require(enlarged.cgImage)
        let enlargedPNG = try #require(NSBitmapImageRep(cgImage: enlargedImage).representation(using: .png, properties: [:]))
        try enlargedPNG.write(to: directory.appendingPathComponent("calibration-glyph-preview.png"))
    }
}
