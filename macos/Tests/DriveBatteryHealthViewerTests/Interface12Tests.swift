import AppKit
import SwiftUI
import Testing
@testable import DriveBatteryHealthViewer

@Suite("1.2 display sizes and settings", .serialized)
struct Interface12Tests {
    @MainActor private func fixture() async throws -> (MainWindowController, AppModel, UserDefaults, String, Update12Stub) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DBHV12-\(UUID())")
        let suite = "DBHV12.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("zh-Hans", forKey: "language")
        defaults.set(folder.appendingPathComponent("history").path, forKey: "historyDirectory")
        let logger = DiagnosticLogger(directory: folder.appendingPathComponent("logs"))
        let manager = ChargeProtectionManager(defaults: defaults, logger: logger, isAppleSilicon: false,
                                               configurationDirectory: folder.appendingPathComponent("charge"))
        let updater = Update12Stub()
        let model = AppModel(defaults: defaults, scanner: HardwareScanner(runner: Interface12Runner(), smartctlPaths: ["/usr/bin/true"]),
                             updater: updater, currentAppVersion: "1.2", currentAppBuild: "35",
                             diagnosticLogger: logger, chargeProtection: manager)
        model.refresh()
        for _ in 0..<100 {
            if !model.isScanning && model.currentSnapshot != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.currentSnapshot?.drives.count == 1)
        #expect(model.currentSnapshot?.batteries.count == 1)
        if var snapshot = model.currentSnapshot {
            for offset in [1, 2] {
                snapshot.id = UUID()
                snapshot.generatedAt = snapshot.generatedAt.addingTimeInterval(-Double(offset) * 3600)
                snapshot.batteries[0].currentCapacityPercent = 80 - offset * 5
                _ = try HistoryStore(directory: model.historyDirectory).save(snapshot: snapshot, source: .refresh, hideSerials: true)
            }
            model.loadHistory()
        }
        let controller = MainWindowController(model: model, persistsFrame: false)
        return (controller, model, defaults, suite, updater)
    }
    @MainActor private func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }

    @Test @MainActor func displaySizePersistsWithoutChangingReportReadingSize() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        defer { controller.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        #expect(model.displaySize == .standard)
        model.reportTextSize = 17
        for size in DisplaySize.allCases {
            model.displaySize = size
            #expect(defaults.string(forKey: "displaySize") == size.rawValue)
            #expect(model.reportTextSize == 17)
        }
        let manager = ChargeProtectionManager(defaults: defaults, isAppleSilicon: false,
            configurationDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("DBHV12-reopen-\(UUID())"))
        let reopened = AppModel(defaults: defaults, chargeProtection: manager)
        defer { reopened.stopLiveHardwareMonitoring(); reopened.stopChargeProtectionMonitoring() }
        #expect(reopened.displaySize == .extraLarge)
        #expect(reopened.reportTextSize == 17)
        #expect(SidebarDestination.mainCases == [.overview, .history, .settings])
        for language in AppLanguage.allCases {
            #expect(ChangelogRelease.localized(for: language).first?.version == "1.2.1")
            #expect(!ChangelogRelease.localized(for: language).contains { $0.version == "1.1.2" })
            for size in DisplaySize.allCases { #expect(L10n.text(size.labelKey, language) != size.labelKey) }
        }
    }

    @Test @MainActor func informationPanelsAndReportReadingPreferencesStayIndependent() async throws {
        let (controller, model, defaults, suite, updater) = try await fixture()
        let window = try #require(controller.window)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.setFrame(NSRect(x: 40, y: 60, width: 900, height: 820), display: true)
        model.destination = .settings
        try await Task.sleep(for: .milliseconds(250))
        window.displayIfNeeded()
        model.checkForUpdates()
        try await Task.sleep(for: .milliseconds(80))
        #expect(updater.requests == 1)
        #expect(model.isCheckingForUpdates)
        updater.finish()
        #expect(!model.isCheckingForUpdates)
        model.showsAbout = true
        try await Task.sleep(for: .milliseconds(180))
        #expect(model.showsAbout)
        #expect(window.attachedSheet != nil)
        model.showsChangelog = false
        #expect(model.showsAbout, "A stale dismissal must not close a different panel")
        model.showsAbout = false
        try await Task.sleep(for: .milliseconds(250))
        model.showsChangelog = true
        try await Task.sleep(for: .milliseconds(180))
        #expect(model.showsChangelog)
        #expect(window.attachedSheet != nil)
        model.showsChangelog = false
        try await Task.sleep(for: .milliseconds(250))
        model.destination = .history
        try await Task.sleep(for: .milliseconds(150))
        let original = model.reportTextSize
        model.increaseReportTextSize()
        try await Task.sleep(for: .milliseconds(40))
        #expect(model.reportTextSize == original + 1)
        model.decreaseReportTextSize()
        try await Task.sleep(for: .milliseconds(40))
        #expect(model.reportTextSize == original)
        model.resetReportTextSize()
        #expect(model.reportTextSize == 13)
        model.displaySize = .extraLarge
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.reportTextSize == 13)
    }

    @Test @MainActor func rapidReportSelectionKeepsLatestRecordAndReaderControlsStable() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        let window = try #require(controller.window)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        controller.showWindow(nil)
        window.setFrame(NSRect(x: 40, y: 60, width: 720, height: 680), display: true)
        model.destination = .history
        model.displaySize = .extraLarge
        model.reportTextSize = 17
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.history.count == 3)
        let navigation = controller.navigationHeader.convert(controller.navigationHeader.bounds, to: nil)
        for index in 0..<60 {
            let record = model.history[index % model.history.count]
            model.selectHistoryReport(record.id, animated: true)
            try await Task.sleep(for: .milliseconds(20))
            #expect(model.selectedHistory?.id == record.id)
            #expect(model.reportTextSize == 17)
            #expect(controller.navigationHeader.convert(controller.navigationHeader.bounds, to: nil) == navigation)
        }
        model.selectHistoryReport(model.history[1].id, animated: false)
        #expect(model.selectedHistory?.id == model.history[1].id)
        let rendered = ReportRenderer.render(snapshot: try #require(model.selectedHistory?.snapshot), language: model.language, hideSerials: true)
        #expect(rendered.contains(model.history[1].snapshot.generatedAt.formattedReportDate()))
    }

    @Test @MainActor func upgradePromptChangelogKeepsOverviewAfterDismissal() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        let window = try #require(controller.window)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        controller.showWindow(nil)
        model.destination = .overview
        model.presentChangelogFromVersionUpdatePrompt()
        #expect(model.destination == .overview)
        #expect(!model.showsVersionUpdatePrompt)
        #expect(model.activeSheet == .changelog)
        try await Task.sleep(for: .milliseconds(250))
        #expect(window.attachedSheet != nil)
        model.showsChangelog = false
        try await Task.sleep(for: .milliseconds(250))
        #expect(window.attachedSheet == nil)
        #expect(model.destination == .overview)
        #expect(!model.showsVersionUpdatePrompt)
    }

    @Test @MainActor func informationalSheetsAllowTerminationWithoutChangingExportPolicy() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        let window = try #require(controller.window)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        controller.showWindow(nil)
        for sheet in [AppSheet.changelog, .about, .report, .diagnosticExport, .changelog] {
            model.activeSheet = sheet
            try await Task.sleep(for: .milliseconds(200))
            let presented = try #require(window.attachedSheet)
            #expect(presented.preventsApplicationTerminationWhenModal == (sheet == .diagnosticExport))
            model.activeSheet = nil
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    @Test @MainActor func viewMenuNavigatesAndKeepsDisplaySizeChecksInSync() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        defer { controller.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        MainMenuLocalizer.install(model.language, model: model)
        let menu = MainMenuLocalizer.makeMenuForTesting(language: .simplifiedChinese)
        let view = try #require(menu.items[2].submenu)
        for (index, destination) in SidebarDestination.mainCases.enumerated() {
            let item = view.items[index]
            #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
            #expect(model.destination == destination)
            #expect((item.target as? NSMenuItemValidation)?.validateMenuItem(item) == true)
            #expect(item.state == .on)
        }
        let sizes = try #require(view.items.first(where: { $0.submenu != nil })?.submenu)
        let identities = sizes.items.map(ObjectIdentifier.init)
        for (index, size) in DisplaySize.allCases.enumerated() {
            let item = sizes.items[index]
            #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
            #expect(model.displaySize == size)
            for (candidateIndex, candidate) in sizes.items.enumerated() {
                #expect((candidate.target as? NSMenuItemValidation)?.validateMenuItem(candidate) == true)
                #expect(candidate.state == (candidateIndex == index ? .on : .off))
            }
        }
        for language in AppLanguage.allCases {
            MainMenuLocalizer.apply(to: menu, language: language)
            #expect(sizes.items.map(ObjectIdentifier.init) == identities)
            #expect(sizes.items.map(\.title) == DisplaySize.allCases.map { L10n.text($0.labelKey, language) })
        }
        model.displaySize = .standard
        let standard = sizes.items[1]
        #expect((standard.target as? NSMenuItemValidation)?.validateMenuItem(standard) == true)
        #expect(standard.state == .on, "Settings changes must also update the menu checkmark")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_RELEASE_SCREENSHOTS"] != nil))
    @MainActor func exportReleaseScreenshotsInBothReadmeLanguages() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        let window = try #require(controller.window)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DBHV_RELEASE_SCREENSHOTS"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        window.appearance = NSAppearance(named: .aqua)
        model.displaySize = .standard
        model.dismissVersionUpdatePrompt()
        for language in [AppLanguage.simplifiedChinese, .english] {
            model.language = language
            for destination in SidebarDestination.mainCases {
                model.destination = destination
                window.setFrame(NSRect(x: 40, y: 60, width: destination == .settings ? 900 : 1280,
                                       height: 780), display: true)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(for: .milliseconds(250))
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                controller.navigationHeader.displayIfNeeded()
                let frame = try #require(window.contentView?.superview)
                let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
                window.effectiveAppearance.performAsCurrentDrawingAppearance { frame.cacheDisplay(in: frame.bounds, to: bitmap) }
                let name = "macos-\(destination.rawValue)-\(language == .english ? "en" : "zh").png"
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name))
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_CHANGELOG_PREVIEW"] != nil))
    @MainActor func renderChangelogEdgesAtStartMiddleAndEnd() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        let window = try #require(controller.window)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DBHV_CHANGELOG_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        controller.showWindow(nil)
        window.setFrame(NSRect(x: 40, y: 60, width: 1100, height: 800), display: true)
        model.destination = .settings
        for dark in [false, true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for size in [DisplaySize.standard, .extraLarge] {
                model.displaySize = size
                model.activeSheet = .changelog
                try await Task.sleep(for: .milliseconds(250))
                let sheet = try #require(window.attachedSheet)
                #expect(!sheet.preventsApplicationTerminationWhenModal)
                let content = try #require(sheet.contentView)
                let scroller = try #require(views(content).compactMap { $0 as? NSScrollView }.first)
                let document = try #require(scroller.documentView)
                let clip = scroller.contentView
                var previousOrigin: CGFloat?
                for fraction in [0.0, 0.47, 1.0] {
                    let maxOffset = max(0, document.bounds.height - clip.bounds.height)
                    let offset = document.isFlipped ? fraction * maxOffset : (1 - fraction) * maxOffset
                    clip.scroll(to: NSPoint(x: 0, y: offset))
                    scroller.reflectScrolledClipView(clip)
                    try await Task.sleep(for: .milliseconds(120))
                    #expect(clip.bounds.origin.y >= -1)
                    if let previousOrigin { #expect(abs(clip.bounds.origin.y - previousOrigin) > 1) }
                    previousOrigin = clip.bounds.origin.y
                    sheet.displayIfNeeded()
                    let frame = try #require(sheet.contentView?.superview)
                    let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
                    sheet.effectiveAppearance.performAsCurrentDrawingAppearance { frame.cacheDisplay(in: frame.bounds, to: bitmap) }
                    let name = "\(dark ? "dark" : "light")-\(size.rawValue)-\(Int(fraction * 100)).png"
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name))
                }
                model.activeSheet = nil
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_12_PREVIEW"] != nil))
    @MainActor func renderHistoryTransitionFrames() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        let window = try #require(controller.window)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DBHV_12_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        controller.showWindow(nil)
        window.setFrame(NSRect(x: 40, y: 60, width: 1100, height: 720), display: true)
        model.destination = .history
        try await Task.sleep(for: .milliseconds(250))
        let first = try #require(model.history.first)
        let last = try #require(model.history.last)
        model.selectHistoryReport(first.id, animated: false)
        try await Task.sleep(for: .milliseconds(80))
        model.selectHistoryReport(last.id, animated: true)
        var previous = 0
        for elapsed in [0, 33, 67, 100, 150, 220] {
            if elapsed > previous { try await Task.sleep(for: .milliseconds(elapsed - previous)) }
            previous = elapsed
            window.displayIfNeeded()
            let frame = try #require(window.contentView?.superview)
            let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("history-motion-\(elapsed)ms.png"))
            #expect(model.selectedHistory?.id == last.id)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_12_PREVIEW"] != nil))
    @MainActor func renderAllSizesAndPagesWithSimulatedDevices() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        let window = try #require(controller.window)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DBHV_12_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        for dark in [false, true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for width in [720.0, 1280.0] {
                window.setFrame(NSRect(x: 40, y: 60, width: width, height: 780), display: true)
                for size in DisplaySize.allCases {
                    model.displaySize = size
                    for destination in SidebarDestination.mainCases {
                        model.destination = destination
                        try await Task.sleep(for: .milliseconds(150))
                        window.contentView?.layoutSubtreeIfNeeded()
                        window.displayIfNeeded()
                        controller.navigationHeader.needsDisplay = true
                        controller.navigationHeader.displayIfNeeded()
                        try await Task.sleep(for: .milliseconds(30))
                        #expect(!controller.navigationHeader.visibleRect.isEmpty)
                        let detail = controller.detailController.view
                        #expect(abs(detail.frame.width - width) < 1)
                        #expect(controller.navigationHeader.destinationButtons.count == 3)
                        let frame = try #require(window.contentView?.superview)
                        let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
                        window.effectiveAppearance.performAsCurrentDrawingAppearance { frame.cacheDisplay(in: frame.bounds, to: bitmap) }
                        let name = "\(dark ? "dark" : "light")-\(Int(width))-\(size.rawValue)-\(destination.rawValue).png"
                        try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name))
                    }
                }
            }
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_12_PREVIEW"] != nil))
    @MainActor func renderLongLanguagesAndInformationPanels() async throws {
        let (controller, model, defaults, suite, _) = try await fixture()
        let window = try #require(controller.window)
        defer { window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring(); defaults.removePersistentDomain(forName: suite) }
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DBHV_12_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        controller.showWindow(nil); window.makeKeyAndOrderFront(nil)
        window.setFrame(NSRect(x: 40, y: 60, width: 720, height: 780), display: true)
        func capture(_ target: NSWindow, name: String) throws {
            let frame = try #require(target.contentView?.superview)
            let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
            target.effectiveAppearance.performAsCurrentDrawingAppearance { frame.cacheDisplay(in: frame.bounds, to: bitmap) }
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
        }
        model.displaySize = .extraLarge
        for language in [AppLanguage.russian, .german] {
            model.language = language
            for destination in SidebarDestination.mainCases {
                model.destination = destination
                try await Task.sleep(for: .milliseconds(250))
                window.displayIfNeeded()
                try capture(window, name: "long-\(language.rawValue)-\(destination.rawValue)")
            }
        }
        model.language = .simplifiedChinese; model.destination = .settings
        for size in [DisplaySize.standard, .extraLarge] {
            model.displaySize = size
            for sheet in [AppSheet.about, .changelog] {
                model.activeSheet = sheet
                try await Task.sleep(for: .milliseconds(250))
                try capture(try #require(window.attachedSheet), name: "sheet-\(size.rawValue)-\(sheet.rawValue)")
                model.activeSheet = nil
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }

}

@MainActor private final class Update12Stub: ApplicationUpdating {
    var canCheckForUpdates = true
    var availabilityChanged: ((Bool) -> Void)?
    var requests = 0
    func checkForUpdates() throws { requests += 1; canCheckForUpdates = false; availabilityChanged?(false) }
    func finish() { canCheckForUpdates = true; availabilityChanged?(true) }
}

/// Entirely simulated transport. No hardware commands or charge control run.
private struct Interface12Runner: CommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        var object: Any = [:]
        var isJSON = false
        if executable.hasSuffix("diskutil"), arguments.first == "list" {
            object = ["AllDisksAndPartitions": [["DeviceIdentifier": "disk900", "Size": 1_000_000_000_000 as UInt64]]]
        } else if executable.hasSuffix("diskutil") {
            object = ["DeviceIdentifier": "disk900", "Whole": true, "VirtualOrPhysical": "Physical", "MediaName": "APPLE SSD AP1024R", "TotalSize": 1_000_000_000_000 as UInt64, "BusProtocol": "USB", "SMARTStatus": "Verified", "SolidState": true, "Internal": false]
        } else if executable.hasSuffix("ioreg") {
            if arguments.contains("AppleSmartBattery") {
                object = [["DeviceName": "bq40z651", "BatterySerialNumber": "SIMULATED-BATTERY", "DesignCapacity": 6075, "AppleRawMaxCapacity": 4751, "CurrentCapacity": 80, "CycleCount": 472, "IsCharging": false, "ExternalConnected": true, "Voltage": 12060, "Temperature": 3032, "BatteryData": ["Chemistry": "Li-ion", "Manufacturer": "ATL"]]]
            } else { object = [] }
        } else if executable.hasSuffix("system_profiler") {
            isJSON = true
            object = arguments.contains("SPPowerDataType") ? ["SPPowerDataType": [["sppower_battery_health_info": ["sppower_battery_health_maximum_capacity": "80%"]]]] : [:]
        } else if executable == "/usr/bin/true" {
            isJSON = true
            object = ["model_name": "APPLE SSD AP1024R", "serial_number": "SIMULATED-SSD", "firmware_version": "591.40.3", "smart_status": ["passed": true], "nvme_smart_health_information_log": ["percentage_used": 5, "temperature": 32, "power_on_hours": 2570, "power_cycles": 314, "data_units_read": 120000000, "data_units_written": 130000000, "unsafe_shutdowns": 29, "media_errors": 0, "num_err_log_entries": 0]]
        }
        let data = try isJSON ? JSONSerialization.data(withJSONObject: object) : PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        return CommandOutput(data: data, errorText: "", status: 0)
    }
}

