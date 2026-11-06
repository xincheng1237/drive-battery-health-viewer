import AppKit
import Sparkle

@MainActor
protocol ApplicationUpdating: AnyObject {
    var canCheckForUpdates: Bool { get }
    var availabilityChanged: ((Bool) -> Void)? { get set }
    func checkForUpdates() throws
}

/// Sparkle owns signed-feed verification, download progress, installation,
/// normal host termination, authorization when needed, and relaunch.
@MainActor
final class InAppUpdater: NSObject, ApplicationUpdating {
    var availabilityChanged: ((Bool) -> Void)?
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )
    private var observation: NSKeyValueObservation?
    private var started = false

    var canCheckForUpdates: Bool { !started || controller.updater.canCheckForUpdates }

    func checkForUpdates() throws {
        if !started {
            try controller.updater.start()
            started = true
            observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                // Sparkle's public updater API is main-thread-only.
                MainActor.assumeIsolated {
                    self?.availabilityChanged?(change.newValue ?? false)
                }
            }
        }
        guard controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }
}
