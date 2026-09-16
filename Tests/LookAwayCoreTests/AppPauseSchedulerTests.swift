import Foundation
import Testing
@testable import LookAwayCore

/// How the scheduler behaves while an app hold is on, and what happens when a
/// meeting and an app hold overlap. The countdown keeps running through both;
/// only the popup is held back.
@MainActor
struct AppPauseSchedulerTests {
    let config = Config(workInterval: 100, breakSeconds: 5, snoozeInterval: 10)
    let clock = FakeTimekeeper()

    /// Seconds since the fake clock's start.
    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private func makeScheduler(schedule: Schedule = .standard) -> BreakScheduler {
        BreakScheduler(config: config, schedule: schedule, clock: clock)
    }

    // MARK: One hold

    @Test func anAppHoldsThePopupButKeepsTheDeadline() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 30)
        scheduler.hold(.app)
        #expect(scheduler.state == .held(dueAt: at(100), by: .app))

        // Well past when the popup would have opened.
        clock.advance(by: 5_000)
        #expect(scheduler.state == .held(dueAt: at(100), by: .app))
    }

    /// The headline case: a long session swallows the break, and it is owed as
    /// soon as you leave the app rather than a fresh interval later.
    @Test func aBreakThatCameDueInTheAppOpensOnLeaving() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 30)
        scheduler.hold(.app)
        clock.advance(by: 7_200) // two hours in the game

        scheduler.release(.app)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    /// A short spell in the app just carries on counting, so the break lands
    /// when it always would have.
    @Test func aShortSpellLetsTheRemainderPlayOut() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 30) // 70 left
        scheduler.hold(.app)
        clock.advance(by: 20)
        scheduler.release(.app)

        #expect(scheduler.state == .idle(fireAt: at(100)))
        clock.advance(by: 50)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    /// A popup already up when the app comes forward is taken away — being
    /// interrupted is the thing the list exists to stop — and owed back after.
    @Test func aBreakInProgressIsClosedAndOwedAgain() {
        let scheduler = makeScheduler()
        var dismissals = 0
        scheduler.onEvent = { if $0 == .breakDismissed { dismissals += 1 } }
        scheduler.start()
        clock.advance(by: 100)
        #expect(scheduler.state == .breaking(remaining: 5))

        scheduler.hold(.app)
        #expect(dismissals == 1)
        #expect(scheduler.state == .held(dueAt: at(100), by: .app))

        clock.advance(by: 60)
        scheduler.release(.app)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    /// Pausing from the menu is the user saying so out loud, and outranks
    /// anything detection has to say.
    @Test func aUserPauseIsNotOverriddenByAnApp() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.pause()
        scheduler.hold(.app)
        #expect(scheduler.state == .paused(byUser: true))
    }

    /// At launch the monitors report before the scheduler is started, so a
    /// hold placed against a stopped scheduler has to be honoured on start.
    @Test func aHoldPlacedBeforeStartIsHonouredOnStart() {
        let scheduler = makeScheduler()
        scheduler.hold(.app)
        scheduler.start()
        #expect(scheduler.state == .held(dueAt: at(100), by: .app))

        scheduler.release(.app)
        #expect(scheduler.state == .idle(fireAt: at(100)))
    }

    /// Switching the feature off mid-hold, which reaches the scheduler as a
    /// release for a hold the monitor will never report the end of.
    @Test func releasingAHoldThatWasNeverPlacedDoesNothing() {
        let scheduler = makeScheduler()
        scheduler.start()
        clock.advance(by: 30)
        scheduler.release(.app)
        #expect(scheduler.state == .idle(fireAt: at(100)))
    }

    // MARK: Two holds

    /// A call taken with the game still up. Leaving the game does not let a
    /// popup through, because the call is still on.
    @Test func thePopupWaitsForTheLastHoldToLift() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.hold(.app)
        scheduler.hold(.meeting)
        clock.advance(by: 300)

        scheduler.release(.app)
        #expect(scheduler.state == .held(dueAt: at(100), by: .meeting))

        scheduler.release(.meeting)
        #expect(scheduler.state == .breaking(remaining: 5))
    }

    /// Being on a call is the more useful thing to be told, so it takes the
    /// menu line over an app hold whichever way round they arrive.
    @Test func aMeetingOutranksAnAppInTheMenu() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.hold(.app)
        #expect(scheduler.state == .held(dueAt: at(100), by: .app))

        scheduler.hold(.meeting)
        #expect(scheduler.state == .held(dueAt: at(100), by: .meeting))

        // And hands it back when the call ends but the game is still up.
        scheduler.release(.meeting)
        #expect(scheduler.state == .held(dueAt: at(100), by: .app))
    }

    /// Delaying a break taken by hand during a hold keeps the hold on display,
    /// and hands the delay's deadline to it.
    @Test func snoozingDuringAnAppHoldStaysHeld() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.hold(.app)
        scheduler.breakNow()
        scheduler.snooze()
        #expect(scheduler.state == .held(dueAt: at(10), by: .app))
    }
}
