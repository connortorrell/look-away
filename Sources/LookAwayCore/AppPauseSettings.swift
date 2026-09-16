import Foundation

/// Which apps should hold reminders back simply by being the app you are in.
///
/// The sibling of `MeetingSettings`, for everything a meeting check cannot
/// cover: a game, a film, a presentation. Nothing about the microphone or the
/// camera is consulted — a full-screen game holds no devices, and asking it to
/// would be the wrong question anyway.
///
/// Opt-in, like the schedule and the meeting list: while `isEnabled` is false
/// nothing is watched at all. The list starts empty and stays that way until
/// the user picks something, since which apps should not be interrupted is a
/// personal answer rather than one worth guessing.
public struct AppPauseSettings: Codable, Equatable, Sendable {
    /// How long the app has to stay in front before it counts. Long enough
    /// that clicking through a window to reach something behind it doesn't
    /// hold anything.
    public static let settleDelay: TimeInterval = 5
    /// How long you have to be out of the app before reminders come back.
    /// Covers switching away to look something up mid-game and switching
    /// straight back, which should not land a popup on the way in.
    public static let leaveGrace: TimeInterval = 20

    public var isEnabled: Bool
    /// The apps that pause reminders, in the order the user added them.
    public var apps: [ChosenApp]

    public init(isEnabled: Bool = false, apps: [ChosenApp] = []) {
        self.isEnabled = isEnabled
        self.apps = apps
    }

    /// Switched off, with nothing chosen.
    public static let standard = AppPauseSettings()

    /// Decoded key by key, so a settings file written by an older build keeps
    /// whatever it does have instead of resetting the lot. Same reasoning as
    /// `MeetingSettings`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = AppPauseSettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? standard.isEnabled
        apps = try container.decodeIfPresent([ChosenApp].self, forKey: .apps) ?? standard.apps
    }

    /// Whether the feature is on and has something to watch for.
    public var isWatching: Bool { isEnabled && !apps.isEmpty }

    // MARK: - Reading

    public func contains(_ bundleID: String) -> Bool {
        apps.contains { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// The chosen app that `bundleID` is, if any.
    ///
    /// Matched on the bundle ID itself rather than through
    /// `ChosenApp.matches(processBundleID:)`: the frontmost app is always the
    /// app, never one of its helpers, and prefix matching would let an
    /// unrelated app with a shared prefix pause reminders.
    public func app(inFront bundleID: String?) -> ChosenApp? {
        guard isWatching, let bundleID else { return nil }
        return apps.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    // MARK: - Editing

    public mutating func add(_ app: ChosenApp) {
        guard !contains(app.bundleID) else { return }
        apps.append(app)
    }

    public mutating func remove(_ bundleID: String) {
        apps.removeAll { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}

/// Where the pause list lives between launches.
@MainActor
public protocol AppPauseSettingsStoring: AnyObject {
    func load() -> AppPauseSettings
    func save(_ settings: AppPauseSettings)
}

/// Stores the settings as JSON under a single preferences key.
@MainActor
public final class UserDefaultsAppPauseSettingsStore: AppPauseSettingsStoring {
    private let key = "appPauseSettings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppPauseSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppPauseSettings.self, from: data)
        else { return .standard }
        return settings
    }

    public func save(_ settings: AppPauseSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
