import Foundation

struct AppReleaseInfo: Equatable, Sendable {
    let version: String
    let pageURL: URL
}

struct AvailableAppUpdate: Identifiable, Equatable, Sendable {
    var id: String { version }
    let currentVersion: String
    let version: String
    let pageURL: URL
}

protocol AppReleaseChecking: Sendable {
    func latestStableRelease() async throws -> AppReleaseInfo
}

struct GitHubReleaseChecker: AppReleaseChecking {
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/xincheng1237/drive-battery-health-viewer/releases/latest"
    )!

    func latestStableRelease() async throws -> AppReleaseInfo {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DriveBatteryHealthViewer/\(applicationVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.invalidResponse
        }
        return try Self.decodeRelease(from: data)
    }

    static func decodeRelease(from data: Data) throws -> AppReleaseInfo {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease,
              let version = AppVersion.normalized(release.tagName),
              let url = URL(string: release.htmlURL) else {
            throw UpdateCheckError.invalidRelease
        }
        return AppReleaseInfo(version: version, pageURL: url)
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }
}

enum UpdateCheckError: Error {
    case invalidResponse
    case invalidRelease
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
