import Foundation
import Testing
@testable import LookAwayCore

/// How the scheduler behaves while a meeting is on. The countdown keeps
/// running through a call; only the popup is held back.
@MainActor
struct MeetingBreakSchedulerTests {
    let config = Config(workInterval: 100, breakSeconds: 5, snoozeInterval: 10)
    let clock = FakeTimekeeper()

    /// Seconds since the fake clock's start.
    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private func makeScheduler(schedule: Schedule = .standard) -> BreakScheduler {
        BreakScheduler(config: config, schedule: schedule, clock: clock)
    }

    // MARK: Holding

    @Test func aMeetingHoldsThePopupButKeepsTheDeadline() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 30)
        scheduler.meetingDidStart()
        #expect(scheduler.state == .inMeeting(dueAt: at(100)))

        // Well past when the popup would have opened.
        clock.advance(by: 500)
        #expect(scheduler.state == .inMeeting(dueAt: at(100)))
    }

    /// The headline case: a long call swallows the break, and it is owed the
    /// moment the call ends rather than a fresh interval later.
    @Test func aBreakThatCameDueDuringALongCallOpensAsSoonAsItEnds() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 30)
        scheduler.meetingDidStart()
        clock.advance(by: 3_600) // an hour on the call

        scheduler.meetingDidEnd()
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    /// The other case: a call shorter than the time left just carries on
    /// counting, so the break lands when it always would have.
    @Test func aShortCallLetsTheRemainderPlayOut() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 30) // 70 left
        scheduler.meetingDidStart()
        clock.advance(by: 20) // a 20 second call
        scheduler.meetingDidEnd()

        // Still due at the original moment, not 100 seconds from now.
        #expect(scheduler.state == .idle(fireAt: at(100)))

        clock.advance(by: 49)
        #expect(scheduler.state == .idle(fireAt: at(100)))
        clock.advance(by: 1)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    /// Time on the call counts towards the break, so a call longer than the
    /// remainder still only owes one break.
    @Test func onlyOneBreakIsOwedAfterALongCall() {
        let scheduler = makeScheduler()
        var starts = 0
        scheduler.onEvent = { if $0 == .breakStarted { starts += 1 } }
        scheduler.start()
        scheduler.meetingDidStart()
        clock.advance(by: 1_000)
        scheduler.meetingDidEnd()
        #expect(starts == 1)

        // And the one after it is a full interval later.
        #expect(scheduler.state == .breaking(remaining: 5))
        clock.advance(by: 5) // finish the break
        #expect(scheduler.state == .idle(fireAt: at(1_005 + 100)))
    }

    /// A break armed before the call has its timer land mid-call; it must be
    /// held and then owed, not dropped.
    @Test func aBreakArrivingDuringAMeetingIsOwedAtTheEnd() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 50)
        scheduler.meetingDidStart()
        clock.advance(by: 100) // the timer's moment passes on the call
        #expect(scheduler.state == .inMeeting(dueAt: at(100)))

        scheduler.meetingDidEnd()
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    // MARK: Interrupted breaks

    /// A break cut short by a call was never taken, so it is owed straight
    /// after — not an interval later.
    @Test func aMeetingStartingMidBreakDismissesThePopupAndReopensAfter() {
        let scheduler = makeScheduler()
        var events: [BreakScheduler.Event] = []
        scheduler.onEvent = { events.append($0) }
        scheduler.start()
        clock.advance(by: 100)
        #expect(scheduler.state == .breaking(remaining: 5))

        scheduler.meetingDidStart()
        #expect(scheduler.state == .inMeeting(dueAt: at(100)))
        #expect(events.contains(.breakDismissed))

        clock.advance(by: 900)
        scheduler.meetingDidEnd()
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    @Test func aMeetingDuringASnoozeKeepsTheSnoozeDeadline() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 100)
        scheduler.snooze()
        #expect(scheduler.state == .snoozed(until: at(110)))

        scheduler.meetingDidStart()
        #expect(scheduler.state == .inMeeting(dueAt: at(110)))

        clock.advance(by: 5)
        scheduler.meetingDidEnd()
        #expect(scheduler.state == .idle(fireAt: at(110)))
        clock.advance(by: 5)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    /// Delaying a break taken by hand during a call has to keep reading as a
    /// meeting. Detection only reports a meeting when one starts, so nothing
    /// would come along afterwards to correct a "delayed" state.
    @Test func delayingDuringAMeetingStillReadsAsAMeeting() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.meetingDidStart()
        scheduler.breakNow()
        #expect(scheduler.state == .breaking(remaining: 5))

        scheduler.snooze()
        #expect(scheduler.state == .inMeeting(dueAt: at(10)))
    }

    /// The delay's own deadline is what the meeting then owes.
    @Test func aDelayDuringAMeetingKeepsItsDeadline() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.meetingDidStart()
        scheduler.breakNow()
        scheduler.snooze() // due at 10

        clock.advance(by: 5)
        scheduler.meetingDidEnd()
        #expect(scheduler.state == .idle(fireAt: at(10)))

        clock.advance(by: 5)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    @Test func aDelayThatRanOutDuringTheCallOpensAtTheEnd() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.meetingDidStart()
        scheduler.breakNow()
        scheduler.snooze() // due at 10

        clock.advance(by: 300)
        scheduler.meetingDidEnd()
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    /// Delaying with no call on still reads as delayed, as it always has.
    @Test func delayingOutsideAMeetingIsUnchanged() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 100)
        scheduler.snooze()
        #expect(scheduler.state == .snoozed(until: at(110)))
    }

    // MARK: Precedence

    /// The menu's pause is the user's own call and outranks detection.
    @Test func aUserPauseIsNotOverriddenByAMeeting() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.pause()
        scheduler.meetingDidStart()
        #expect(scheduler.state == .paused(byUser: true))
    }

    /// Resuming from the menu during a call should not fire a popup into it.
    @Test func resumingDuringAMeetingHoldsAgain() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.pause()
        scheduler.meetingDidStart()
        scheduler.resume()
        #expect(scheduler.state == .inMeeting(dueAt: at(100)))
    }

    /// "Take a Break Now" is an explicit request and still works.
    @Test func aBreakCanStillBeTakenByHandDuringAMeeting() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.meetingDidStart()
        scheduler.breakNow()
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    /// Turning detection off releases the hold, keeping the deadline.
    @Test func switchingDetectionOffReleasesTheHold() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 30)
        scheduler.meetingDidStart()
        scheduler.meetingDetectionDidStop()
        #expect(scheduler.state == .idle(fireAt: at(100)))
    }

    @Test func switchingDetectionOffAfterTheBreakCameDueOpensIt() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.meetingDidStart()
        clock.advance(by: 300)
        scheduler.meetingDetectionDidStop()
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    // MARK: Sleep

    @Test func sleepingDuringAMeetingWakesToAFreshInterval() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.meetingDidStart()
        scheduler.systemDidSuspend()
        #expect(scheduler.state == .paused(byUser: false))

        clock.advance(by: 50)
        scheduler.meetingDidEnd()
        scheduler.systemDidResume()
        // Sleep starts the 20 minutes over, as it always has.
        #expect(scheduler.state == .idle(fireAt: at(150)))
    }

    /// A call still going when the Mac wakes keeps holding.
    @Test func wakingIntoAMeetingHoldsAgain() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.meetingDidStart()
        scheduler.systemDidSuspend()
        clock.advance(by: 40)
        scheduler.systemDidResume()
        #expect(scheduler.state == .inMeeting(dueAt: at(140)))
    }

    // MARK: Schedule

    private var mondayOnly: Schedule {
        Schedule(
            isEnabled: true,
            activeDays: [.monday],
            hours: TimeWindow(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 17, minute: 0))
        )
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// The schedule still applies once the call ends.
    @Test func aMeetingEndingOutsideTheScheduleHoldsForTheSchedule() {
        let scheduler = BreakScheduler(config: config, schedule: mondayOnly, clock: clock, calendar: utc)
        clock.advance(by: 10 * 3_600) // Monday 10am, inside the window
        scheduler.start()
        scheduler.meetingDidStart()
        clock.advance(by: 8 * 3_600) // 6pm, the window has closed
        scheduler.meetingDidEnd()

        // Monday is the only active day, so it reopens a week on.
        #expect(scheduler.state == .offSchedule(until: at(7 * 86_400 + 9 * 3_600)))
    }

    /// Outside the scheduled hours there is nothing pending to hold, and that
    /// hold already outlasts any call.
    @Test func aMeetingOutsideTheScheduleLeavesTheHoldAlone() {
        let scheduler = BreakScheduler(config: config, schedule: mondayOnly, clock: clock, calendar: utc)
        clock.advance(by: 20 * 3_600) // Monday 8pm, outside the window
        scheduler.start()
        let held = scheduler.state
        scheduler.meetingDidStart()
        #expect(scheduler.state == held)
    }
}
