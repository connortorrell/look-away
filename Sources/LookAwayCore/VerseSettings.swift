import Foundation

/// A verse to show during a break: the words, and where they come from.
public struct Verse: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    /// "Psalm 121:1", or empty when the user didn't give one.
    public var reference: String

    public init(id: UUID = UUID(), text: String, reference: String = "") {
        self.id = id
        self.text = text
        self.reference = reference
    }
}

/// Where the popup's verse comes from.
public enum VerseSource: String, Codable, Sendable, CaseIterable {
    /// The built-in verse of the day: the same verse at every break that day.
    case dailyVerse
    /// The user's own list, one verse per break, in order.
    case myVerses
}

/// A verse to meditate on while looking away.
///
/// Opt-in, like every other setting: while `isEnabled` is false the popup is
/// exactly what it always was. The verse is meant to be read first and then
/// carried away from the screen, so the break opens with `readingTime` for
/// reading before its countdown starts, dims the verse while the countdown
/// runs, and brings it back when the break is done.
public struct VerseSettings: Codable, Equatable, Sendable {
    /// Seconds for reading the verse before the countdown starts. Added to the
    /// break, so the whole countdown is still spent looking away.
    public static let readingTime = 5
    /// How long the finished popup stays up when it has a verse to re-read,
    /// in place of the usual brief "Done".
    public static let doneLinger: TimeInterval = 4
    /// How strongly the verse shows while the countdown runs.
    public static let dimmedOpacity = 0.35
    /// Past this a verse is hard to take in at a glance. A soft limit: the
    /// settings warn, but the verse is still saved and shown.
    public static let softLimit = 280

    public var isEnabled: Bool
    public var source: VerseSource
    /// The user's verses, in the order they are shown.
    public private(set) var myVerses: [Verse]
    /// Which of `myVerses` the next break shows. Every edit keeps it pointing
    /// at the same verse where it can, so reordering doesn't lose your place.
    public private(set) var nextIndex: Int

    public init(
        isEnabled: Bool = false,
        source: VerseSource = .dailyVerse,
        myVerses: [Verse] = [],
        nextIndex: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.source = source
        self.myVerses = myVerses
        self.nextIndex = myVerses.isEmpty ? 0 : min(max(nextIndex, 0), myVerses.count - 1)
    }

    /// Switched off, on the verse of the day, with no verses of your own.
    public static let standard = VerseSettings()

    /// Decoded key by key, so a settings file written by an older build keeps
    /// whatever it does have instead of resetting the lot. Same reasoning as
    /// `AppPauseSettings`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = VerseSettings()
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? standard.isEnabled,
            source: try container.decodeIfPresent(VerseSource.self, forKey: .source) ?? standard.source,
            myVerses: try container.decodeIfPresent([Verse].self, forKey: .myVerses) ?? standard.myVerses,
            nextIndex: try container.decodeIfPresent(Int.self, forKey: .nextIndex) ?? standard.nextIndex
        )
    }

    // MARK: - Reading

    /// Whether breaks step through the user's own list. An empty list falls
    /// back to the verse of the day, which doesn't step.
    public var isRotating: Bool { isEnabled && source == .myVerses && !myVerses.isEmpty }

    /// The verse a break starting at `date` shows, or nil when switched off.
    public func verse(on date: Date, calendar: Calendar = .current) -> Verse? {
        guard isEnabled else { return nil }
        return isRotating ? myVerses[nextIndex] : DailyVerses.verse(on: date, calendar: calendar)
    }

    /// Moves on to the next of the user's verses, back to the first after the
    /// last. Called only when a break is completed, so a delayed or declined
    /// break brings the same verse back.
    public mutating func advance() {
        guard !myVerses.isEmpty else { return }
        nextIndex = (nextIndex + 1) % myVerses.count
    }

    // MARK: - Editing

    public mutating func add(_ verse: Verse) {
        myVerses.append(verse)
    }

    /// Replaces the verse with the same id, if it is still there.
    public mutating func update(_ verse: Verse) {
        guard let index = myVerses.firstIndex(where: { $0.id == verse.id }) else { return }
        myVerses[index] = verse
    }

    /// Removing the next verse makes the one after it next.
    public mutating func remove(_ id: Verse.ID) {
        keepingNext { $0.removeAll { $0.id == id } }
    }

    /// Moves a verse to `destination`, an index in the list before the move,
    /// the way SwiftUI's `move(fromOffsets:toOffset:)` counts.
    public mutating func move(_ id: Verse.ID, to destination: Int) {
        guard let source = myVerses.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(destination, 0), myVerses.count)
        keepingNext { verses in
            let verse = verses.remove(at: source)
            verses.insert(verse, at: destination > source ? destination - 1 : destination)
        }
    }

    /// Applies an edit to the list while `nextIndex` follows the verse it
    /// pointed at. When that verse is gone, whatever took its place is next,
    /// wrapping to the first when it was the last.
    private mutating func keepingNext(_ edit: (inout [Verse]) -> Void) {
        let next = myVerses.indices.contains(nextIndex) ? myVerses[nextIndex].id : nil
        edit(&myVerses)
        if let next, let index = myVerses.firstIndex(where: { $0.id == next }) {
            nextIndex = index
        } else {
            nextIndex = nextIndex < myVerses.count ? nextIndex : 0
        }
    }
}

/// Where the verse settings live between launches.
@MainActor
public protocol VerseSettingsStoring: AnyObject {
    func load() -> VerseSettings
    func save(_ settings: VerseSettings)
}

/// Stores the settings as JSON under a single preferences key.
@MainActor
public final class UserDefaultsVerseSettingsStore: VerseSettingsStoring {
    private let key = "verseSettings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> VerseSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(VerseSettings.self, from: data)
        else { return .standard }
        return settings
    }

    public func save(_ settings: VerseSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
