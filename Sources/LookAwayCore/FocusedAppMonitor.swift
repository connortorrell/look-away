import Foundation

/// Reads which app is in front. A protocol so the monitor can be tested
/// without switching apps for real.
@MainActor
public protocol FrontmostAppProbing: AnyObject {
    /// Bundle ID of the app the user is currently in, or nil when there isn't
    /// one — the Finder desktop, a login window, a screen saver.
    func frontmostBundleID() -> String?
}

/// Watches for one of the chosen apps coming to the front, and reports when
/// you enter and leave it.
///
/// Deliberately the dumbest possible signal: the app you are in. No device is
/// consulted, because the apps this list is for — games, players, slide decks
/// — hold no microphone and no camera, so the meeting check can never see them.
///
/// Debounced at both ends like `MeetingMonitor`, for the same reason: a
/// reading has to hold for `settleDelay` before it counts and stay clear for
/// `leaveGrace` before reminders come back, so clicking through a window or
/// glancing at another app mid-game doesn't flip anything. Nothing is polled
/// at all while the feature is off.
///
/// Polled, rather than fed by `NSWorkspace`'s activation notifications, so it
/// works the same way as `MeetingMonitor` and this module stays AppKit-free.
@MainActor
public final class FocusedAppMonitor {
    /// How often the frontmost app is read. Cheap — it is one lookup — and
    /// short enough that the delay and grace periods land accurately.
    public static let pollInterval: TimeInterval = 2

    public var isInPausingApp: Bool { core.isActive }
    /// Which app is holding reminders back, for the menu to name.
    public var app: ChosenApp? { core.reading }
    /// Called only when `isInPausingApp` actually flips.
    public var onChange: (@MainActor (Bool) -> Void)? {
        get { core.onChange }
        set { core.onChange = newValue }
    }

    private var settings: AppPauseSettings
    private let probe: FrontmostAppProbing
    private let clock: Timekeeper
    /// Look Away's own bundle ID. Seeing ourselves in front says nothing about
    /// the app the user is really in — the settings window activates us — so
    /// those readings are skipped rather than counted as leaving.
    private let ownBundleID: String?
    private lazy var core = DebouncedMonitor<ChosenApp>(
        pollInterval: Self.pollInterval,
        clock: clock,
        sample: { [unowned self] in self.sample() },
        delay: { entering in
            entering ? AppPauseSettings.settleDelay : AppPauseSettings.leaveGrace
        }
    )

    public init(
        settings: AppPauseSettings = .standard,
        probe: FrontmostAppProbing,
        clock: Timekeeper,
        ownBundleID: String? = nil
    ) {
        self.settings = settings
        self.probe = probe
        self.clock = clock
        self.ownBundleID = ownBundleID
    }

    /// Begin watching, if the feature is on and something is chosen.
    ///
    /// The first reading is taken at its word: at launch the app already in
    /// front is where the user is, and there is nothing to settle.
    public func start() {
        guard settings.isWatching else {
            core.stop()
            return
        }
        core.start()
    }

    public func stop() {
        core.stop()
    }

    /// Adopt edited settings and re-evaluate straight away. Removing the app
    /// you are in releases the hold on the spot rather than after the grace
    /// period, since the edit has already answered the question.
    public func apply(settings: AppPauseSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        // The re-read in `start()` is most likely looking at our own settings
        // window, which says nothing about the app we were holding for. The
        // edit does: off the list means the hold is over.
        if let app, settings.app(inFront: app.bundleID) == nil { core.stop() }
        start()
    }

    /// The Mac is going to sleep or the screen is locking. Nothing is polled
    /// until it comes back; what was known stands until then.
    public func systemDidSuspend() {
        core.suspend()
    }

    /// Woke or unlocked. The app in front may be anything by now, so the
    /// current reading is taken as it is, like a start, rather than waiting
    /// out a grace period for a game that was quit hours ago.
    public func systemDidResume() {
        start()
    }

    private func sample() -> DebouncedMonitor<ChosenApp>.Sample {
        let frontmost = probe.frontmostBundleID()
        // Our own windows are how the user talks to us, not somewhere they
        // went.
        if let frontmost, let ownBundleID,
           frontmost.caseInsensitiveCompare(ownBundleID) == .orderedSame {
            return .disregarded
        }
        return .init(settings.app(inFront: frontmost))
    }
}
