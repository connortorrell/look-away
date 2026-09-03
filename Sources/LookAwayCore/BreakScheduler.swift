import Foundation

/// The 20/20/20 state machine. Owns all timing; the UI only reacts to events
/// and reads `state` for display.
@MainActor
public final class BreakScheduler {
    public enum SnoozeLength: Sendable, Equatable {
        case short
        case long
    }

    public enum State: Equatable, Sendable {
        /// `start()` has not been called.
        case stopped
        /// Waiting for the next break.
        case idle(fireAt: Date)
        /// Popup is visible and counting down.
        case breaking(remaining: Int)
        /// Popup was delayed and will return at `until`.
        case snoozed(until: Date)
        /// Reminders are off. `byUser` distinguishes a menu pause from sleep/lock.
        case paused(byUser: Bool)
    }

    public enum Event: Equatable, Sendable {
        /// Show the popup with a fresh countdown.
        case breakStarted
        /// Countdown moved to `remaining` seconds.
        case countdownTicked(remaining: Int)
        /// Countdown reached zero.
        case breakCompleted
        /// Popup should hide without completing (declined, snoozed, or paused).
        case breakDismissed
        /// Timing changed with no popup side effect (re-armed, snoozed, paused, resumed).
        case scheduleChanged
    }

    public let config: Config
    public private(set) var state: State = .stopped
    public var onEvent: (@MainActor (Event) -> Void)?

    private let clock: Timekeeper
    private var pending: ScheduledTask?

    public init(config: Config = .standard, clock: Timekeeper) {
        self.config = config
        self.clock = clock
    }

    // MARK: - Commands

    /// Begin the first work interval.
    public func start() {
        armWork()
    }

    /// Open a break immediately from any non-breaking state.
    public func breakNow() {
        if case .breaking = state { return }
        beginBreak()
    }

    /// Close the popup and start the next work interval.
    public func decline() {
        guard case .breaking = state else { return }
        emit(.breakDismissed)
        armWork()
    }

    /// Hide the popup and bring it back after the snooze length.
    public func snooze(_ length: SnoozeLength) {
        guard case .breaking = state else { return }
        cancelPending()
        emit(.breakDismissed)
        let duration = length == .short ? config.shortSnooze : config.longSnooze
        state = .snoozed(until: clock.now().addingTimeInterval(duration))
        pending = clock.schedule(after: duration) { [weak self] in self?.beginBreak() }
        emit(.scheduleChanged)
    }

    /// User turned reminders off from the menu.
    public func pause() {
        guard state != .stopped else { return }
        enterPause(byUser: true)
    }

    /// User turned reminders back on. Starts a fresh work interval.
    public func resume() {
        guard case .paused = state else { return }
        armWork()
    }

    /// System went to sleep or the screen locked. Does not override a user pause.
    public func systemDidSuspend() {
        guard state != .stopped else { return }
        if case .paused(byUser: true) = state { return }
        enterPause(byUser: false)
    }

    /// System woke or the screen unlocked. Only resumes a system-initiated pause.
    public func systemDidResume() {
        guard case .paused(byUser: false) = state else { return }
        armWork()
    }

    // MARK: - Transitions

    private func armWork() {
        cancelPending()
        state = .idle(fireAt: clock.now().addingTimeInterval(config.workInterval))
        pending = clock.schedule(after: config.workInterval) { [weak self] in self?.beginBreak() }
        emit(.scheduleChanged)
    }

    private func beginBreak() {
        cancelPending()
        state = .breaking(remaining: config.breakSeconds)
        emit(.breakStarted)
        scheduleTick()
    }

    private func scheduleTick() {
        pending = clock.schedule(after: 1) { [weak self] in self?.tick() }
    }

    private func tick() {
        guard case .breaking(let remaining) = state else { return }
        let next = remaining - 1
        if next <= 0 {
            state = .breaking(remaining: 0)
            emit(.countdownTicked(remaining: 0))
            emit(.breakCompleted)
            armWork()
        } else {
            state = .breaking(remaining: next)
            emit(.countdownTicked(remaining: next))
            scheduleTick()
        }
    }

    private func enterPause(byUser: Bool) {
        cancelPending()
        if case .breaking = state { emit(.breakDismissed) }
        state = .paused(byUser: byUser)
        emit(.scheduleChanged)
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    private func emit(_ event: Event) {
        onEvent?(event)
    }
}
