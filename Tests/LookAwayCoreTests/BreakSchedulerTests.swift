import Foundation
import Testing
@testable import LookAwayCore

@MainActor
struct BreakSchedulerTests {
    // Short durations keep the arithmetic readable: 100s work, 5s break, 10s / 20s snooze.
    let config = Config(workInterval: 100, breakSeconds: 5, shortSnooze: 10, longSnooze: 20)
    let clock = FakeTimekeeper()
    let scheduler: BreakScheduler
    let events: EventLog

    @MainActor final class EventLog {
        var all: [BreakScheduler.Event] = []
        func clear() { all.removeAll() }
    }

    init() {
        scheduler = BreakScheduler(config: config, clock: clock)
        let log = EventLog()
        events = log
        scheduler.onEvent = { log.all.append($0) }
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    // MARK: Basic cycle

    @Test func startArmsWorkInterval() {
        scheduler.start()
        #expect(scheduler.state == .idle(fireAt: date(100)))
        #expect(events.all == [.scheduleChanged])
    }

    @Test func breakStartsWhenWorkIntervalElapses() {
        scheduler.start()
        clock.advance(by: 99)
        #expect(scheduler.state == .idle(fireAt: date(100)))
        clock.advance(by: 1)
        #expect(scheduler.state == .breaking(remaining: 5))
        #expect(events.all.last == .breakStarted)
    }

    @Test func countdownTicksEverySecondAndCompletes() {
        scheduler.start()
        clock.advance(by: 100)
        events.clear()

        clock.advance(by: 1)
        #expect(scheduler.state == .breaking(remaining: 4))
        clock.advance(by: 3)
        #expect(scheduler.state == .breaking(remaining: 1))
        #expect(events.all == [
            .countdownTicked(remaining: 4), .countdownTicked(remaining: 3),
            .countdownTicked(remaining: 2), .countdownTicked(remaining: 1),
        ])

        events.clear()
        clock.advance(by: 1)
        #expect(events.all == [.countdownTicked(remaining: 0), .breakCompleted, .scheduleChanged])
        // Next break is 100s after the break *closed* (t = 105), not after it opened.
        #expect(scheduler.state == .idle(fireAt: date(205)))
    }

    @Test func nextBreakFollowsCompletedBreak() {
        scheduler.start()
        clock.advance(by: 105)
        events.clear()
        clock.advance(by: 100)
        #expect(scheduler.state == .breaking(remaining: 5))
        #expect(events.all == [.breakStarted])
    }

    // MARK: Decline

    @Test func declineHidesAndReArmsFromNow() {
        scheduler.start()
        clock.advance(by: 102) // 2s into the break
        events.clear()

        scheduler.decline()
        #expect(events.all == [.breakDismissed, .scheduleChanged])
        #expect(scheduler.state == .idle(fireAt: date(202)))

        // The old tick timer must be gone; nothing fires until 202.
        clock.advance(by: 99)
        #expect(scheduler.state == .idle(fireAt: date(202)))
        clock.advance(by: 1)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    @Test func declineIsIgnoredOutsideABreak() {
        scheduler.start()
        events.clear()
        scheduler.decline()
        #expect(events.all.isEmpty)
        #expect(scheduler.state == .idle(fireAt: date(100)))
    }

    // MARK: Snooze

    @Test func shortSnoozeReturnsWithFreshCountdown() {
        scheduler.start()
        clock.advance(by: 103) // 3s into the break, 2 remaining
        events.clear()

        scheduler.snooze(.short)
        #expect(events.all == [.breakDismissed, .scheduleChanged])
        #expect(scheduler.state == .snoozed(until: date(113)))

        clock.advance(by: 9)
        #expect(scheduler.state == .snoozed(until: date(113)))
        clock.advance(by: 1)
        #expect(scheduler.state == .breaking(remaining: 5))
        #expect(events.all.last == .breakStarted)
    }

    @Test func longSnoozeUsesLongDuration() {
        scheduler.start()
        clock.advance(by: 100)
        scheduler.snooze(.long)
        #expect(scheduler.state == .snoozed(until: date(120)))
        clock.advance(by: 20)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    @Test func snoozeDoesNotStartWorkInterval() {
        scheduler.start()
        clock.advance(by: 100)
        scheduler.snooze(.short)
        clock.advance(by: 10) // popup back at 110
        clock.advance(by: 5)  // completes at 115
        // Work interval anchored to completion at 115, not to the snooze at 100.
        #expect(scheduler.state == .idle(fireAt: date(215)))
    }

    @Test func snoozesCanChain() {
        scheduler.start()
        clock.advance(by: 100)
        scheduler.snooze(.short)
        clock.advance(by: 10)
        #expect(scheduler.state == .breaking(remaining: 5))
        scheduler.snooze(.long)
        #expect(scheduler.state == .snoozed(until: date(130)))
        clock.advance(by: 20)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    @Test func snoozeIsIgnoredOutsideABreak() {
        scheduler.start()
        events.clear()
        scheduler.snooze(.short)
        #expect(events.all.isEmpty)
        #expect(clock.pendingCount == 1)
    }

    // MARK: Pause / resume

    @Test func pauseDuringBreakDismissesPopup() {
        scheduler.start()
        clock.advance(by: 101)
        events.clear()
        scheduler.pause()
        #expect(events.all == [.breakDismissed, .scheduleChanged])
        #expect(scheduler.state == .paused(byUser: true))
        #expect(clock.pendingCount == 0)
    }

    @Test func pauseWhileIdleCancelsTimer() {
        scheduler.start()
        events.clear()
        scheduler.pause()
        #expect(events.all == [.scheduleChanged])
        #expect(clock.pendingCount == 0)
        clock.advance(by: 1000)
        #expect(scheduler.state == .paused(byUser: true))
    }

    @Test func pauseWhileSnoozedCancelsReturn() {
        scheduler.start()
        clock.advance(by: 100)
        scheduler.snooze(.short)
        scheduler.pause()
        clock.advance(by: 1000)
        #expect(scheduler.state == .paused(byUser: true))
    }

    @Test func resumeStartsFreshWorkInterval() {
        scheduler.start()
        clock.advance(by: 50)
        scheduler.pause()
        clock.advance(by: 30)
        scheduler.resume()
        #expect(scheduler.state == .idle(fireAt: date(180)))
    }

    @Test func resumeIsIgnoredWhenNotPaused() {
        scheduler.start()
        events.clear()
        scheduler.resume()
        #expect(events.all.isEmpty)
    }

    @Test func pauseBeforeStartIsIgnored() {
        scheduler.pause()
        #expect(scheduler.state == .stopped)
    }

    // MARK: System sleep / lock

    @Test func systemSuspendPausesAndResumeReArms() {
        scheduler.start()
        clock.advance(by: 60)
        events.clear()

        scheduler.systemDidSuspend()
        #expect(scheduler.state == .paused(byUser: false))
        #expect(events.all == [.scheduleChanged])

        clock.advance(by: 3600)
        scheduler.systemDidResume()
        #expect(scheduler.state == .idle(fireAt: date(3760)))
    }

    @Test func systemSuspendDuringBreakDismissesPopup() {
        scheduler.start()
        clock.advance(by: 102)
        events.clear()
        scheduler.systemDidSuspend()
        #expect(events.all == [.breakDismissed, .scheduleChanged])
    }

    @Test func systemResumeDoesNotOverrideUserPause() {
        scheduler.start()
        scheduler.pause()
        scheduler.systemDidSuspend()
        #expect(scheduler.state == .paused(byUser: true))
        scheduler.systemDidResume()
        #expect(scheduler.state == .paused(byUser: true))
    }

    @Test func userResumeClearsSystemPause() {
        scheduler.start()
        scheduler.systemDidSuspend()
        scheduler.resume()
        #expect(scheduler.state == .idle(fireAt: date(100)))
    }

    @Test func systemEventsBeforeStartAreIgnored() {
        scheduler.systemDidSuspend()
        #expect(scheduler.state == .stopped)
        scheduler.systemDidResume()
        #expect(scheduler.state == .stopped)
    }

    // MARK: Break now

    @Test func breakNowFromIdleStartsBreak() {
        scheduler.start()
        clock.advance(by: 30)
        events.clear()
        scheduler.breakNow()
        #expect(scheduler.state == .breaking(remaining: 5))
        #expect(events.all == [.breakStarted])
        // Old work timer cancelled: only the tick timer remains.
        #expect(clock.pendingCount == 1)
        clock.advance(by: 5)
        #expect(scheduler.state == .idle(fireAt: date(135)))
    }

    @Test func breakNowFromPausedStartsBreakAndReArmsAfter() {
        scheduler.start()
        scheduler.pause()
        scheduler.breakNow()
        #expect(scheduler.state == .breaking(remaining: 5))
        clock.advance(by: 5)
        #expect(scheduler.state == .idle(fireAt: date(105)))
    }

    @Test func breakNowDuringBreakIsIgnored() {
        scheduler.start()
        clock.advance(by: 102)
        events.clear()
        scheduler.breakNow()
        #expect(scheduler.state == .breaking(remaining: 3))
        #expect(events.all.isEmpty)
    }
}
