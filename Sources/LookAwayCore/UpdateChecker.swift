import Foundation

/// Fetches the body at a URL. Injected so the checker can be tested without a
/// network.
public protocol DataFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

/// A published release the running app could update to.
public struct Release: Equatable, Sendable {
    public var version: String
    public var downloadURL: URL

    public init(version: String, downloadURL: URL) {
        self.version = version
        self.downloadURL = downloadURL
    }
}

public enum UpdateAvailability: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// Offline, or GitHub's answer couldn't be read.
        case fetchFailed
        /// The newest release has no zip for the updater to install.
        case noDownload
    }

    case upToDate
    case available(Release)
    case unavailable(Reason)
}

/// Asks GitHub whether a release newer than the running app has been published.
///
/// `releases/latest` never returns drafts or prereleases, so tagging
/// `v1.2.0-rc1` tests the release pipeline without offering it to anyone.
public struct UpdateChecker: Sendable {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/connortorrell/look-away/releases/latest")!
    /// The asset the updater installs; the DMG next to it is for people.
    public static let assetName = "LookAway.zip"

    public let currentVersion: String
    private let fetcher: DataFetching

    public init(currentVersion: String, fetcher: DataFetching = URLSessionFetcher()) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
    }

    public func check() async -> UpdateAvailability {
        guard let body = try? await fetcher.data(from: Self.latestReleaseURL),
              let release = try? JSONDecoder().decode(LatestRelease.self, from: body),
              let latest = AppVersion(release.tagName),
              let current = AppVersion(currentVersion)
        else {
            return .unavailable(.fetchFailed)
        }
        guard latest > current else { return .upToDate }
        guard let asset = release.assets.first(where: { $0.name == Self.assetName }) else {
            return .unavailable(.noDownload)
        }
        return .available(Release(version: latest.description, downloadURL: asset.browserDownloadURL))
    }

    /// The part of GitHub's release JSON the checker reads.
    private struct LatestRelease: Decodable {
        struct Asset: Decodable {
            var name: String
            var browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        var tagName: String
        var assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }
}

/// A dotted version number such as `1.10.2`, compared number by number so
/// `1.10` is newer than `1.9`. A leading `v` is dropped, and missing trailing
/// numbers count as zero, so `1.2` equals `1.2.0`.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? string.dropFirst() : Substring(string)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { UInt($0) }
        guard !parts.isEmpty, numbers.count == parts.count else { return nil }
        components = numbers.map { Int($0) }
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Fetches with `URLSession`, treating anything but a 200 as a failure.
public struct URLSessionFetcher: DataFetching {
    public struct BadStatus: Error {
        public let code: Int
    }

    public init() {}

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw BadStatus(code: code) }
        return data
    }
}
