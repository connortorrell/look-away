import AppKit
import LookAwayCore
import Observation

/// One installed app, as offered by the search field.
struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL

    var id: String { bundleID }

    var meetingApp: MeetingApp {
        MeetingApp(bundleID: bundleID, name: name)
    }
}

/// The list of apps on this Mac, for the meeting-app picker.
///
/// Scanned from the usual application folders rather than asked of Launch
/// Services, because there is no API that just hands over "every installed
/// app". The scan takes a moment, so it happens off the main thread once and
/// the result is reused for the rest of the session.
@MainActor
@Observable
final class InstalledApps {
    private(set) var all: [InstalledApp] = []
    private var scan: Task<[InstalledApp], Never>?

    private nonisolated static let searchRoots = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        // Safari and friends ship in a sealed volume and are only symlinked
        // into /Applications, where the link itself is marked hidden.
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    /// Loads the list the first time it is needed. Repeat callers join the scan
    /// already in flight rather than starting a second one.
    @discardableResult
    func load() async -> [InstalledApp] {
        if let scan { return await scan.value }
        let task = Task { await Task.detached(priority: .userInitiated) { Self.scanApplicationFolders() }.value }
        scan = task
        let found = await task.value
        all = found
        return found
    }

    /// Apps matching `query`, minus the ones already chosen. An empty query
    /// lists everything, which is what the field shows when it opens.
    func matches(_ query: String, excluding chosen: MeetingSettings) -> [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let available = all.filter { !chosen.contains($0.bundleID) }
        guard !trimmed.isEmpty else { return available }
        return available
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) || $0.bundleID.localizedCaseInsensitiveContains(trimmed) }
            // A name that starts with the query is what the user meant.
            .sorted { lhs, rhs in
                let left = lhs.name.localizedCaseInsensitiveHasPrefix(trimmed)
                let right = rhs.name.localizedCaseInsensitiveHasPrefix(trimmed)
                if left != right { return left }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - Scanning

    private nonisolated static func scanApplicationFolders() -> [InstalledApp] {
        let manager = FileManager.default
        var byBundleID: [String: InstalledApp] = [:]

        for root in searchRoots {
            let rootURL = URL(fileURLWithPath: root)
            guard let walker = manager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in walker {
                guard url.pathExtension == "app" else {
                    // Only a couple of levels down; vendors nest apps in a
                    // folder, but nobody buries them deeper than that.
                    if walker.level > 3 { walker.skipDescendants() }
                    continue
                }
                walker.skipDescendants()
                guard let app = describe(url) else { continue }
                // Keep the first hit: /Applications wins over a system copy.
                if byBundleID[app.bundleID] == nil { byBundleID[app.bundleID] = app }
            }
        }

        return byBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private nonisolated static func describe(_ url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              !bundleID.isEmpty
        else { return nil }

        let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(bundleID: bundleID, name: name, url: url)
    }
}

private extension String {
    func localizedCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
    }
}
