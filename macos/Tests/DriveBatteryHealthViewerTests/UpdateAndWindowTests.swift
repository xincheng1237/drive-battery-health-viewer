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
        #expect(info["CFBundleShortVersionString"] as? String == "1.1.2")
        #expect(info["CFBundleVersion"] as? String == "17")
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SUSignedFeedFailureExpirationInterval"] as? Int == 0)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == false)
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
        let descriptions = try document.nodes(forXPath: "/rss/channel/item/description")
        #expect(descriptions.count == 7)
        for language in ["en", "zh-Hans", "ru", "fr", "de", "ko", "ja"] {
            #expect(descriptions.contains { ($0 as? XMLElement)?.attribute(forName: "xml:lang")?.stringValue == language })
        }
        #expect(try document.nodes(forXPath: "/rss/channel/item/sparkle:version").first?.stringValue == "17")
        let enclosure = try #require(document.nodes(forXPath: "/rss/channel/item/enclosure").first as? XMLElement)
        #expect(enclosure.attribute(forName: "url")?.stringValue == "https://github.com/xincheng1237/drive-battery-health-viewer/releases/download/v1.1.2/DriveBatteryHealthViewer_v1.1.2_build17_macOS_Universal.zip")
    }

    @Test @MainActor func samePublicVersionUsesIncreasingBuildNumbers() {
        let comparator = SUStandardVersionComparator.default
        #expect(comparator.compareVersion("17", toVersion: "16") == .orderedDescending)
        #expect(comparator.compareVersion("17", toVersion: "17") == .orderedSame)
        #expect(comparator.compareVersion("17", toVersion: "18") == .orderedAscending)
    }

    @Test(arguments: [AppLanguage.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese])
    func requestedReleaseNotesHaveNoImprovementSection(_ language: AppLanguage) throws {
        let release = try #require(ChangelogRelease.localized(for: language).first)
        #expect(release.sections.map(\.kind) == [.feature, .fix])
        #expect(release.sections.flatMap(\.items).count == 5)
        for key in ["release112Updater", "release112Toolbar"] { #expect(L10n.text(key, language) != key) }
        if language == .simplifiedChinese {
            #expect(release.sections.flatMap(\.items).contains("系统校准或临时允许充满时，不再错误地显示充电保护失败。"))
        }
    }

    @Test @MainActor func windowContentRemainsBelowNativeChromeAtNarrowAndWideSizes() {
        let controller = NSHostingController(rootView:
            ScrollView { VStack { ForEach(0..<80) { Text("Hardware section \($0)").frame(height: 50) } } }
                .navigationTitle("概览").toolbar { Button("Refresh") {} }
                .toolbarBackground(.visible, for: .windowToolbar)
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                              styleMask: MainWindowLayout.styleMask, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        MainWindowLayout.configure(window)
        for width in [720.0, 900.0, 1280.0] {
            window.setContentSize(NSSize(width: width, height: 600))
            window.contentView?.layoutSubtreeIfNeeded()
            #expect(!window.styleMask.contains(.fullSizeContentView))
            #expect(!window.titlebarAppearsTransparent)
            #expect(window.contentLayoutRect.height > 500)
            #expect(window.contentLayoutRect.maxY < window.frame.height)
        }
        window.close()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_NATIVE_WINDOW_QA"] != nil))
    @MainActor func renderActualRootWindowAtNarrowWidthAndAfterScrolling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DBHVWindowQA-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "DBHVWindowQA.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: "language")
        defaults.set(root.appendingPathComponent("history").path, forKey: "historyDirectory")
        let logger = DiagnosticLogger(directory: root.appendingPathComponent("logs"))
        let manager = ChargeProtectionManager(defaults: defaults, logger: logger, isAppleSilicon: false,
                                               configurationDirectory: root.appendingPathComponent("charge"))
        let model = AppModel(defaults: defaults, diagnosticLogger: logger, chargeProtection: manager)
        let host = NSHostingController(rootView: RootView().environmentObject(model)
            .frame(minWidth: 720, minHeight: 560))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                              styleMask: MainWindowLayout.styleMask, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.title = "概览"
        MainWindowLayout.configure(window)
        window.makeKeyAndOrderFront(nil)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring() }
        model.refreshForColdLaunch()
        for _ in 0..<200 {
            if model.currentSnapshot != nil && !model.isScanning { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.currentSnapshot != nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(!window.titlebarAppearsTransparent)
        let output = try #require(ProcessInfo.processInfo.environment["DBHV_NATIVE_WINDOW_QA"])
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let content = try #require(window.contentView)
        let scroll = try #require(descendants(content).compactMap { $0 as? NSScrollView }.max { $0.frame.width < $1.frame.width })
        for step in 0..<2 {
            if step == 1, let document = scroll.documentView {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.height / 2))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            try await Task.sleep(for: .milliseconds(300))
            window.displayIfNeeded()
            #expect(!window.styleMask.contains(.fullSizeContentView))
            let frame = content.convert(content.bounds, to: nil)
            #expect(frame.maxY <= window.contentLayoutRect.maxY + 1)
            let chrome = try #require(content.superview)
            let rep = try #require(chrome.bitmapImageRepForCachingDisplay(in: chrome.bounds))
            chrome.cacheDisplay(in: chrome.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("actual-root-\(step).png"))
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
