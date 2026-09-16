import Foundation

/// Polls a reading and turns it into a debounced on/off state: a reading has
/// to hold for the enter delay before the state flips on, and stay clear for
/// the leave delay before it flips off. The monitors built on it say what is
/// read and how long each side has to hold.
///
/// Both detectors in the app work this way for the same reason: their raw
/// signals are jumpy — apps grab and release the microphone around joining
/// and muting, and clicking through a window puts another app in front for a
/// moment — so one polled reading is never acted on by itself.
@MainActor
public final class DebouncedMonitor<Reading: Sendable> {
    /// What one poll saw.
    public enum Sample {
        /// Nothing of interest. Counts towards leaving.
        case absent
        /// Something of interest. Counts towards entering, and keeps `reading`
        /// current while already in.
        case present(Reading)
        /// A reading that says nothing about where we are. Neither starts,
        /// extends nor breaks a run; the poll simply moves on.
        case disregarded

        public init(_ reading: Reading?) {
            self = reading.map(Sample.present) ?? .absent
        }
    }

    public private(set) var isActive = false
    /// The latest reading of interest, for the menu to name.
    public private(set) var reading: Reading?
    /// Called only when `isActive` actually flips.
    public var onChange: (@MainActor (Bool) -> Void)?

    private let pollInterval: TimeInterval
    private let clock: Timekeeper
    private let sample: @MainActor () -> Sample
    /// Read at check time, so a delay that lives in mutable settings is
    /// always the current one.
    private let delay: @MainActor (_ entering: Bool) -> TimeInterval
    private var poll: ScheduledTask?
    /// When the current run of readings disagreeing with `isActive` began.
    private var pendingSince: Date?

    public init(
        pollInterval: TimeInterval,
        clock: Timekeeper,
        sample: @escaping @MainActor () -> Sample,
        delay: @escaping @MainActor (_ entering: Bool) -> TimeInterval
    ) {
        self.pollInterval = pollInterval
        self.clock = clock
        self.sample = sample
        self.delay = delay
    }

    /// Take a reading now and keep polling. The first reading is acted on at
    /// once: at start, after an edit, or on waking, the current state is the
    /// answer rather than a change to be waited out. Polled readings are
    /// debounced.
    public func start() {
        stopPolling()
        pendingSince = nil
        check(debounced: false)
        schedulePoll()
    }

    /// Stop polling but keep what is known: the Mac is going to sleep, and
    /// what was true stands until it wakes and `start()` reads again.
    public func suspend() {
        stopPolling()
        pendingSince = nil
    }

    /// Stop polling and drop any hold, reporting the end if there was one.
    public func stop() {
        stopPolling()
        pendingSince = nil
        reading = nil
        guard isActive else { return }
        isActive = false
        onChange?(false)
    }

    // MARK: - Polling

    private func schedulePoll() {
        poll = clock.schedule(after: pollInterval) { [weak self] in
            guard let self else { return }
            self.check(debounced: true)
            self.schedulePoll()
        }
    }

    private func stopPolling() {
        poll?.cancel()
        poll = nil
    }

    private func check(debounced: Bool) {
        let found: Reading?
        switch sample() {
        case .disregarded: return
        case .absent: found = nil
        case .present(let reading): found = reading
        }

        let seen = found != nil
        guard seen != isActive else {
            // The reading agrees with where we are; drop any part-run and keep
            // the reading current, since two apps of interest can follow each
            // other without ever passing through a state change.
            pendingSince = nil
            if let found { reading = found }
            return
        }

        let now = clock.now()
        let since = pendingSince ?? now
        pendingSince = since
        if debounced, now.timeIntervalSince(since) < delay(seen) { return }

        pendingSince = nil
        isActive = seen
        reading = found
        onChange?(seen)
    }
}
