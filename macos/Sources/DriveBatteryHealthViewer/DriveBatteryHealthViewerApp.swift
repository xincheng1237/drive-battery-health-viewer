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
        if geteuid() == 0 {
            FileHandle.standardError.write(Data("The main application must not run as root.\n".utf8))
            exit(77)
        }
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

/// Debug-only isolated launch for exercising the actual application lifecycle.
/// Release builds never select this path or read the QA environment variable.
@MainActor
private enum ApplicationLaunchContext {
    static var isIsolatedReview: Bool {
        #if DEBUG
        return Bundle.main.bundleIdentifier == "com.chengxin.dbhv.ui-review"
        #else
        return false
        #endif
    }

    static func makeModel() -> AppModel {
        #if DEBUG
        if isIsolatedReview {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DBHV-Isolated-UI-Review")
            let defaults = UserDefaults(suiteName: "com.chengxin.dbhv.ui-review.preferences") ?? .standard
            defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: "language")
            defaults.set(directory.appendingPathComponent("history").path, forKey: "historyDirectory")
            let logger = DiagnosticLogger(directory: directory.appendingPathComponent("logs"))
            let manager = ChargeProtectionManager(defaults: defaults, logger: logger, isAppleSilicon: false,
                                                   configurationDirectory: directory.appendingPathComponent("charge"))
            return AppModel(defaults: defaults, diagnosticLogger: logger, chargeProtection: manager)
        }
        #endif
        return AppModel()
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = ApplicationLaunchContext.makeModel()
    private var mainWindowController: NSWindowController?
    private var isCreatingMainWindow = false
    private var isClosingMainWindow = false
    private var backgroundedAt: Date?

    func prepareMainMenuForLaunch() {
        MainMenuLocalizer.install(model.language, model: model)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLogger.shared.log(.info, category: "lifecycle", event: "application_started", message: "Application started on \(ProcessInfo.processInfo.operatingSystemVersionString).")
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
        if !ApplicationLaunchContext.isIsolatedReview { model.chargeProtection.ensureStatusAgentInstalled() }
        showMainWindow()
        // Let the first window become usable before explaining a one-time
        // administrator request that may be needed to replace an older helper.
        // The system authorization dialog is never launched without this
        // explicit user-facing preflight.
        if !ApplicationLaunchContext.isIsolatedReview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.model.chargeProtection.requestInstalledHelperUpdateAuthorizationIfNeeded()
            }
        }
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

    func applicationDidBecomeActive(_ notification: Notification) {
        // Waking from sleep, leaving the lock screen, or returning from a
        // different Space does not always make `NSWindow.isVisible` true at
        // the instant NSWorkspace posts its wake notification. Reassert the
        // lightweight monitors whenever the app becomes active so live
        // battery values cannot remain frozen at the pre-sleep snapshot.
        let previousBackgroundDate = backgroundedAt
        backgroundedAt = nil
        if mainWindowController?.window != nil {
            model.startLiveHardwareMonitoring()
        }
        if let previousBackgroundDate,
           BackgroundRefreshPolicy.requiresCheckpoint(backgroundedAt: previousBackgroundDate) {
            model.refreshAfterExtendedBackground()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Record only the first transition out of the foreground. Repeated
        // resign notifications must not shorten a genuine long-background
        // interval and suppress its checkpoint refresh.
        if backgroundedAt == nil {
            backgroundedAt = Date()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticLogger.shared.log(.info, category: "lifecycle", event: "application_terminating", message: "Application is terminating normally.")
        DiagnosticLogger.shared.flush()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        model.stopLiveHardwareMonitoring()
        model.stopChargeProtectionMonitoring()
        DBHVResetNVMeSMARTInterfaces()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              mainWindowController?.window === closingWindow else { return }
        isClosingMainWindow = true
        DiagnosticLogger.shared.log(.info, category: "lifecycle", event: "main_window_closed", message: "The main window closed.")
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

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              mainWindowController?.window === window else { return }
        model.startLiveHardwareMonitoring()
    }

    @objc private func systemWillSleep() {
        DiagnosticLogger.shared.log(.info, category: "lifecycle", event: "system_sleep", message: "The system is preparing to sleep.")
        model.stopLiveHardwareMonitoring()
        DBHVResetNVMeSMARTInterfaces()
    }

    @objc private func systemDidWake() {
        DiagnosticLogger.shared.log(.info, category: "lifecycle", event: "system_wake", message: "The system woke from sleep.")
        // The window can be temporarily reported as not visible while the
        // login/Space transition is still completing. Its existence, rather
        // than that transient flag, is the correct ownership boundary.
        if mainWindowController?.window != nil {
            model.startLiveHardwareMonitoring()
            if model.currentSnapshot == nil { model.refreshWithoutSavingHistory() }
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

        let windowController = MainWindowController(model: model)
        guard let window = windowController.window else { return }
        window.delegate = self
        mainWindowController = windowController
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        model.startLiveHardwareMonitoring()
        if model.currentSnapshot == nil { model.refreshForColdLaunch() }
        NSApp.activate(ignoringOtherApps: true)
    }
}
