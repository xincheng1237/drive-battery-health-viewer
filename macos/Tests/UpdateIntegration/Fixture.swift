import AppKit
import CryptoKit
import Sparkle

@MainActor
final class RecordingDriver: NSObject, SPUUserDriver {
    var events: [String] = []
    var cancelDownload = false

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        events.append("permission")
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { events.append("manual") }
    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        events.append("found:\(item.versionString):\(item.signingValidationStatus.rawValue)")
        reply(cancelDownload ? .install : .dismiss)
    }
    func showUpdateReleaseNotes(with data: SPUDownloadData) { events.append("notes") }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) { events.append("notes-error") }
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        events.append("no-update"); acknowledgement()
    }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        events.append("error"); acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        events.append("download-cancel"); cancellation()
    }
    func showDownloadDidReceiveExpectedContentLength(_ length: UInt64) { events.append("length") }
    func showDownloadDidReceiveData(ofLength length: UInt64) { events.append("bytes") }
    func showDownloadDidStartExtractingUpdate() { events.append("extract") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        events.append("ready"); reply(.dismiss)
    }
    func showInstallingUpdate(withApplicationTerminated terminated: Bool, retryTerminatingApplication: @escaping () -> Void) { events.append("installing") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        events.append("installed"); acknowledgement()
    }
    func dismissUpdateInstallation() { events.append("finished") }
    func showUpdateInFocus() { events.append("focus") }
}

@main
@MainActor
struct Fixture {
    static func main() async throws {
        if CommandLine.arguments[1] == "key" {
            let key = Curve25519.Signing.PrivateKey()
            try key.rawRepresentation.base64EncodedString().write(
                toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8
            )
            print(key.publicKey.rawRepresentation.base64EncodedString())
            return
        }
        let scenario = CommandLine.arguments[1]
        if scenario == "install-handoff-mock" {
            let standard = RecordingDriver()
            let driver = QuietScheduledUpdateDriver(standard: standard)
            driver.showUserInitiatedUpdateCheck(cancellation: {})
            var choice: SPUUserUpdateChoice?
            driver.showReady(toInstallAndRelaunch: { choice = $0 })
            precondition(choice == .dismiss)
            driver.showInstallingUpdate(withApplicationTerminated: false, retryTerminatingApplication: {})
            var acknowledged = false
            driver.showUpdateInstalledAndRelaunched(false, acknowledgement: { acknowledged = true })
            driver.dismissUpdateInstallation()
            precondition(acknowledged && standard.events == ["manual", "ready", "installing", "installed", "finished"])
            print("PASS mock install handoff \(standard.events)")
            return
        }
        let bundleID = Bundle.main.bundleIdentifier!
        let defaults = UserDefaults.standard
        defer { defaults.removePersistentDomain(forName: bundleID) }
        // Simulate elapsed time without changing the machine clock or interval.
        if scenario == "running" {
            defaults.set(Date().addingTimeInterval(-604800 + 3), forKey: "SULastCheckTime")
        } else if scenario == "restart" {
            defaults.set(Date(), forKey: "SULastCheckTime")
        }
        if scenario == "upgrade-legacy" {
            let driver = RecordingDriver()
            driver.cancelDownload = true
            // The published 1.2 config starts Sparkle on explicit request.
            let legacy = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
            try legacy.start()
            legacy.checkForUpdates()
            let deadline = ContinuousClock.now + .seconds(15)
            while !driver.events.contains("finished"), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            precondition(driver.events.filter { $0 == "manual" }.count == 1, "\(driver.events)")
            precondition(driver.events.contains("found:39:1") && driver.events.contains("download-cancel"), "\(driver.events)")
            precondition(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "35")
            print("PASS 1.2 (35) manual selection of signed 1.3 (39), download canceled")
            return
        }
        let driver = RecordingDriver()
        driver.cancelDownload = scenario == "download"
        let quietWindowCheck = scenario == "quiet-standard"
        let app = quietWindowCheck ? NSApplication.shared : nil
        let wasActive = app?.isActive
        let visibleWindows = app?.windows.filter { $0.isVisible }.count
        let keyWindow = app?.keyWindow
        let updater = InAppUpdater(standardDriver: quietWindowCheck ? nil : driver)
        var updates: [AvailableAppUpdate] = []
        var emptyResults = 0
        updater.scheduledResult = {
            if let update = $0 { updates.append(update) }
            else { emptyResults += 1 }
        }
        if scenario == "disabled" { updater.automaticallyChecks = false }
        try updater.start()
        func wait(_ seconds: Int, until condition: () -> Bool) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(seconds)
            while !condition() && clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        }
        switch scenario {
        case "quiet-standard":
            try await wait(24) { !updates.isEmpty }
            precondition(updates == [AvailableAppUpdate(version: "1.3.1", build: "40")])
            try await Task.sleep(for: .milliseconds(350))
            precondition(app?.isActive == wasActive && app?.keyWindow === keyWindow)
            precondition(app?.modalWindow == nil && app?.windows.filter { $0.isVisible }.count == visibleWindows)
        case "upgrade-queued":
            let coordination = URL(fileURLWithPath: CommandLine.arguments[2]).deletingLastPathComponent()
            let started = coordination.appendingPathComponent("queue-started")
            let release = coordination.appendingPathComponent("queue-release")
            try await wait(20) { FileManager.default.fileExists(atPath: started.path) }
            precondition(FileManager.default.fileExists(atPath: started.path))
            precondition(updates.isEmpty && driver.events.isEmpty)
            try updater.checkForUpdates()
            try updater.checkForUpdates()
            try await Task.sleep(for: .milliseconds(350))
            precondition(driver.events.isEmpty && !updater.canCheckForUpdates)
            try Data().write(to: release)
            try await wait(15) { driver.events.contains("finished") && updater.canCheckForUpdates }
            precondition(updates == [AvailableAppUpdate(version: "1.3", build: "39")], "\(updates)")
            precondition(driver.events.filter { $0 == "manual" }.count == 1 && driver.events.contains("found:39:1"), "\(driver.events)")
        case "new", "running", "download", "higher":
            if scenario == "running" {
                try await Task.sleep(for: .seconds(1))
                precondition(updates.isEmpty)
            }
            try await wait(24) { !updates.isEmpty }
            precondition(updates == [AvailableAppUpdate(version: scenario == "higher" ? "1.2.2" : "1.2.1", build: "38")], "\(updates)")
            precondition(driver.events.isEmpty, "\(driver.events)")
            try updater.checkForUpdates()
            try updater.checkForUpdates()
            try await wait(12) { driver.events.contains("finished") }
            precondition(driver.events.filter { $0 == "manual" }.count == 1, "\(driver.events)")
            precondition(driver.events.contains("found:38:1"), "\(driver.events)")
            precondition(driver.events.contains("download-cancel") == (scenario == "download"), "\(driver.events)")
        case "disabled", "restart":
            try await Task.sleep(for: .seconds(3))
            precondition(updates.isEmpty && driver.events.isEmpty)
            try updater.checkForUpdates()
            try await wait(12) { driver.events.contains("finished") }
            precondition(driver.events.contains("found:38:1"), "\(driver.events)")
        case "none":
            try await wait(12) { emptyResults != 0 }
            precondition(emptyResults == 1 && updates.isEmpty && driver.events.isEmpty)
        case "offline", "recover", "malformed", "tampered":
            try await Task.sleep(for: .seconds(5))
            precondition(updates.isEmpty && driver.events.isEmpty)
            if scenario == "recover" {
                try Data().write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            }
            try updater.checkForUpdates()
            try await wait(12) { driver.events.contains("finished") }
            precondition(driver.events.contains("manual"), "\(driver.events)")
            if scenario == "recover" { precondition(driver.events.contains("found:38:1"), "\(driver.events)") }
        default: preconditionFailure(scenario)
        }
        print("PASS \(scenario) background=\(updates) noUpdate=\(emptyResults) standard=\(driver.events)")
    }
}
