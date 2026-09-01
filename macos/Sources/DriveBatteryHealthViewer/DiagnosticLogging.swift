import AppKit
import Foundation
import OSLog

enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error
}

struct DiagnosticLogRecord: Codable, Equatable, Sendable {
    let timestamp: Date
    let severity: DiagnosticSeverity
    let subsystem: String
    let category: String
    let event: String
    let message: String
    let source: String
}

protocol DiagnosticLogging: Sendable {
    func log(_ severity: DiagnosticSeverity, category: String, event: String, message: String)
}

final class DiagnosticLogger: DiagnosticLogging, @unchecked Sendable {
    static let shared = DiagnosticLogger()
    static let subsystem = "com.chengxin.drive-battery-health-viewer"
    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DriveBatteryHealthViewer", isDirectory: true)

    private let directory: URL
    private let retentionDays: Int
    private let maximumBytes: Int64
    private let queue: DispatchQueue
    private let console: Logger
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        directory: URL = DiagnosticLogger.defaultDirectory,
        retentionDays: Int = 14,
        maximumBytes: Int64 = 16 * 1_024 * 1_024,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.retentionDays = retentionDays
        self.maximumBytes = maximumBytes
        self.fileManager = fileManager
        self.now = now
        self.queue = DispatchQueue(label: "com.chengxin.dbhv.diagnostic-log", qos: .utility)
        self.console = Logger(subsystem: Self.subsystem, category: "application")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
        queue.async { [weak self] in self?.prepareAndClean() }
    }

    func log(_ severity: DiagnosticSeverity, category: String, event: String, message: String) {
        #if !DEBUG
        if severity == .debug { return }
        #endif
        let safeCategory = Self.safeToken(category)
        let safeEvent = Self.safeToken(event)
        let safeMessage = Self.redact(message)
        switch severity {
        case .debug: console.debug("[\(safeCategory, privacy: .public)] \(safeEvent, privacy: .public): \(safeMessage, privacy: .public)")
        case .info: console.info("[\(safeCategory, privacy: .public)] \(safeEvent, privacy: .public): \(safeMessage, privacy: .public)")
        case .warning: console.warning("[\(safeCategory, privacy: .public)] \(safeEvent, privacy: .public): \(safeMessage, privacy: .public)")
        case .error: console.error("[\(safeCategory, privacy: .public)] \(safeEvent, privacy: .public): \(safeMessage, privacy: .public)")
        }
        let record = DiagnosticLogRecord(
            timestamp: now(),
            severity: severity,
            subsystem: Self.subsystem,
            category: safeCategory,
            event: safeEvent,
            message: safeMessage,
            source: "APP"
        )
        queue.async { [weak self] in self?.append(record) }
    }

    func flush() {
        queue.sync {}
    }

    func cleanNow() {
        queue.sync { prepareAndClean() }
    }

    static func redact(_ value: String, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        var result = value.replacingOccurrences(of: homeDirectory.path, with: "~")
        if let regex = try? NSRegularExpression(pattern: #"/Users/[^/\s]+"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "~")
        }
        if let serialAssignment = try? NSRegularExpression(
            pattern: #"(?i)\b(serial(?:Number)?|batterySerial|diskSerial)\s*[:=]\s*[^\s,;}]+"#
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = serialAssignment.stringByReplacingMatches(in: result, range: range, withTemplate: "$1=[REDACTED]")
        }
        return result
    }

    private static func safeToken(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" })
    }

    private func append(_ record: DiagnosticLogRecord) {
        prepareDirectory()
        let fileURL = directory.appendingPathComponent(fileName(for: record.timestamp))
        do {
            var data = try encoder.encode(record)
            data.append(0x0A)
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
            try fileManager.setAttributes([.modificationDate: record.timestamp], ofItemAtPath: fileURL.path)
        } catch {
            console.error("Unable to persist diagnostic event")
        }
        prepareAndClean()
    }

    private func prepareDirectory() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            console.error("Unable to prepare diagnostic directory")
        }
    }

    private func prepareAndClean() {
        prepareDirectory()
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = now().addingTimeInterval(-Double(retentionDays) * 86_400)
        var retained: [(url: URL, date: Date, size: Int64)] = []
        for url in files where url.lastPathComponent.hasPrefix("app-") && url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let date = values?.contentModificationDate ?? .distantPast
            if date < cutoff {
                try? fileManager.removeItem(at: url)
            } else {
                retained.append((url, date, Int64(values?.fileSize ?? 0)))
            }
        }
        var total = retained.reduce(Int64(0)) { $0 + $1.size }
        for file in retained.sorted(by: { $0.date < $1.date }) where total > maximumBytes {
            if file.url.lastPathComponent == fileName(for: now()) { continue }
            if (try? fileManager.removeItem(at: file.url)) != nil { total -= file.size }
        }
    }

    private func fileName(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "app-%04d-%02d-%02d.jsonl", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

enum DiagnosticExportValidationError: Error, Equatable {
    case startAfterEnd
    case endTooFarInFuture
}

struct DiagnosticExportRequest: Equatable, Sendable {
    let start: Date
    let end: Date

    func validate(now: Date = Date()) throws {
        guard start <= end else { throw DiagnosticExportValidationError.startAfterEnd }
        guard end <= now else { throw DiagnosticExportValidationError.endTooFarInFuture }
    }
}

struct DiagnosticExportContext: Sendable {
    let appVersion: String
    let buildVersion: String
    let selectedLanguage: String
    let helperInstalled: Bool
    let protectionEnabled: Bool?
    let fixedLimit: Int?
}

struct DiagnosticLogExporter: @unchecked Sendable {
    let appDirectory: URL
    let helperDirectory: URL
    let fileManager: FileManager

    init(
        appDirectory: URL = DiagnosticLogger.defaultDirectory,
        helperDirectory: URL = URL(fileURLWithPath: "/Library/Logs/DriveBatteryHealthViewer", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.appDirectory = appDirectory
        self.helperDirectory = helperDirectory
        self.fileManager = fileManager
    }

    func export(
        request: DiagnosticExportRequest,
        context: DiagnosticExportContext,
        destination: URL,
        now: Date = Date()
    ) throws {
        try request.validate(now: now)
        let appResult = read(directory: appDirectory, source: "APP", request: request)
        let helperResult = read(directory: helperDirectory, source: "CHARGE-HELPER", request: request)
        let entries = (appResult.records + helperResult.records).sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp { return lhs.source < rhs.source }
            return lhs.timestamp < rhs.timestamp
        }
        let formatter = ISO8601DateFormatter()
        let safeModel = Self.redactedHeaderValue(Self.macModel)
        let safeLanguage = Self.redactedHeaderValue(context.selectedLanguage)
        var lines = [
            "Drive & Battery Health Viewer",
            "App version: \(context.appVersion)",
            "Build version: \(context.buildVersion)",
            "macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Architecture: \(Self.architecture)",
            "Mac model: \(safeModel)",
            "Selected language: \(safeLanguage)",
            "Export generated time: \(formatter.string(from: now))",
            "Requested start time: \(formatter.string(from: request.start))",
            "Requested end time: \(formatter.string(from: request.end))",
            "Helper installed: \(context.helperInstalled ? "yes" : "no")",
            "Charge protection enabled: \(context.protectionEnabled.map { $0 ? "yes" : "no" } ?? "not applicable")",
            "Fixed charge limit: \(context.fixedLimit.map { "\($0)%" } ?? "not applicable")",
            ""
        ]
        if appResult.records.isEmpty {
            lines.append("No matching app log entries in the selected period.")
        }
        if helperResult.records.isEmpty {
            lines.append("No matching helper log entries in the selected period.")
        }
        if let error = appResult.error { lines.append("[APP] Log source unavailable: \(error)") }
        if let error = helperResult.error { lines.append("[CHARGE-HELPER] Log source unavailable: \(error)") }
        for record in entries {
            lines.append("[\(record.source)] \(formatter.string(from: record.timestamp)) [\(record.severity.rawValue.uppercased())] [\(record.category)/\(record.event)] \(DiagnosticLogger.redact(record.message))")
        }
        try (lines.joined(separator: "\n") + "\n").write(to: destination, atomically: true, encoding: .utf8)
    }

    private func read(
        directory: URL,
        source: String,
        request: DiagnosticExportRequest
    ) -> (records: [DiagnosticLogRecord], error: String?) {
        do {
            let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "jsonl" }
            var records: [DiagnosticLogRecord] = []
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for url in urls {
                let data = try Data(contentsOf: url)
                for rawLine in data.split(separator: 0x0A) where !rawLine.isEmpty {
                    guard var record = try? decoder.decode(DiagnosticLogRecord.self, from: Data(rawLine)),
                          record.timestamp >= request.start, record.timestamp <= request.end else { continue }
                    if record.source != source {
                        record = DiagnosticLogRecord(
                            timestamp: record.timestamp,
                            severity: record.severity,
                            subsystem: record.subsystem,
                            category: record.category,
                            event: record.event,
                            message: record.message,
                            source: source
                        )
                    }
                    records.append(record)
                }
            }
            return (records, nil)
        } catch {
            return ([], DiagnosticLogger.redact(error.localizedDescription))
        }
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func redactedHeaderValue(_ value: String) -> String {
        DiagnosticLogger.redact(value)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static var macModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }
}
