import Foundation

struct HistoryStore: Sendable {
    var directory: URL

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DriveBatteryHealthViewer/History", isDirectory: true)
    }

    func load() throws -> [HistoryRecord] {
        try ensureDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasSuffix(".hhv.json") }
            .compactMap { try? decoder.decode(HistoryRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.snapshot.generatedAt > $1.snapshot.generatedAt }
    }

    @discardableResult
    func save(snapshot: HealthSnapshot, source: HistorySource, exportPath: String? = nil, hideSerials: Bool) throws -> HistoryRecord {
        try ensureDirectory()
        let storedSnapshot = hideSerials ? snapshot.redactingSerialNumbers() : snapshot
        let record = HistoryRecord(source: source, snapshot: storedSnapshot, exportPath: exportPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: fileURL(for: record), options: [.atomic])
        return record
    }

    func delete(_ record: HistoryRecord) throws {
        let url = fileURL(for: record)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for record: HistoryRecord) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let name = "HHV_\(formatter.string(from: record.snapshot.generatedAt))_\(record.id.uuidString).hhv.json"
        return directory.appendingPathComponent(name)
    }
}

extension HealthSnapshot {
    func redactingSerialNumbers() -> HealthSnapshot {
        var copy = self
        copy.drives = drives.map { drive in
            var value = drive
            value.serialNumber = value.serialNumber == nil ? nil : "••••••••"
            return value
        }
        copy.batteries = batteries.map { battery in
            var value = battery
            value.serialNumber = value.serialNumber == nil ? nil : "••••••••"
            return value
        }
        return copy
    }
}
