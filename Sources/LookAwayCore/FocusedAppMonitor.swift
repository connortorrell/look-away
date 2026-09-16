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
@MainActor
public final class FocusedAppMonitor {
    /// How often the frontmost app is read. Cheap — it is one lookup — and
    /// short enough that the delay and grace periods land accurately.
    public static let pollInterval: TimeInterval = 2

    public private(set) var isInPausingApp = false
    /// Which app is holding reminders back, for the menu to name.
    public private(set) var app: ChosenApp?
    /// Called only when `isInPausingApp` actually flips.
    public var onChange: (@MainActor (Bool) -> Void)?

    private var settings: AppPauseSettings
    private let probe: FrontmostAppProbing
    private let clock: Timekeeper
    /// Look Away's own bundle ID. Seeing ourselves in front says nothing about
    /// the app the user is really in — the settings window activates us — so
    /// those readings are skipped rather than counted as leaving.
    private let ownBundleID: String?
    private var poll: ScheduledTask?
    /// When the current run of "in the app" / "out of it" began.
    private var pendingSince: Date?

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
    /// The first reading is taken at its word: switching the feature on while
    /// already in the app is the user answering the question themselves, and
    /// there is nothing to settle.
    public func start() {
        stopPolling()
        guard settings.isWatching else {
            clearPause()
            return
        }
        check(debounced: false)
        schedulePoll()
    }

    public func stop() {
        stopPolling()
        clearPause()
    }

    /// Adopt edited settings and re-evaluate straight away. Removing the app
    /// you are in releases the hold on the spot rather than after the grace
    /// period, since the edit already answered the question.
    public func apply(settings: AppPauseSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        pendingSince = nil
        // The re-read in `start()` is most likely looking at our own settings
        // window, which says nothing about the app we were holding for. The
        // edit does: off the list means the hold is over.
        if let app, settings.app(inFront: app.bundleID) == nil { clearPause() }
        start()
    }

    // MARK: - Polling

    private func schedulePoll() {
        poll = clock.schedule(after: Self.pollInterval) { [weak self] in
            guard let self else { return }
            self.check(debounced: true)
            self.schedulePoll()
        }
    }

    private func stopPolling() {
        poll?.cancel()
        poll = nil
    }

    /// One reading, turned into an enter or a leave. A polled reading has to
    /// hold for the settle or grace period first; a reading taken because the
    /// settings changed is acted on at once.
    private func check(debounced: Bool) {
        let frontmost = probe.frontmostBundleID()
        // Our own windows are how the user talks to us, not somewhere they
        // went. Neither starts, extends nor breaks a run.
        if let frontmost, let ownBundleID,
           frontmost.caseInsensitiveCompare(ownBundleID) == .orderedSame {
            return
        }
        let found = settings.app(inFront: frontmost)
        let isInApp = found != nil
        guard isInApp != isInPausingApp else {
            // The reading agrees with where we are; drop any part-run and keep
            // the name current, since two chosen apps can follow each other
            // without ever passing through a state change.
            pendingSince = nil
            if let found { app = found }
            return
        }

        let now = clock.now()
        let since = pendingSince ?? now
        pendingSince = since
        if debounced {
            let required = isInApp ? AppPauseSettings.settleDelay : AppPauseSettings.leaveGrace
            guard now.timeIntervalSince(since) >= required else { return }
        }

        pendingSince = nil
        isInPausingApp = isInApp
        app = found
        onChange?(isInApp)
    }

    private func clearPause() {
        pendingSince = nil
        app = nil
        guard isInPausingApp else { return }
        isInPausingApp = false
        onChange?(false)
    }
}
