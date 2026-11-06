import Foundation

/// Decides whether a launch represents an installed app update that merits the
/// one-time, nonmodal release-notes hint. The release identity includes both
/// the public version and the internal build so same-version replacement builds
/// are detected. A clean installation intentionally remains quiet.
enum VersionUpdatePromptPolicy {
    static func releaseIdentifier(version: String, build: String) -> String? {
        guard AppVersion(version) != nil else { return nil }
        let trimmedBuild = build.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBuild.isEmpty else { return nil }
        return "\(version)#\(trimmedBuild)"
    }

    static func shouldPresent(
        previousReleaseIdentifier: String?,
        legacyPreviousVersion: String?,
        currentVersion: String,
        currentBuild: String,
        hasExistingAppData: Bool
    ) -> Bool {
        guard let currentReleaseIdentifier = releaseIdentifier(
            version: currentVersion,
            build: currentBuild
        ) else { return false }
        if let previousReleaseIdentifier {
            return previousReleaseIdentifier != currentReleaseIdentifier
        }
        // The previous implementation persisted only the public version. Its
        // presence proves this is an upgrade, but cannot identify the old build,
        // so migrate by showing the hint once and recording the full identity.
        return legacyPreviousVersion != nil || hasExistingAppData
    }
}

struct AppVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    init?(_ value: String) {
        guard let normalized = Self.normalized(value) else { return nil }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.compactMap({ Int($0) }).count == parts.count else { return nil }
        var parsed = parts.compactMap { Int($0) }
        while parsed.count > 1, parsed.last == 0 { parsed.removeLast() }
        components = parsed
    }

    static func normalized(_ value: String) -> String? {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.first == "v" || result.first == "V" { result.removeFirst() }
        result = String(result.prefix { $0 != "-" && $0 != "+" })
        guard !result.isEmpty else { return nil }
        return result
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
