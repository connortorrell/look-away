import Foundation

/// An app the user picked out of the installed-apps list, for either of the
/// two features that hold reminders back: the meeting list, which watches the
/// microphone and camera, and the pause list, which only watches which app you
/// are in.
///
/// `bundleID` identifies the app the user picked. Meeting detection sees the
/// bundle IDs of the processes actually holding the audio device, and those
/// are often not the app itself: Electron and Chromium apps capture from a
/// helper (`com.pop.pop.app.helper`), and Zoom captures from a sibling process
/// (`us.zoom.caphost`, next to `us.zoom.xos`). `extraPrefixes` covers the
/// sibling case; the helper case is handled for every app by matching any
/// bundle ID nested under `bundleID`.
public struct ChosenApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    /// Kept alongside the ID so a chip still reads properly after the app is
    /// uninstalled, and so settings never have to hit the disk to draw.
    public var name: String
    /// Bundle ID prefixes that belong to this app but are not nested under its
    /// own ID.
    public var extraPrefixes: [String]
    /// Whether camera use may be pinned on this app while it is running. The
    /// system reports the camera per device rather than per process, so the
    /// only way to attribute it is "a chosen app is open". That is fair for a
    /// dedicated meeting app and wrong for a browser, which is open all day:
    /// with a browser counting, Photo Booth would read as a meeting. Only
    /// meeting detection consults this; the pause list never does.
    public var attributesCamera: Bool

    public var id: String { bundleID }

    public init(bundleID: String, name: String, extraPrefixes: [String] = [], attributesCamera: Bool = true) {
        self.bundleID = bundleID
        self.name = name
        self.extraPrefixes = extraPrefixes
        self.attributesCamera = attributesCamera
    }

    /// Settings saved before an app carried a camera rule have no key for it;
    /// they decode as counting, which is what they did at the time. An app
    /// saved with no prefixes of its own picks up whatever its meeting preset
    /// has learned since — a FaceTime chip seeded before its call daemon was
    /// known would otherwise never match.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        name = try container.decode(String.self, forKey: .name)
        attributesCamera = try container.decodeIfPresent(Bool.self, forKey: .attributesCamera) ?? true
        let saved = try container.decodeIfPresent([String].self, forKey: .extraPrefixes) ?? []
        extraPrefixes = saved.isEmpty ? ChosenApp.meetingPreset(for: bundleID)?.extraPrefixes ?? [] : saved
    }

    /// Whether a process's bundle ID belongs to this app. Only meeting
    /// detection needs this: the pause list compares against the frontmost
    /// app's own bundle ID, which is never a helper. Compared
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

public extension ChosenApp {
    /// Meeting apps worth offering up front. On first run the ones actually
    /// installed are pre-selected; every other app on the Mac is reachable
    /// through the search field, so this list only has to cover the common
    /// cases. The pause list has no equivalent — which apps should not be
    /// interrupted is personal, so it starts empty.
    static let meetingPresets: [ChosenApp] = [
        ChosenApp(bundleID: "us.zoom.xos", name: "Zoom", extraPrefixes: ["us.zoom."]),
        ChosenApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams", extraPrefixes: ["com.microsoft.teams"]),
        ChosenApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
        ChosenApp(bundleID: "com.pop.pop.app", name: "Pop", extraPrefixes: ["com.pop."]),
        ChosenApp(bundleID: "com.hnc.Discord", name: "Discord"),
        // FaceTime — and an iPhone call answered on the Mac — captures from
        // the system's call daemon, not from FaceTime.app itself.
        ChosenApp(bundleID: "com.apple.FaceTime", name: "FaceTime", extraPrefixes: ["com.apple.avconferenced"]),
        ChosenApp(bundleID: "Cisco-Systems.Spark", name: "Webex", extraPrefixes: ["com.webex."]),
        // Browsers count for the microphone — a Meet tab holding the mic is
        // a call — but not for the camera, since one is nearly always open.
        ChosenApp(bundleID: "com.google.Chrome", name: "Google Chrome", attributesCamera: false),
        ChosenApp(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", attributesCamera: false),
        ChosenApp(bundleID: "company.thebrowser.Browser", name: "Arc", attributesCamera: false),
        ChosenApp(bundleID: "com.brave.Browser", name: "Brave", attributesCamera: false),
        // Firefox captures from its main process rather than a helper.
        ChosenApp(bundleID: "org.mozilla.firefox", name: "Firefox", attributesCamera: false),
        // Safari hands capture to a shared WebKit process that does not say
        // which browser it came from, so this entry covers any WebKit browser.
        ChosenApp(
            bundleID: "com.apple.Safari", name: "Safari",
            extraPrefixes: ["com.apple.WebKit"], attributesCamera: false
        ),
    ]

    /// The meeting preset carrying the extra prefixes for `bundleID`, if there
    /// is one. Lets an app picked out of the installed-apps list inherit the
    /// sibling and helper knowledge baked into `meetingPresets`.
    static func meetingPreset(for bundleID: String) -> ChosenApp? {
        meetingPresets.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}
