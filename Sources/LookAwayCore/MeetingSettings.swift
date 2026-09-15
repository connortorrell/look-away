import Foundation

/// Whether — and how — reminders should get out of the way during meetings.
/// Opt-in, like the schedule: while `isEnabled` is false nothing is watched and
/// no detection work happens at all.
public struct MeetingSettings: Codable, Equatable, Sendable {
    /// How long a signal has to hold before it counts as a meeting. Guards
    /// against a notification chime or a quick "can you hear me" grabbing the
    /// microphone for a second.
    public static let detectionDelayChoices: [TimeInterval] = [0, 5, 15, 30, 60]

    public var isEnabled: Bool
    /// The apps that count as a meeting, in the order the user added them.
    public var apps: [MeetingApp]
    public var detectionDelay: TimeInterval
    /// How long the signal has to stay clear before reminders come back. Keeps
    /// a spell on mute, or a moment between two back-to-back calls, from
    /// letting a popup through.
    public var endGrace: TimeInterval
    /// Count a selected app using the camera, not just the microphone. Catches
    /// the case of sitting muted but on video.
    public var countsCamera: Bool
    /// Count a selected app *playing* audio as well as capturing it. Catches a
    /// listen-only call, where the mic is released and the camera is off.
    ///
    /// Off by default, and deliberately: browsers and chat apps play audio all
    /// day for videos and notification sounds, so this trades false negatives
    /// for false positives rather than removing them.
    public var countsAudioOutput: Bool
    /// Whether the installed meeting apps have already been offered once. Kept
    /// so clearing the list stays cleared instead of filling back in.
    public var hasSeededApps: Bool

    public init(
        isEnabled: Bool = false,
        apps: [MeetingApp] = [],
        detectionDelay: TimeInterval = 15,
        endGrace: TimeInterval = 30,
        countsCamera: Bool = true,
        countsAudioOutput: Bool = false,
        hasSeededApps: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.apps = apps
        self.detectionDelay = detectionDelay
        self.endGrace = endGrace
        self.countsCamera = countsCamera
        self.countsAudioOutput = countsAudioOutput
        self.hasSeededApps = hasSeededApps
    }

    /// Switched off, with no apps chosen yet. `seedApps(installed:)` fills the
    /// list in the first time the panel is opened.
    public static let standard = MeetingSettings()

    /// Decoded key by key, falling back to the default for anything missing.
    /// The synthesized decoder would throw on a key that a settings file
    /// written by an older build does not have, which would quietly reset
    /// every other setting along with it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = MeetingSettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? standard.isEnabled
        apps = try container.decodeIfPresent([MeetingApp].self, forKey: .apps) ?? standard.apps
        detectionDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .detectionDelay) ?? standard.detectionDelay
        endGrace = try container.decodeIfPresent(TimeInterval.self, forKey: .endGrace) ?? standard.endGrace
        countsCamera = try container.decodeIfPresent(Bool.self, forKey: .countsCamera) ?? standard.countsCamera
        countsAudioOutput = try container.decodeIfPresent(Bool.self, forKey: .countsAudioOutput) ?? standard.countsAudioOutput
        hasSeededApps = try container.decodeIfPresent(Bool.self, forKey: .hasSeededApps) ?? standard.hasSeededApps
    }

    // MARK: - Reading

    public func contains(_ bundleID: String) -> Bool {
        apps.contains { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// Whether any chosen app owns `processBundleID`.
    public func app(owning processBundleID: String) -> MeetingApp? {
        apps.first { $0.matches(processBundleID: processBundleID) }
    }

    // MARK: - Editing

    public mutating func add(_ app: MeetingApp) {
        guard !contains(app.bundleID) else { return }
        // Prefer the preset's prefixes: an app picked from the installed list
        // only knows its own bundle ID, and Zoom's capture process is a sibling.
        var app = app
        if let preset = MeetingApp.preset(for: app.bundleID), app.extraPrefixes.isEmpty {
            app.extraPrefixes = preset.extraPrefixes
        }
        apps.append(app)
    }

    public mutating func remove(_ bundleID: String) {
        apps.removeAll { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// Fills the list with whichever presets are actually installed, so turning
    /// the feature on already knows about the user's meeting apps. Happens once
    /// only. Returns whether anything changed.
    public mutating func seedApps(installed: Set<String>) -> Bool {
        guard !hasSeededApps else { return false }
        hasSeededApps = true
        let matched = MeetingApp.presets.filter { preset in
            installed.contains { $0.caseInsensitiveCompare(preset.bundleID) == .orderedSame }
        }
        apps = matched
        return true
    }
}

/// Where the meeting settings live between launches.
@MainActor
public protocol MeetingSettingsStoring: AnyObject {
    func load() -> MeetingSettings
    func save(_ settings: MeetingSettings)
}

/// Stores the settings as JSON under a single preferences key.
@MainActor
public final class UserDefaultsMeetingSettingsStore: MeetingSettingsStoring {
    private let key = "meetingSettings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> MeetingSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(MeetingSettings.self, from: data)
        else { return .standard }
        return settings
    }

    public func save(_ settings: MeetingSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
