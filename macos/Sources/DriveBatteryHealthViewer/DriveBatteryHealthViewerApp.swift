import AppKit
import CNVMeSMART
import SwiftUI

/// AppKit owns the application and menu lifecycles. SwiftUI continues to own
/// all visible content, but it can no longer replace the main menu during a
/// view update or while AppKit is tracking an open menu.
@main
enum DriveBatteryHealthViewerApplication {
    @MainActor private static var retainedDelegate: ApplicationDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        retainedDelegate = delegate
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        // Construct the stable, correctly localized menu before AppKit enters
        // its launch run loop. Otherwise AppKit can retain the English bundle
        // name on a clean first launch before system language is applied.
        delegate.prepareMainMenuForLaunch()
        application.run()
        application.delegate = nil
        retainedDelegate = nil
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var mainWindowController: NSWindowController?
    private var isCreatingMainWindow = false
    private var isClosingMainWindow = false

    func prepareMainMenuForLaunch() {
        MainMenuLocalizer.install(model.language, model: model)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // AppKit may normalize application-menu metadata while finishing its
        // launch. Reapply titles in place once; the hierarchy never changes.
        MainMenuLocalizer.apply(model.language)
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // The reopen callback is delivered while AppKit is processing an
        // Apple event. Defer window construction until that event has
        // unwound, so closing and reopening cannot mutate the same window
        // hierarchy reentrantly.
        if !flag {
            DispatchQueue.main.async { [weak self] in
                self?.showMainWindow()
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        model.stopLiveHardwareMonitoring()
        DBHVResetNVMeSMARTInterfaces()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              mainWindowController?.window === closingWindow else { return }
        isClosingMainWindow = true
        model.stopLiveHardwareMonitoring()
        let closingIdentifier = ObjectIdentifier(closingWindow)
        // NSWindowDelegate receives this callback before AppKit has finished
        // closing the window. Keep the controller alive through that cycle,
        // then discard the closed hierarchy so a future reopen starts clean.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let currentWindow = self.mainWindowController?.window,
                  ObjectIdentifier(currentWindow) == closingIdentifier else {
                self?.isClosingMainWindow = false
                return
            }
            // `windowWillClose` is only sent once AppKit has committed to the
            // close. Do not depend on `isVisible` becoming false in exactly the
            // next run-loop cycle; close animations and sheets may delay it.
            currentWindow.delegate = nil
            self.mainWindowController = nil
            self.isClosingMainWindow = false
        }
    }

    @objc private func systemWillSleep() {
        model.stopLiveHardwareMonitoring()
        DBHVResetNVMeSMARTInterfaces()
    }

    @objc private func systemDidWake() {
        if mainWindowController?.window?.isVisible == true {
            model.startLiveHardwareMonitoring()
            if model.currentSnapshot == nil { model.refresh() }
        }
    }

    private func showMainWindow() {
        if isClosingMainWindow {
            DispatchQueue.main.async { [weak self] in self?.showMainWindow() }
            return
        }
        if let window = mainWindowController?.window {
            mainWindowController?.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            model.startLiveHardwareMonitoring()
            return
        }

        guard !isCreatingMainWindow else { return }
        isCreatingMainWindow = true
        defer { isCreatingMainWindow = false }

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
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 560)
        window.title = model.t("overview")
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        let frameName = "DriveBatteryHealthViewer.MainWindow"
        if !window.setFrameUsingName(frameName) { window.center() }
        window.setFrameAutosaveName(frameName)
        let windowController = NSWindowController(window: window)
        mainWindowController = windowController
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        model.startLiveHardwareMonitoring()
        if model.currentSnapshot == nil { model.refresh() }
        NSApp.activate(ignoringOtherApps: true)
    }
}
