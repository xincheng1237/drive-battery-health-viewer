import Foundation

@main
struct OwnershipFixture {
    static func main() {
        let arguments = CommandLine.arguments
        let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let marker = directory.appendingPathComponent("powerui-owner.json")
        let backup = directory.appendingPathComponent(".helper-upgrade/powerui-owner.json")
        do {
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
}
