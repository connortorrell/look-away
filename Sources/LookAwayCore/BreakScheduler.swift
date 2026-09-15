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
        if isInMeeting {
            // A break delayed while on a call is still a call, and that is the
            // more useful thing to be told: "delayed" suggests the wait is the
            // only reason nothing is happening. The popup is held either way,
            // and the delay's own deadline carries over as the one the meeting
            // owes.
            holdForMeeting(dueAt: until)
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
    /// counts. A user pause, the schedule's own hold, and a scheduler that has
    /// not started yet are left alone: the flag carries the meeting into
    /// whatever is armed next.
    public func meetingDidStart() {
        isInMeeting = true
        let dueAt: Date
        switch state {
        case .idle(let fireAt):
            dueAt = fireAt
        case .snoozed(let until):
            dueAt = until
        case .breaking:
            // Cut short, so never taken: owed the moment the call ends.
            dueAt = clock.now()
        case .stopped, .paused, .offSchedule, .inMeeting:
            return
        }
        cancelPending()
        if case .breaking = state { emit(.breakDismissed) }
        holdForMeeting(dueAt: dueAt)
    }

    /// The meeting ended. The countdown ran through the call, so a break that
    /// came due during it opens now; otherwise the remainder plays out.
    public func meetingDidEnd() {
        isInMeeting = false
        guard case .inMeeting(let dueAt) = state else { return }
        waitForBreak(dueAt: dueAt)
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

    /// A fresh work interval from now.
    private func armWork() {
        waitForBreak(dueAt: clock.now().addingTimeInterval(config.workInterval))
    }

    /// Head for the break owed at `dueAt`: a full interval away from
    /// `armWork()`, or whatever was left when a meeting ended. The schedule's
    /// hold wins; a meeting holds the popup but keeps `dueAt`; a deadline that
    /// has already passed opens the break straight away.
    private func waitForBreak(dueAt: Date) {
        cancelPending()
        let now = clock.now()
        guard schedule.allows(now, calendar: calendar) else {
            enterOffSchedule()
            return
        }
        if isInMeeting {
            holdForMeeting(dueAt: dueAt)
            return
        }
        guard dueAt > now else {
            beginBreak()
            return
        }
        state = .idle(fireAt: dueAt)
        wait(until: dueAt)
        emit(.scheduleChanged)
    }

    /// Hold the popup for the meeting while the countdown runs on towards
    /// `dueAt`. Nothing is armed for the break itself — `meetingDidEnd()`
    /// reads the clock — but the schedule closing still has to be noticed, so
    /// that edge is waited for as usual.
    private func holdForMeeting(dueAt: Date) {
        cancelPending()
        state = .inMeeting(dueAt: dueAt)
        let now = clock.now()
        if let close = schedule.currentWindowEnd(at: now, calendar: calendar) {
            pending = clock.schedule(after: close.timeIntervalSince(now)) { [weak self] in self?.evaluate() }
        }
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
        case .stopped, .paused, .breaking:
            return
        case .idle, .snoozed, .offSchedule, .inMeeting:
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
        case .inMeeting(let dueAt):
            // The window closed under the hold, or the schedule or clock
            // changed. The schedule's hold wins; otherwise the meeting's hold
            // and its deadline stand, against whatever the window edge is now.
            guard schedule.allows(now, calendar: calendar) else {
                enterOffSchedule()
                return
            }
            holdForMeeting(dueAt: dueAt)
        case .offSchedule:
            armWork()
        case .stopped, .paused, .breaking:
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
