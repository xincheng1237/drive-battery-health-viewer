import AppKit
import Foundation
import QuartzCore
import Testing
@testable import DriveBatteryHealthViewer

@Suite("Production pill navigation and toolbar interaction", .serialized)
struct NativeWindowInteractionTests {
    @MainActor
    private func fixture() throws -> (MainWindowController, AppModel, UserDefaults, String) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DBHVNativeUI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "DBHVNativeUI.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: "language")
        defaults.set(directory.appendingPathComponent("history").path, forKey: "historyDirectory")
        let logger = DiagnosticLogger(directory: directory.appendingPathComponent("logs"))
        let manager = ChargeProtectionManager(defaults: defaults, logger: logger,
                                               isAppleSilicon: false,
                                               configurationDirectory: directory.appendingPathComponent("charge"))
        let model = AppModel(defaults: defaults, diagnosticLogger: logger, chargeProtection: manager)
        let controller = MainWindowController(model: model, persistsFrame: false)
        return (controller, model, defaults, suite)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_TOOLBAR_PREVIEW"] != nil))
    @MainActor func renderToolbarSelectionAndNativeButtonBezel() async throws {
        let (controller, model, defaults, suite) = try fixture()
        let window = try #require(controller.window)
        defer {
            window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring()
            defaults.removePersistentDomain(forName: suite)
        }
        let path = try #require(ProcessInfo.processInfo.environment["DBHV_TOOLBAR_PREVIEW"])
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.setFrame(NSRect(x: 50, y: 80, width: 720, height: 520), display: true)
        for dark in [false, true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for selected in [true, false] {
                model.hideSerials = selected
                try await Task.sleep(for: .milliseconds(200))
                let frame = try #require(window.contentView?.superview)
                // A visual-only fixture enables report controls without doing
                // a hardware scan. It does not exercise report availability.
                func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
                for button in descendants(frame).compactMap({ $0 as? NSButton }) {
                    if button.identifier?.rawValue.hasPrefix("DBHV.Toolbar.") == true { button.isEnabled = true }
                }
                let rect = NSRect(x: frame.bounds.maxX - 220, y: frame.bounds.maxY - 52, width: 220, height: 52)
                let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: rect))
                window.effectiveAppearance.performAsCurrentDrawingAppearance { frame.cacheDisplay(in: rect, to: bitmap) }
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("toolbar-\(dark ? "dark" : "light")-\(selected ? "on" : "off").png"))
            }
        }
    }

    @Test @MainActor
    func privacyToolbarToggleStillChangesAndRestoresSerialVisibility() async throws {
        let (controller, model, defaults, suite) = try fixture()
        let window = try #require(controller.window)
        defer {
            window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.showWindow(nil)
        try await Task.sleep(for: .milliseconds(100))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let frame = try #require(window.contentView?.superview)
        let button = try #require(descendants(frame).compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "DBHV.Toolbar.hideSerials"
        })
        let original = model.hideSerials
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.hideSerials != original)
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.hideSerials == original)
    }



    @Test @MainActor
    func threeVisibleDestinationsFitAllLanguagesAndWindowWidths() async throws {
        let (controller, model, defaults, suite) = try fixture()
        let window = try #require(controller.window)
        defer {
            window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.showWindow(nil)
        let toolbar = try #require(window.toolbar)
        let identity = toolbar.items
        for language in AppLanguage.allCases {
            model.language = language
            try await Task.sleep(for: .milliseconds(40))
            for width in [600.0, 680.0, 720.0, 900.0, 1280.0, 1728.0] {
                window.setFrame(NSRect(x: 50, y: 80, width: width, height: 650), display: true)
                window.contentView?.superview?.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
                let nav = controller.navigationHeader
                let navFrame = nav.convert(nav.bounds, to: nil)
                let actions = controller.actionFramesInWindow()
                #expect(actions.count == 5)
                for (key, rect) in actions {
                    #expect(abs(rect.width - 32) < 0.5 && abs(rect.height - 32) < 0.5,
                            "Actual toolbar frame for \(key) is \(rect.size), expected a square")
                }
                #expect(toolbar.visibleItems?.count == 2, "A control overflowed at \(language) / \(width)")
                #expect(navFrame.minX >= 70)
                if width >= 900 { #expect(abs(navFrame.midX - width / 2) < 1, "Navigation is not centered in a wide window") }
                #expect(window.titlebarSeparatorStyle == .none)
                #expect(!toolbar.showsBaselineSeparator)
                #expect(navFrame.maxX + 8 <= (actions.values.map(\.minX).min() ?? 0))
                for button in nav.destinationButtons {
                    let destination = SidebarDestination.mainCases[button.tag]
                    #expect(button.title == model.t(destination == .history ? "historyNavigation" : destination.rawValue))
                    if language == .simplifiedChinese && destination == .history { #expect(button.title == "历史") }
                    #expect(!button.visibleRect.isEmpty)
                    #expect(abs(button.bounds.height - 28) < 0.5)
                    #expect(abs(button.convert(button.bounds, to: nav).midY - nav.bounds.midY) < 0.5)
                    #expect(button.bounds.width >= button.intrinsicContentSize.width - 0.5)
                }
                let detail = controller.detailController.view
                let content = detail.convert(detail.bounds, to: nil)
                #expect(abs(content.minX) < 0.5)
                #expect(abs(content.width - width) < 0.5)
                #expect(content.maxY <= window.contentLayoutRect.maxY + 0.5)
                #expect(zip(toolbar.items, identity).allSatisfy { $0 === $1 })
            }
        }
    }

    @Test @MainActor
    func navigationFollowsResizeContinuouslyInBothDirections() async throws {
        let (controller, model, defaults, suite) = try fixture()
        let window = try #require(controller.window)
        defer {
            window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.showWindow(nil)
        let nav = controller.navigationHeader
        let widths = Array(stride(from: 900, through: 600, by: -4))
        var positions: [Int: CGFloat] = [:]
        // Include coarse steps like the opening frames of a fast window zoom.
        let fastWidths = [600, 616, 648, 712, 820, 900, 820, 712, 648, 616, 600]
        for (fixedRightEdge, sequence) in [(false, widths + widths.reversed()), (true, fastWidths)] {
            var previous: (width: Int, localX: CGFloat, screenX: CGFloat)?
            for width in sequence {
                let x = fixedRightEdge ? 950 - width : 50
                window.setFrame(NSRect(x: x, y: 80, width: width, height: 650), display: true)
                try await Task.sleep(for: .milliseconds(12))
                let frame = nav.convert(nav.bounds, to: nil)
                let screenX = window.convertToScreen(frame).minX
                #expect(nav.visibleRect.width >= nav.bounds.width - 0.5)
                if let previous {
                    let direction: CGFloat = width >= previous.width ? 1 : -1
                    let localTravel = (frame.minX - previous.localX) * direction
                    #expect(localTravel >= -0.5 && localTravel <= CGFloat(abs(width - previous.width)) + 0.5,
                            "Navigation outran the window edge at \(width)pt")
                    if fixedRightEdge {
                        #expect((screenX - previous.screenX) * direction <= 0.5,
                                "Navigation reversed on screen at \(width)pt")
                    }
                }
                if let old = positions[width] { #expect(abs(old - frame.minX) < 1) }
                positions[width] = frame.minX
                previous = (width, frame.minX, screenX)
            }
        }
        #expect(Set(positions.values.map { Int($0.rounded()) }).count > 20)
        #expect(abs((positions[900] ?? 0) + nav.bounds.width / 2 - 450) < 1)
        #expect(abs((positions[600] ?? 0) - (positions[604] ?? 0)) < 1)
    }

    @Test @MainActor
    func rapidNavigationKeepsGeometryAndSelectionAndKeyboardWorking() async throws {
        let (controller, model, defaults, suite) = try fixture()
        let window = try #require(controller.window)
        defer {
            window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.showWindow(nil)
        window.setFrame(NSRect(x: 50, y: 80, width: 720, height: 650), display: true)
        try await Task.sleep(for: .milliseconds(100))
        let reference = controller.actionFramesInWindow()
        let navigation = controller.navigationHeader
        let navFrame = navigation.convert(navigation.bounds, to: nil)
        for index in 0..<38 {
            let destination = index % 3
            navigation.destinationButtons[destination].performClick(nil)
            try await Task.sleep(for: .milliseconds(12))
            #expect(model.destination == SidebarDestination.mainCases[destination])
            #expect(navigation.destinationButtons.filter { $0.state == .on }.count == 1)
            #expect(navigation.destinationButtons[destination].state == .on)
            func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
            let chrome = try #require(window.contentView?.superview)
            let privacy = try #require(views(chrome).first { $0.identifier?.rawValue == "DBHV.Toolbar.hideSerials" })
            #expect(privacy.isHiddenOrHasHiddenAncestor == (destination != 0))
            #expect(controller.actionFramesInWindow() == reference)
            #expect(navigation.convert(navigation.bounds, to: nil) == navFrame)
        }
        for index in 0..<3 {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\(index + 1)",
                charactersIgnoringModifiers: "\(index + 1)", isARepeat: false, keyCode: 0))
            #expect(window.performKeyEquivalent(with: event))
            #expect(model.destination == SidebarDestination.mainCases[index])
        }
        let arrow = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 124))
        navigation.destinationButtons[2].keyDown(with: arrow)
        #expect(model.destination == .overview)
        #expect(window.firstResponder === navigation.destinationButtons[0])
        model.destination = .settings
        try await Task.sleep(for: .milliseconds(40))
        #expect(navigation.destinationButtons[2].state == .on)
        #expect(navigation.destinationButtons[2].accessibilityRole() == .radioButton)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let frame = try #require(window.contentView?.superview)
        #expect(descendants(frame).allSatisfy { !($0 is NSSplitView) })
        #expect(descendants(frame).allSatisfy { $0.identifier?.rawValue != "DBHV.SidebarDivider" })
        let menu = MainMenuLocalizer.makeMenuForTesting(language: .simplifiedChinese)
        func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items + menu.items.flatMap { $0.submenu.map(items) ?? [] } }
        #expect(items(menu).allSatisfy { $0.keyEquivalent != "s" || $0.keyEquivalentModifierMask != [.control, .command] })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_PILL_PREVIEW"] != nil))
    @MainActor func renderProductionPillNavigationAndScrolledPages() async throws {
        let (controller, model, defaults, suite) = try fixture()
        let window = try #require(controller.window)
        defer {
            window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring()
            defaults.removePersistentDomain(forName: suite)
        }
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DBHV_PILL_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        model.refreshWithoutSavingHistory()
        for _ in 0..<200 {
            if model.currentSnapshot != nil && !model.isScanning { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.currentSnapshot != nil)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for dark in [false, true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for width in [720.0, 1280.0] {
                window.setFrame(NSRect(x: 50, y: 80, width: width, height: 720), display: true)
                for phase in 0..<4 {
                    model.destination = phase < 2 ? .overview : SidebarDestination.mainCases[phase - 1]
                    try await Task.sleep(for: .milliseconds(180))
                    if phase == 1, let scroll = descendants(controller.detailController.view).compactMap({ $0 as? NSScrollView }).max(by: { $0.frame.width < $1.frame.width }), let document = scroll.documentView {
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.height / 2))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                    try await Task.sleep(for: .milliseconds(120))
                    let frame = try #require(window.contentView?.superview)
                    let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
                    window.effectiveAppearance.performAsCurrentDrawingAppearance { frame.cacheDisplay(in: frame.bounds, to: bitmap) }
                    if phase == 0 || phase == 3 {
                        let top = NSRect(x: 0, y: frame.bounds.maxY - 60, width: frame.bounds.width, height: 60)
                        let bar = try #require(frame.bitmapImageRepForCachingDisplay(in: top))
                        window.effectiveAppearance.performAsCurrentDrawingAppearance { frame.cacheDisplay(in: top, to: bar) }
                        try #require(bar.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("topbar-\(dark ? "dark" : "light")-\(Int(width))-\(phase).png"))
                    }
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("pill-\(dark ? "dark" : "light")-\(Int(width))-\(phase).png"))
                }
            }
        }
    }

    @Test @MainActor
    func selectionSlidesAndCanBeInterruptedWithoutLayoutChanges() async throws {
        let (controller, model, defaults, suite) = try fixture()
        let window = try #require(controller.window)
        defer {
            window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.setFrame(NSRect(x: 50, y: 80, width: 1280, height: 720), display: true)
        let navigation = controller.navigationHeader
        navigation.reduceMotion = { false }
        try await Task.sleep(for: .milliseconds(200))
        let fixed = controller.actionFramesInWindow()
        navigation.activate(index: 0, animated: false)
        let start = navigation.presentedSelectionFrame
        navigation.activate(index: 2, animated: true)
        #expect(navigation.hasSelectionAnimation)
        var positions: [CGFloat] = []
        for _ in 0..<32 {
            try await Task.sleep(for: .milliseconds(8))
            positions.append(navigation.presentedSelectionFrame.minX)
            #expect(controller.actionFramesInWindow() == fixed)
        }
        let endpoint = navigation.destinationButtons[2].convert(navigation.destinationButtons[2].bounds, to: navigation)
        #expect(Set(positions.map { Int($0.rounded()) }).count > 4, "No intermediate sliding frames sampled")
        #expect(positions.first! < endpoint.minX - 1)
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 + 0.5 })
        #expect(abs(navigation.presentedSelectionFrame.minX - endpoint.minX) < 0.5)
        #expect(start.minX < endpoint.minX)
        var rows: [[String: Double]] = []
        for index in Array(repeating: [0, 2, 1, 0, 2, 1, 0, 2, 0, 2, 0, 1], count: 5).flatMap({ $0 }) {
            let before = navigation.presentedSelectionFrame
            navigation.activate(index: index, animated: true)
            CATransaction.flush()
            let after = navigation.presentedSelectionFrame
            #expect(abs(before.minX - after.minX) < 8, "Interrupted selection teleported")
            #expect(controller.actionFramesInWindow() == fixed)
            rows.append(["from": before.minX, "after": after.minX, "destination": Double(index)])
            try await Task.sleep(for: .milliseconds(25))
        }
        try await Task.sleep(for: .milliseconds(250))
        let final = navigation.destinationButtons[1].convert(navigation.destinationButtons[1].bounds, to: navigation)
        #expect(abs(navigation.presentedSelectionFrame.minX - final.minX) < 0.5)
        #expect(navigation.destinationButtons.filter { $0.state == .on }.count == 1)
        navigation.reduceMotion = { true }
        navigation.activate(index: 2, animated: true)
        #expect(!navigation.hasSelectionAnimation)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        let reduced = navigation.destinationButtons[2].convert(navigation.destinationButtons[2].bounds, to: navigation)
        #expect(abs(navigation.presentedSelectionFrame.minX - reduced.minX) < 0.5)
        navigation.reduceMotion = { false }
        navigation.activate(index: 2, animated: false)
        #expect(!navigation.hasSelectionAnimation)
        #expect(model.destination == .settings)
        if let path = ProcessInfo.processInfo.environment["DBHV_PILL_PREVIEW"] {
            let folder = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["slideX": positions, "interruptions": rows], options: [.prettyPrinted]).write(to: folder.appendingPathComponent("motion-samples.json"))
        }
    }


    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_FULLSCREEN_PREVIEW"] != nil))
    @MainActor func nativeFullScreenCentersNavigationWithoutASeparator() async throws {
        let (controller, model, defaults, suite) = try fixture()
        let window = try #require(controller.window)
        let observer = FullScreenObserver()
        window.delegate = observer
        defer {
            window.close(); model.stopLiveHardwareMonitoring(); model.stopChargeProtectionMonitoring()
            defaults.removePersistentDomain(forName: suite)
        }
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.setFrame(NSRect(x: 50, y: 80, width: 600, height: 650), display: true)
        try await Task.sleep(for: .milliseconds(200))
        let nav = controller.navigationHeader
        let originalX = nav.convert(nav.bounds, to: nil).minX
        window.toggleFullScreen(nil)
        for _ in 0..<80 {
            if observer.entered { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(observer.entered, "Native full screen did not complete")
        if observer.entered {
            try await Task.sleep(for: .milliseconds(200))
            let rect = nav.convert(nav.bounds, to: nil)
            #expect(abs(rect.midX - window.frame.width / 2) < 1)
            #expect(window.titlebarSeparatorStyle == .none)
            let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DBHV_FULLSCREEN_PREVIEW"]))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let frame = try #require(window.contentView?.superview)
            let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("native-fullscreen.png"))
            try JSONSerialization.data(withJSONObject: ["entered": true, "windowWidth": window.frame.width, "navigationCenterX": rect.midX], options: [.prettyPrinted]).write(to: folder.appendingPathComponent("fullscreen.json"))
            window.toggleFullScreen(nil)
            for _ in 0..<80 {
                if observer.exited { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(observer.exited, "Native full screen did not exit")
            try await Task.sleep(for: .milliseconds(150))
            #expect(abs(window.frame.width - 600) < 1)
            #expect(abs(nav.convert(nav.bounds, to: nil).minX - originalX) < 1)
        }
    }

}

@MainActor private final class FullScreenObserver: NSObject, NSWindowDelegate {
    var entered = false
    var exited = false
    func windowDidEnterFullScreen(_ notification: Notification) { entered = true }
    func windowDidExitFullScreen(_ notification: Notification) { exited = true }
}
