import Foundation
import Testing
@testable import LookAwayCore

/// Answers with a fixed body, or fails as if offline.
private struct FakeGitHub: DataFetching {
    var body: String?

    func data(from url: URL) async throws -> Data {
        guard let body else { throw URLError(.notConnectedToInternet) }
        return Data(body.utf8)
    }
}

struct UpdateCheckerTests {
    private static let zipURL = "https://github.com/connortorrell/look-away/releases/download/v1.2.0/LookAway.zip"

    /// GitHub's release JSON, trimmed to what the checker reads plus a DMG
    /// asset it should skip.
    private static func release(tag: String, assets: [String] = ["LookAway.dmg", "LookAway.zip"]) -> String {
        let list = assets.map { name in
            #"{"name": "\#(name)", "browser_download_url": "https://github.com/connortorrell/look-away/releases/download/\#(tag)/\#(name)"}"#
        }
        return #"{"tag_name": "\#(tag)", "html_url": "https://example.com", "assets": [\#(list.joined(separator: ","))]}"#
    }

    private static func check(current: String, body: String?) async -> UpdateAvailability {
        await UpdateChecker(currentVersion: current, fetcher: FakeGitHub(body: body)).check()
    }

    @Test func offersANewerRelease() async {
        let result = await Self.check(current: "1.1.0", body: Self.release(tag: "v1.2.0"))
        #expect(result == .available(Release(version: "1.2.0", downloadURL: URL(string: Self.zipURL)!)))
    }

    @Test func isUpToDateOnTheSameVersion() async {
        #expect(await Self.check(current: "1.2.0", body: Self.release(tag: "v1.2.0")) == .upToDate)
    }

    @Test func neverOffersAnOlderRelease() async {
        #expect(await Self.check(current: "1.3.0", body: Self.release(tag: "v1.2.0")) == .upToDate)
    }

    @Test func comparesNumbersRatherThanText() async {
        let result = await Self.check(current: "1.9", body: Self.release(tag: "v1.10"))
        guard case .available(let release) = result else {
            Issue.record("expected an update, got \(result)")
            return
        }
        #expect(release.version == "1.10")
    }

    @Test func treatsMissingTrailingNumbersAsZero() async {
        #expect(await Self.check(current: "1.2", body: Self.release(tag: "v1.2.0")) == .upToDate)
    }

    @Test func holdsBackWhenTheReleaseHasNoZip() async {
        let body = Self.release(tag: "v1.2.0", assets: ["LookAway.dmg"])
        #expect(await Self.check(current: "1.1.0", body: body) == .unavailable(.noDownload))
    }

    @Test func failsOnUnreadableJSON() async {
        #expect(await Self.check(current: "1.1.0", body: "<html>rate limited</html>") == .unavailable(.fetchFailed))
    }

    @Test func failsOnAnUnreadableTag() async {
        #expect(await Self.check(current: "1.1.0", body: Self.release(tag: "latest")) == .unavailable(.fetchFailed))
    }

    @Test func failsWhenOffline() async {
        #expect(await Self.check(current: "1.1.0", body: nil) == .unavailable(.fetchFailed))
    }

    @Test(arguments: [
        ("v1.2.3", [1, 2, 3]),
        ("1.2.3", [1, 2, 3]),
        ("10", [10]),
    ])
    func readsVersions(text: String, components: [Int]) {
        #expect(AppVersion(text)?.components == components)
    }

    @Test(arguments: ["", "v", "1..2", "1.2-rc1", "-1.0", "1.x"])
    func rejectsMalformedVersions(text: String) {
        #expect(AppVersion(text) == nil)
    }
}
