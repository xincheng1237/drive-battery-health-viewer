import Foundation

@main
struct OwnershipFixture {
    static func main() {
        let arguments = CommandLine.arguments
        let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let marker = directory.appendingPathComponent("powerui-owner.json")
        let backup = directory.appendingPathComponent(".helper-upgrade/powerui-owner.json")
        do {
            if arguments[1] == "--verify-resume" {
                try verifyResume(marker: marker)
                return
            }
            try migratePowerUIOwnership(
                marker: marker,
                backup: backup,
                preparing: arguments[1] == "--prepare-upgrade-ownership",
                requireRoot: false
            ) {
                switch arguments[3] {
                case "clean": .clean
                case "topOff": .restoredTopOff
                case "system": .system
                default: .unknown
                }
            }
        } catch {
            FileHandle.standardError.write(Data("Ownership migration refused: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func verifyResume(marker: URL) throws {
        let inspection = inspectPowerUIOwnershipFile(at: marker, requireRoot: false)
        guard case .owned(let ownership) = inspection, ownership.leaseState == .deferredToSystem else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var coordinator = PowerUIProtectionCoordinator()
        let now = ContinuousClock.now
        var input = PowerUIProtectionCoordinator.Input(
            batteryPercentage: 80, isCharging: true, adapterConnected: true, systemAdapterConnected: true,
            checkpoint: 5, engaged: false, temporarilyDisabled: true, hasOwnership: false
        )
        precondition(coordinator.evaluate(input: input, now: now).request == nil)
        var authorizations: [Bool] = []
        for baseline: PowerUIOwnershipBaseline in [.system, .unknown, .restoredTopOff, .clean] {
            let acquired = try acquirePowerUIOwnership(
                inspection: inspection, baseline: baseline, percentage: 80,
                persist: { try PowerUIOwnershipStore.write($0, to: marker) },
                retire: { try PowerUIOwnershipStore.remove(at: marker) },
                engage: { alreadyOwned in authorizations.append(alreadyOwned); return true },
                restore: { false }
            )
            precondition(acquired == (baseline == .clean))
        }
        precondition(authorizations == [false])
        guard case .owned(let resumed) = inspectPowerUIOwnershipFile(at: marker, requireRoot: false),
              resumed.leaseState == .activeEighty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        input.temporarilyDisabled = false
        input.checkpoint = 0
        input.powerUIActive = false
        precondition(coordinator.evaluate(input: input, now: now).request == .recover)
        input.checkpoint = 2
        input.powerUIActive = true
        input.engaged = true
        input.isCharging = false
        input.hasOwnership = true
        input.isHoldApplied = true
        precondition(!coordinator.evaluate(input: input, now: now).holding)
        precondition(coordinator.evaluate(input: input, now: now.advanced(by: .seconds(4))).holding)
        print("System/unknown/unowned CP5: no actuation. Clean CP0: fresh 80% lease, then confirmed hold.")
    }
}
