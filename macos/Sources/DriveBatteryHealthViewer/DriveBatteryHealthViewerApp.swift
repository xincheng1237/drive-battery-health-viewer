import AppKit
import SwiftUI

/// AppKit owns the application and menu lifecycles. SwiftUI continues to own
/// all visible content, but it can no longer replace the main menu during a
/// view update or while AppKit is tracking an open menu.
@main
enum DriveBatteryHealthViewerApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuLocalizer.install(model.language, model: model)
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopLiveHardwareMonitoring()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopLiveHardwareMonitoring()
    }

    private func showMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            model.startLiveHardwareMonitoring()
            return
        }

        let content = RootView()
            .environmentObject(model)
            .frame(minWidth: 720, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.delegate = self
        window.minSize = NSSize(width: 720, height: 560)
        window.title = model.t("overview")
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        let frameName = "DriveBatteryHealthViewer.MainWindow"
        if !window.setFrameUsingName(frameName) { window.center() }
        window.setFrameAutosaveName(frameName)
        window.makeKeyAndOrderFront(nil)
        mainWindow = window

        model.startLiveHardwareMonitoring()
        if model.currentSnapshot == nil { model.refresh() }
        NSApp.activate(ignoringOtherApps: true)
    }
}
