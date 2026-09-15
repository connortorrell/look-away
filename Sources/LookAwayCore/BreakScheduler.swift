import Foundation

/// The 20/20/20 state machine. Owns all timing; the UI only reacts to events
/// and reads `state` for display.
@MainActor
public final class BreakScheduler {
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
        /// The clock is outside the user's schedule. `until` is the next
        /// opening, or nil when no day is active.
        case offSchedule(until: Date?)
        /// A meeting is in progress, so the popup is held back — but the
        /// countdown carries on underneath it. `dueAt` is the moment the break
        /// is owed, and it can be in the past: a break that came due mid-call
        /// is taken as soon as the call ends, rather than starting the wait
        /// over and leaving you a full interval short of a rest you had earned.
        case inMeeting(dueAt: Date)
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
    public private(set) var schedule: Schedule
    public var onEvent: (@MainActor (Event) -> Void)?

    private let clock: Timekeeper
    private let calendar: Calendar
    private var pending: ScheduledTask?
    /// Set by `meetingDidStart()` / `meetingDidEnd()`. Consulted whenever the
    /// next wait is armed, so a meeting outlasts any single transition.
    private var isInMeeting = false

    public init(
        config: Config = .standard,
        schedule: Schedule = .standard,
        clock: Timekeeper,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.config = config
        self.schedule = schedule
        self.clock = clock
        self.calendar = calendar
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

    /// Hide the popup and bring it back after the snooze interval. A break the
    /// user opened outside the schedule comes back regardless of the window,
    /// since `breakNow()` already bypassed it on their behalf.
    public func snooze() {
        guard case .breaking = state else { return }
        cancelPending()
        emit(.breakDismissed)
        let now = clock.now()
        let until = now.addingTimeInterval(config.snoozeInterval)
        // A break delayed while on a call is still a call, and that is the more
        // useful thing to be told: "delayed" suggests the wait is the only
        // reason nothing is happening. The popup is held either way, and the
        // delay's own deadline carries over as the one the meeting owes.
        if isInMeeting {
            state = .inMeeting(dueAt: until)
            emit(.scheduleChanged)
            return
        }
        state = .snoozed(until: until)
        if schedule.allows(now, calendar: calendar) {
            wait(until: until)
        } else {
            pending = clock.schedule(after: config.snoozeInterval) { [weak self] in self?.beginBreak() }
        }
        emit(.scheduleChanged)
    }

    /// Adopt an edited schedule and re-check the current wait against it. The
    /// wait keeps its target, so editing does not restart the work interval.
    /// An in-progress break is left alone; the new schedule applies when it closes.
    public func apply(schedule: Schedule) {
        self.schedule = schedule
        reevaluate()
    }

    /// The system clock or time zone changed. Window edges are recomputed and
    /// a target that has already passed fires straight away.
    public func clockDidChange() {
        reevaluate()
    }

    /// A meeting started. Holds the popup back and closes one already up — the
    /// whole point is not to be interrupted on a call — while keeping the
    /// deadline the countdown was working towards, so time on the call still
    /// counts. A user pause outranks this and is left alone.
    public func meetingDidStart() {
        isInMeeting = true
        guard state != .stopped else { return }
        switch state {
        case .paused, .inMeeting:
            return
        // Outside the scheduled hours nothing is pending anyway, and that hold
        // already outlasts the call.
        case .offSchedule:
            return
        case .idle, .breaking, .snoozed, .stopped:
            break
        }
        let dueAt = currentDeadline()
        cancelPending()
        if case .breaking = state { emit(.breakDismissed) }
        state = .inMeeting(dueAt: dueAt)
        emit(.scheduleChanged)
    }

    /// When the break the current state was heading towards is owed.
    private func currentDeadline() -> Date {
        switch state {
        case .idle(let fireAt):
            return fireAt
        case .snoozed(let until):
            return until
        // A break cut short by the call was never taken, so it is owed the
        // moment the call ends.
        case .breaking:
            return clock.now()
        case .stopped, .paused, .offSchedule, .inMeeting:
            return clock.now().addingTimeInterval(config.workInterval)
        }
    }

    /// The meeting ended. The countdown ran through the call, so a break that
    /// came due during it is taken now; otherwise the remainder plays out.
    public func meetingDidEnd() {
        isInMeeting = false
        guard case .inMeeting(let dueAt) = state else { return }
        guard schedule.allows(clock.now(), calendar: calendar) else {
            enterOffSchedule()
            return
        }
        if dueAt <= clock.now() {
            beginBreak()
        } else {
            scheduleWork(dueAt: dueAt)
        }
    }

    /// Meeting detection was switched off, so drop any hold it was placing.
    public func meetingDetectionDidStop() {
        meetingDidEnd()
        isInMeeting = false
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

    /// Start the wait over, a full interval from now.
    private func armWork() {
        scheduleWork(dueAt: clock.now().addingTimeInterval(config.workInterval))
    }

    /// Wait for the break owed at `dueAt`, which may be less than a full
    /// interval away when a countdown is being picked back up mid-flight.
    private func scheduleWork(dueAt: Date) {
        cancelPending()
        if isInMeeting {
            state = .inMeeting(dueAt: dueAt)
            emit(.scheduleChanged)
            return
        }
        let now = clock.now()
        guard schedule.allows(now, calendar: calendar) else {
            enterOffSchedule()
            return
        }
        state = .idle(fireAt: dueAt)
        wait(until: dueAt)
        emit(.scheduleChanged)
    }

    /// Sleep until `target`, or until the schedule window closes if that comes
    /// first. Either way `evaluate()` decides what the wake-up means.
    private func wait(until target: Date) {
        cancelPending()
        let now = clock.now()
        let close = schedule.currentWindowEnd(at: now, calendar: calendar) ?? target
        let wake = min(target, close)
        pending = clock.schedule(after: wake.timeIntervalSince(now)) { [weak self] in self?.evaluate() }
    }

    /// Re-check a running wait after the schedule or the clock changed. States
    /// without a timer have nothing to re-check.
    private func reevaluate() {
        switch state {
        case .stopped, .paused, .breaking, .inMeeting:
            return
        case .idle, .snoozed, .offSchedule:
            cancelPending()
            evaluate()
        }
    }

    /// A timer woke up, or something changed under it: decide from wall time.
    /// Emits exactly one event.
    private func evaluate() {
        let now = clock.now()
        switch state {
        case .idle(let target), .snoozed(let target):
            if isInMeeting {
                cancelPending()
                state = .inMeeting(dueAt: target)
                emit(.scheduleChanged)
                return
            }
            guard schedule.allows(now, calendar: calendar) else {
                enterOffSchedule()
                return
            }
            if target > now {
                // Still inside a window (the one that closed was followed by
                // another), so keep waiting for the same target.
                wait(until: target)
                emit(.scheduleChanged)
            } else {
                beginBreak()
            }
        case .offSchedule:
            armWork()
        case .stopped, .paused, .breaking, .inMeeting:
            break
        }
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

    /// Hold until the schedule opens again. Re-arms itself at that moment.
    private func enterOffSchedule() {
        cancelPending()
        let now = clock.now()
        let opensAt = schedule.nextOpening(after: now, calendar: calendar)
        state = .offSchedule(until: opensAt)
        if let opensAt {
            pending = clock.schedule(after: opensAt.timeIntervalSince(now)) { [weak self] in self?.armWork() }
        }
        emit(.scheduleChanged)
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
