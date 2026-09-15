import Foundation
import Testing
@testable import LookAwayCore

/// Stands in for the real frontmost-app lookup.
@MainActor
final class FakeFrontmostAppProbe: FrontmostAppProbing {
    var bundleID: String?
    private(set) var sampleCount = 0

    func frontmostBundleID() -> String? {
        sampleCount += 1
        return bundleID
    }
}

@MainActor
struct FocusedAppMonitorTests {
    let clock = FakeTimekeeper()
    let probe = FakeFrontmostAppProbe()

    let minecraft = ChosenApp(bundleID: "com.mojang.minecraft", name: "Minecraft")

    private func makeMonitor(enabled: Bool = true, apps: [ChosenApp]? = nil) -> FocusedAppMonitor {
        FocusedAppMonitor(
            settings: AppPauseSettings(isEnabled: enabled, apps: apps ?? [minecraft]),
            probe: probe,
            clock: clock
        )
    }

    /// Both ends of the debounce, in one pass.
    @Test func entersAfterTheSettleDelayAndLeavesAfterTheGrace() {
        let monitor = makeMonitor()
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }

        probe.bundleID = "com.apple.finder"
        monitor.start()
        #expect(!monitor.isInPausingApp)

        // Switching into the app has to settle before it counts.
        probe.bundleID = minecraft.bundleID
        clock.advance(by: AppPauseSettings.settleDelay - FocusedAppMonitor.pollInterval)
        #expect(!monitor.isInPausingApp)

        clock.advance(by: AppPauseSettings.settleDelay)
        #expect(monitor.isInPausingApp)
        #expect(monitor.app == minecraft)
        #expect(changes == [true])

        probe.bundleID = "com.apple.finder"
        clock.advance(by: FocusedAppMonitor.pollInterval)
        #expect(monitor.isInPausingApp)

        clock.advance(by: AppPauseSettings.leaveGrace)
        #expect(!monitor.isInPausingApp)
        #expect(changes == [true, false])
    }

    /// Switching the feature on while already in the app is the user answering
    /// the question, so there is nothing left to settle.
    @Test func switchingTheFeatureOnInsideTheAppHoldsAtOnce() {
        let monitor = makeMonitor()
        probe.bundleID = minecraft.bundleID
        monitor.start()
        #expect(monitor.isInPausingApp)
        #expect(monitor.app == minecraft)
    }

    /// And removing the app you are in, with others still on the list, ends
    /// the hold without waiting out the grace period.
    @Test func removingTheAppYouAreInWithOthersLeftEndsTheHoldAtOnce() {
        let steam = ChosenApp(bundleID: "com.valvesoftware.steam", name: "Steam")
        let monitor = makeMonitor(apps: [minecraft, steam])
        probe.bundleID = minecraft.bundleID
        monitor.start()
        #expect(monitor.isInPausingApp)

        monitor.apply(settings: AppPauseSettings(isEnabled: true, apps: [steam]))
        #expect(!monitor.isInPausingApp)
    }

    /// Clicking through a window to reach something behind it is not a session.
    @Test func aBriefVisitNeverCounts() {
        let monitor = makeMonitor()
        monitor.start()

        probe.bundleID = minecraft.bundleID
        clock.advance(by: 2)
        probe.bundleID = "com.apple.Safari"
        clock.advance(by: 100)
        #expect(!monitor.isInPausingApp)
    }

    /// Alt-tabbing out to look something up and straight back is not leaving.
    @Test func aGlanceAtAnotherAppDoesNotReleaseTheHold() {
        let monitor = makeMonitor()
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }

        probe.bundleID = minecraft.bundleID
        monitor.start()
        #expect(monitor.isInPausingApp)

        probe.bundleID = "com.apple.Safari"
        clock.advance(by: AppPauseSettings.leaveGrace - FocusedAppMonitor.pollInterval)
        probe.bundleID = minecraft.bundleID
        clock.advance(by: 60)

        #expect(monitor.isInPausingApp)
        #expect(changes == [true])
    }

    /// Two chosen apps in a row is one unbroken hold, and the menu follows
    /// whichever one is in front.
    @Test func movingBetweenTwoChosenAppsStaysHeld() {
        let steam = ChosenApp(bundleID: "com.valvesoftware.steam", name: "Steam")
        let monitor = makeMonitor(apps: [minecraft, steam])
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }

        probe.bundleID = minecraft.bundleID
        monitor.start()
        clock.advance(by: 30)

        probe.bundleID = steam.bundleID
        clock.advance(by: 30)
        #expect(monitor.isInPausingApp)
        #expect(monitor.app == steam)
        #expect(changes == [true])
    }

    /// Nothing is watched at all while the feature is off, or while the list
    /// is empty — the same promise the meeting monitor makes.
    @Test func nothingIsPolledWhileTheFeatureIsOff() {
        let monitor = makeMonitor(enabled: false)
        probe.bundleID = minecraft.bundleID
        monitor.start()
        clock.advance(by: 600)
        #expect(probe.sampleCount == 0)
        #expect(!monitor.isInPausingApp)
    }

    @Test func nothingIsPolledWithAnEmptyList() {
        let monitor = makeMonitor(apps: [])
        probe.bundleID = minecraft.bundleID
        monitor.start()
        clock.advance(by: 600)
        #expect(probe.sampleCount == 0)
    }

    /// Removing the app you are in has to end the hold, since the monitor will
    /// never report a leave for an app it is no longer watching.
    @Test func removingTheAppYouAreInEndsTheHold() {
        let monitor = makeMonitor()
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }

        probe.bundleID = minecraft.bundleID
        monitor.start()
        clock.advance(by: 30)
        #expect(monitor.isInPausingApp)

        monitor.apply(settings: AppPauseSettings(isEnabled: true, apps: []))
        #expect(!monitor.isInPausingApp)
        #expect(changes == [true, false])
    }

    @Test func switchingTheFeatureOffEndsTheHold() {
        let monitor = makeMonitor()
        probe.bundleID = minecraft.bundleID
        monitor.start()
        clock.advance(by: 30)

        monitor.apply(settings: AppPauseSettings(isEnabled: false, apps: [minecraft]))
        #expect(!monitor.isInPausingApp)
    }
}

@MainActor
struct AppPauseSettingsTests {
    let minecraft = ChosenApp(bundleID: "com.mojang.minecraft", name: "Minecraft")

    @Test func matchesTheChosenAppInFront() {
        let settings = AppPauseSettings(isEnabled: true, apps: [minecraft])
        #expect(settings.app(inFront: "com.mojang.minecraft") == minecraft)
        #expect(settings.app(inFront: "COM.MOJANG.MINECRAFT") == minecraft)
        #expect(settings.app(inFront: nil) == nil)
        #expect(settings.app(inFront: "com.apple.Safari") == nil)
    }

    /// The frontmost app is always the app itself, so prefix matching would
    /// only ever let something unrelated pause reminders.
    @Test func doesNotMatchOnAPrefix() {
        let settings = AppPauseSettings(isEnabled: true, apps: [ChosenApp(bundleID: "com.foo", name: "Foo")])
        #expect(settings.app(inFront: "com.foo.helper") == nil)
        #expect(settings.app(inFront: "com.foobar") == nil)
    }

    @Test func nothingMatchesWhileSwitchedOff() {
        let settings = AppPauseSettings(isEnabled: false, apps: [minecraft])
        #expect(settings.app(inFront: "com.mojang.minecraft") == nil)
        #expect(!settings.isWatching)
    }

    @Test func addingIsIdempotentAndRemovalIsCaseInsensitive() {
        var settings = AppPauseSettings(isEnabled: true)
        settings.add(minecraft)
        settings.add(ChosenApp(bundleID: "COM.MOJANG.MINECRAFT", name: "Minecraft"))
        #expect(settings.apps.count == 1)

        settings.remove("COM.MOJANG.MINECRAFT")
        #expect(settings.apps.isEmpty)
    }

    /// A settings file written before a field existed keeps what it does have.
    @Test func decodingFillsInMissingKeys() throws {
        let json = Data(#"{"isEnabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppPauseSettings.self, from: json)
        #expect(settings.isEnabled)
        #expect(settings.apps.isEmpty)
    }

    @Test func roundTripsThroughTheStore() throws {
        let settings = AppPauseSettings(isEnabled: true, apps: [minecraft])
        let decoded = try JSONDecoder().decode(
            AppPauseSettings.self, from: try JSONEncoder().encode(settings)
        )
        #expect(decoded == settings)
    }
}
