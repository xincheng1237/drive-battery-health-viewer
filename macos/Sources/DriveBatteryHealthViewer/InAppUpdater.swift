import AppKit
import Sparkle

struct AvailableAppUpdate: Equatable {
    let version: String
    let build: String
}

func isNewerSparkleBuild(_ build: String, than other: String) -> Bool {
    SUStandardVersionComparator.default.compareVersion(build, toVersion: other) == .orderedDescending
}

@MainActor
protocol ApplicationUpdating: AnyObject {
    var canCheckForUpdates: Bool { get }
    var availabilityChanged: ((Bool) -> Void)? { get set }
    func checkForUpdates() throws
}

@MainActor
protocol AutomaticallyCheckingForUpdates: ApplicationUpdating {
    var automaticallyChecks: Bool { get set }
    var scheduledResult: ((AvailableAppUpdate?) -> Void)? { get set }
    func start() throws
}

@MainActor
final class InAppUpdater: NSObject, AutomaticallyCheckingForUpdates, SPUUpdaterDelegate {
    var availabilityChanged: ((Bool) -> Void)?
    var scheduledResult: ((AvailableAppUpdate?) -> Void)?
    private let driver: QuietScheduledUpdateDriver
    private let host: Bundle
    private lazy var updater = SPUUpdater(
        hostBundle: host, applicationBundle: host, userDriver: driver, delegate: self
    )
    private var observation: NSKeyValueObservation?
    private var started = false
    private var manualCheckQueued = false
    private var manualCheckRequested = false

    init(host: Bundle = .main, standardDriver: (any SPUUserDriver)? = nil) {
        self.host = host
        driver = QuietScheduledUpdateDriver(
            standard: standardDriver ?? SPUStandardUserDriver(hostBundle: host, delegate: nil)
        )
        super.init()
        driver.found = { [weak self] update in
            guard let self, self.automaticallyChecks else { return }
            self.scheduledResult?(update)
        }
    }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    // A silent check must not disable the user's manual check command.
    var canCheckForUpdates: Bool { !manualCheckQueued && !manualCheckRequested && !driver.isInteractive }

    func start() throws {
        guard !started else { return }
        try updater.start()
        started = true
        observation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.availabilityChanged?(self?.canCheckForUpdates ?? true) }
        }
    }

    func checkForUpdates() throws {
        try start()
        guard canCheckForUpdates else { return }
        if !updater.sessionInProgress && updater.canCheckForUpdates {
            beginManualCheck()
        } else {
            manualCheckQueued = true
        }
        availabilityChanged?(canCheckForUpdates)
    }

    private func beginManualCheck() {
        manualCheckQueued = false
        manualCheckRequested = true
        updater.checkForUpdates()
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool {
        driver.isInteractive
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if updateCheck == .updates {
            manualCheckRequested = false
        } else if updateCheck == .updatesInBackground {
            let failure = error as NSError?
            if failure?.domain == SUSparkleErrorDomain && failure?.code == Int(SUError.noUpdateError.rawValue) {
                scheduledResult?(nil)
            }
        }
        // Sparkle completes its own cycle first. Coalesce any clicks made during
        // a background check into one user-initiated check on the next turn.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.manualCheckQueued, !self.updater.sessionInProgress, self.updater.canCheckForUpdates {
                self.beginManualCheck()
            }
            self.availabilityChanged?(self.canCheckForUpdates)
        }
    }
}

/// Sparkle schedules, validates and selects the update. A scheduled result is
/// dismissed at the driver boundary, before any standard UI or download can
/// start. Every user-initiated step stays with Sparkle's standard driver.
@MainActor
final class QuietScheduledUpdateDriver: NSObject, SPUUserDriver {
    private let standard: any SPUUserDriver
    private(set) var isInteractive = false
    var found: ((AvailableAppUpdate) -> Void)?

    init(standard: any SPUUserDriver) { self.standard = standard }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // The application supplies an explicit default and a settings switch.
        // If an unexpected permission callback occurs, fail closed without UI.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        isInteractive = true
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if state.userInitiated {
            isInteractive = true
            standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
        } else {
            if state.stage == .notDownloaded &&
                appcastItem.signingValidationStatus == .succeeded && !appcastItem.isInformationOnlyUpdate {
                found?(AvailableAppUpdate(version: appcastItem.displayVersionString, build: appcastItem.versionString))
            }
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        if isInteractive { standard.showUpdateReleaseNotes(with: downloadData) }
    }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        if isInteractive { standard.showUpdateReleaseNotesFailedToDownloadWithError(error) }
    }
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        if isInteractive { standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement) }
        else { acknowledgement() }
    }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        if isInteractive { standard.showUpdaterError(error, acknowledgement: acknowledgement) }
        else { acknowledgement() }
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        if isInteractive { standard.showDownloadInitiated(cancellation: cancellation) }
        else { cancellation() }
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        if isInteractive { standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength) }
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        if isInteractive { standard.showDownloadDidReceiveData(ofLength: length) }
    }
    func showDownloadDidStartExtractingUpdate() {
        if isInteractive { standard.showDownloadDidStartExtractingUpdate() }
    }
    func showExtractionReceivedProgress(_ progress: Double) {
        if isInteractive { standard.showExtractionReceivedProgress(progress) }
    }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if isInteractive { standard.showReady(toInstallAndRelaunch: reply) }
        else { reply(.dismiss) }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        if isInteractive {
            standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
        }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        if isInteractive { standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement) }
        else { acknowledgement() }
    }
    func dismissUpdateInstallation() {
        if isInteractive { standard.dismissUpdateInstallation() }
        isInteractive = false
    }
    func showUpdateInFocus() {
        if isInteractive { standard.showUpdateInFocus?() }
    }
}
