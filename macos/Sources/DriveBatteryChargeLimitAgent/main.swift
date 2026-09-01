import AppKit
import Darwin
import Foundation

if geteuid() == 0 {
    FileHandle.standardError.write(Data("The charge-limit menu-bar agent must not run as root.\n".utf8))
    exit(77)
}

/// A LaunchAgent job and a legacy LaunchServices launch can overlap briefly
/// during upgrades. A non-blocking advisory lock guarantees that only one of
/// them is ever allowed to own an NSStatusItem for this user session.
final class ChargeLimitAgentInstanceLock {
    private let descriptor: Int32

    init?() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/DriveBatteryHealthViewer/ChargeLimitAgent",
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch { return nil }
        let path = directory.appendingPathComponent("instance.lock").path
        let opened = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { return nil }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(opened)
            return nil
        }
        descriptor = opened
    }

    deinit {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}

@MainActor
final class ChargeLimitAgentApplicationDelegate: NSObject, NSApplicationDelegate {
    private let instanceLock: ChargeLimitAgentInstanceLock
    var model: ChargeLimitAgentModel?
    var statusItemController: ChargeLimitAgentStatusItemController?

    init(instanceLock: ChargeLimitAgentInstanceLock) {
        self.instanceLock = instanceLock
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startStatusItemIfNeeded()
    }

    /// LaunchAgents are started directly by launchd rather than LaunchServices.
    /// On affected macOS 15 builds the did-finish-launching callback can be
    /// delayed or missed while a freshly replaced LSUIElement is registering.
    /// Keep initialization idempotent so the explicit post-finish call below
    /// and the normal AppKit callback safely cover both launch paths.
    func startStatusItemIfNeeded() {
        guard model == nil, statusItemController == nil else { return }
        // NSStatusItem registration is only reliable after AppKit has completed
        // launch and connected this LaunchAgent process to the current GUI
        // session's SystemUIServer. Creating it before `finishLaunching()` can
        // leave a healthy process with no visible status item.
        let model = ChargeLimitAgentModel()
        let controller = ChargeLimitAgentStatusItemController(model: model)
        self.model = model
        statusItemController = controller
        model.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.invalidate()
        statusItemController = nil
        model = nil
    }
}

@MainActor
func runChargeLimitAgentApplication() {
    guard let instanceLock = ChargeLimitAgentInstanceLock() else { return }
    let application = NSApplication.shared
    let delegate = ChargeLimitAgentApplicationDelegate(instanceLock: instanceLock)
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.finishLaunching()
    delegate.startStatusItemIfNeeded()
    withExtendedLifetime(delegate) {
        application.run()
    }
    application.delegate = nil
}

MainActor.assumeIsolated { runChargeLimitAgentApplication() }
