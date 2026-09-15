import Foundation

/// An app that counts as "being in a meeting" while it is using the microphone
/// or camera.
///
/// `bundleID` identifies the app the user picked. Detection sees the bundle IDs
/// of the processes actually holding the audio device, and those are often not
/// the app itself: Electron and Chromium apps capture from a helper
/// (`com.pop.pop.app.helper`), and Zoom captures from a sibling process
/// (`us.zoom.caphost`, next to `us.zoom.xos`). `extraPrefixes` covers the
/// sibling case; the helper case is handled for every app by matching any
/// bundle ID nested under `bundleID`.
public struct MeetingApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    /// Kept alongside the ID so a chip still reads properly after the app is
    /// uninstalled, and so settings never have to hit the disk to draw.
    public var name: String
    /// Bundle ID prefixes that belong to this app but are not nested under its
    /// own ID.
    public var extraPrefixes: [String]

    public var id: String { bundleID }

    public init(bundleID: String, name: String, extraPrefixes: [String] = []) {
        self.bundleID = bundleID
        self.name = name
        self.extraPrefixes = extraPrefixes
    }

    /// Whether a process's bundle ID belongs to this app. Compared
    /// case-insensitively because helpers do not always match the case of the
    /// app they belong to — Arc ships as `company.thebrowser.Browser` but
    /// captures audio from `company.thebrowser.browser.helper`.
    public func matches(processBundleID: String) -> Bool {
        let process = processBundleID.lowercased()
        let own = bundleID.lowercased()
        if process == own || process.hasPrefix(own + ".") { return true }
        return extraPrefixes.contains { process.hasPrefix($0.lowercased()) }
    }
}

// MARK: - Known apps

public extension MeetingApp {
    /// Apps worth offering up front. On first run the ones actually installed
    /// are pre-selected; every other app on the Mac is reachable through the
    /// search field, so this list only has to cover the common cases.
    static let presets: [MeetingApp] = [
        MeetingApp(bundleID: "us.zoom.xos", name: "Zoom", extraPrefixes: ["us.zoom."]),
        MeetingApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams", extraPrefixes: ["com.microsoft.teams"]),
        MeetingApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
        MeetingApp(bundleID: "com.pop.pop.app", name: "Pop", extraPrefixes: ["com.pop."]),
        MeetingApp(bundleID: "com.hnc.Discord", name: "Discord"),
        MeetingApp(bundleID: "com.apple.FaceTime", name: "FaceTime"),
        MeetingApp(bundleID: "Cisco-Systems.Spark", name: "Webex", extraPrefixes: ["com.webex."]),
        MeetingApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
        MeetingApp(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge"),
        MeetingApp(bundleID: "company.thebrowser.Browser", name: "Arc"),
        // Safari hands capture to a shared WebKit process that does not say
        // which browser it came from, so this entry covers any WebKit browser.
        MeetingApp(bundleID: "com.apple.Safari", name: "Safari", extraPrefixes: ["com.apple.WebKit"]),
    ]

    /// The preset carrying the extra prefixes for `bundleID`, if there is one.
    /// Lets an app picked out of the installed-apps list inherit the sibling
    /// and helper knowledge baked into `presets`.
    static func preset(for bundleID: String) -> MeetingApp? {
        presets.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}
