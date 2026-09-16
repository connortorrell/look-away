import Foundation
import Testing
@testable import LookAwayCore

/// Stands in for the real audio and camera probe.
@MainActor
final class FakeActivityProbe: MeetingActivityProbing {
    var activity = MeetingActivity()
    private(set) var sampleCount = 0

    func sample() -> MeetingActivity {
        sampleCount += 1
        return activity
    }
}

@MainActor
struct ChosenAppMatchingTests {
    let zoom = ChosenApp.preset(for: "us.zoom.xos")!
    let pop = ChosenApp(bundleID: "com.pop.pop.app", name: "Pop")

    @Test func matchesTheAppItself() {
        #expect(zoom.matches(processBundleID: "us.zoom.xos"))
    }

    /// Electron and Chromium apps capture from a nested helper process.
    @Test func matchesAHelperNestedUnderTheApp() {
        #expect(pop.matches(processBundleID: "com.pop.pop.app.helper"))
        #expect(pop.matches(processBundleID: "com.pop.pop.app.helper.Plugin"))
    }

    /// Zoom's capture process is a sibling of the app, not nested under it.
    @Test func matchesASiblingCaptureProcess() {
        #expect(zoom.matches(processBundleID: "us.zoom.caphost"))
    }

    /// Arc ships as `company.thebrowser.Browser` but captures from
    /// `company.thebrowser.browser.helper`.
    /// FaceTime.app never touches the microphone itself; the system's call
    /// daemon does, for FaceTime and for iPhone calls taken on the Mac.
    @Test func matchesFaceTimesCallDaemon() {
        let facetime = ChosenApp.preset(for: "com.apple.FaceTime")!
        #expect(facetime.matches(processBundleID: "com.apple.avconferenced"))
    }

    @Test func matchesRegardlessOfCase() {
        let arc = ChosenApp(bundleID: "company.thebrowser.Browser", name: "Arc")
        #expect(arc.matches(processBundleID: "company.thebrowser.browser.helper"))
    }

    /// Every browser in the presets is reachable from its capture process.
    @Test func matchesEachBrowsersCaptureProcess() {
        let captures = [
            ("com.google.Chrome", "com.google.Chrome.helper"),
            ("com.microsoft.edgemac", "com.microsoft.edgemac.helper"),
            ("company.thebrowser.Browser", "company.thebrowser.browser.helper"),
            ("com.brave.Browser", "com.brave.Browser.helper"),
            ("org.mozilla.firefox", "org.mozilla.firefox"),
            ("com.apple.Safari", "com.apple.WebKit.GPU"),
        ]
        for (bundleID, process) in captures {
            let browser = ChosenApp.preset(for: bundleID)
            #expect(browser?.matches(processBundleID: process) == true, "\(bundleID) should own \(process)")
            #expect(browser?.attributesCamera == false, "\(bundleID) should not be credited with camera use")
        }
    }

    @Test func doesNotMatchAnUnrelatedApp() {
        #expect(!pop.matches(processBundleID: "com.spotify.client"))
        // A shared prefix that is not a bundle-ID boundary must not match.
        #expect(!ChosenApp(bundleID: "com.foo", name: "Foo").matches(processBundleID: "com.foobar"))
    }
}

@MainActor
struct MeetingEvidenceTests {
    private var settings: MeetingSettings {
        MeetingSettings(isEnabled: true, apps: [ChosenApp.preset(for: "us.zoom.xos")!])
    }

    @Test func microphoneUseByAChosenAppIsAMeeting() {
        let activity = MeetingActivity(capturingBundleIDs: ["us.zoom.caphost"])
        #expect(meetingEvidence(in: activity, settings: settings)?.app.name == "Zoom")
    }

    @Test func microphoneUseByAnotherAppIsNot() {
        let activity = MeetingActivity(capturingBundleIDs: ["com.apple.VoiceMemos"])
        #expect(meetingEvidence(in: activity, settings: settings) == nil)
    }

    /// The point of the feature: an app being open, or in front, is not enough
    /// — it has to be on a device itself.
    @Test func aChosenAppMerelyRunningIsNotAMeeting() {
        #expect(meetingEvidence(in: MeetingActivity(), settings: settings) == nil)
    }

    /// Muted on video: the mic is released but the call's audio still plays.
    @Test func cameraUseCountsWhenAChosenAppIsOnTheAudioDevices() {
        let activity = MeetingActivity(playingBundleIDs: ["us.zoom.caphost"], isCameraInUse: true)
        #expect(meetingEvidence(in: activity, settings: settings) == .camera(app: settings.apps[0]))
    }

    /// The camera is reported per device, so an app that is only *open* cannot
    /// be blamed for it — Photo Booth must not read as a Zoom meeting just
    /// because Zoom is running.
    @Test func cameraUseByAnotherAppIsNotAMeeting() {
        let activity = MeetingActivity(playingBundleIDs: ["com.apple.PhotoBooth"], isCameraInUse: true)
        #expect(meetingEvidence(in: activity, settings: settings) == nil)
    }

    /// The camera alone, with no chosen app on a device, is nobody's meeting.
    @Test func cameraUseAloneIsNotAMeeting() {
        let activity = MeetingActivity(isCameraInUse: true)
        #expect(meetingEvidence(in: activity, settings: settings) == nil)
    }

    /// A browser is playing something most of the day, so the camera cannot be
    /// pinned on it — otherwise a YouTube tab plus Photo Booth would be a
    /// "Google Chrome meeting".
    @Test func cameraUseWithABrowserPlayingAudioIsNotAMeeting() {
        let browsing = MeetingSettings(
            isEnabled: true,
            apps: [ChosenApp.preset(for: "us.zoom.xos")!, ChosenApp.preset(for: "com.google.Chrome")!]
        )
        let activity = MeetingActivity(playingBundleIDs: ["com.google.Chrome.helper"], isCameraInUse: true)
        #expect(meetingEvidence(in: activity, settings: browsing) == nil)
    }

    /// But a browser still counts for the microphone, where the process is named.
    @Test func aBrowserHoldingTheMicrophoneIsStillAMeeting() {
        let browsing = MeetingSettings(isEnabled: true, apps: [ChosenApp.preset(for: "com.google.Chrome")!])
        let activity = MeetingActivity(capturingBundleIDs: ["com.google.Chrome.helper"])
        #expect(meetingEvidence(in: activity, settings: browsing)?.app.name == "Google Chrome")
    }

    @Test func cameraUseWithAMeetingAppAndABrowserPlayingIsPinnedOnTheChosenApp() {
        let browsing = MeetingSettings(
            isEnabled: true,
            apps: [ChosenApp.preset(for: "com.google.Chrome")!, ChosenApp.preset(for: "us.zoom.xos")!]
        )
        let activity = MeetingActivity(playingBundleIDs: ["com.google.Chrome.helper", "us.zoom.caphost"], isCameraInUse: true)
        #expect(meetingEvidence(in: activity, settings: browsing)?.app.name == "Zoom")
    }

    @Test func cameraCanBeIgnored() {
        var ignoring = settings
        ignoring.countsCamera = false
        let activity = MeetingActivity(playingBundleIDs: ["us.zoom.caphost"], isCameraInUse: true)
        #expect(meetingEvidence(in: activity, settings: ignoring) == nil)
    }

    /// Audio playing is off by default, so a video in Chrome is not a meeting.
    @Test func audioOutputIsIgnoredByDefault() {
        let activity = MeetingActivity(playingBundleIDs: ["us.zoom.xos"])
        #expect(meetingEvidence(in: activity, settings: settings) == nil)
    }

    @Test func audioOutputCountsOnceItIsSwitchedOn() {
        var listening = settings
        listening.countsAudioOutput = true
        let activity = MeetingActivity(playingBundleIDs: ["us.zoom.caphost"])
        #expect(meetingEvidence(in: activity, settings: listening) == .audioOutput(app: settings.apps[0]))
    }

    @Test func audioOutputFromAnotherAppIsNotAMeeting() {
        var listening = settings
        listening.countsAudioOutput = true
        let activity = MeetingActivity(playingBundleIDs: ["com.spotify.client"])
        #expect(meetingEvidence(in: activity, settings: listening) == nil)
    }

    /// The microphone is the stronger signal and should be the one reported.
    @Test func microphoneIsPreferredOverAudioOutput() {
        var listening = settings
        listening.countsAudioOutput = true
        let activity = MeetingActivity(
            capturingBundleIDs: ["us.zoom.xos"],
            playingBundleIDs: ["us.zoom.xos"]
        )
        #expect(meetingEvidence(in: activity, settings: listening) == .microphone(app: settings.apps[0]))
    }

    @Test func nothingIsDetectedWhileSwitchedOff() {
        var off = settings
        off.isEnabled = false
        let activity = MeetingActivity(capturingBundleIDs: ["us.zoom.caphost"])
        #expect(meetingEvidence(in: activity, settings: off) == nil)
    }

    @Test func nothingIsDetectedWithNoAppsChosen() {
        let empty = MeetingSettings(isEnabled: true, apps: [])
        let activity = MeetingActivity(capturingBundleIDs: ["us.zoom.caphost"])
        #expect(meetingEvidence(in: activity, settings: empty) == nil)
    }
}

@MainActor
struct MeetingMonitorTests {
    let clock = FakeTimekeeper()
    let probe = FakeActivityProbe()
    let zoom = ChosenApp.preset(for: "us.zoom.xos")!

    private func makeMonitor(delay: TimeInterval = 15, grace: TimeInterval = 30) -> MeetingMonitor {
        let settings = MeetingSettings(
            isEnabled: true,
            apps: [zoom],
            detectionDelay: delay,
            endGrace: grace
        )
        return MeetingMonitor(settings: settings, probe: probe, clock: clock)
    }

    private func startMeeting() {
        probe.activity = MeetingActivity(capturingBundleIDs: ["us.zoom.caphost"])
    }

    private func endMeeting() {
        probe.activity = MeetingActivity()
    }

    @Test func aMeetingIsNotReportedBeforeTheDetectionDelayPasses() {
        let monitor = makeMonitor()
        monitor.start()
        startMeeting()

        clock.advance(by: 10)
        #expect(!monitor.isInMeeting)

        clock.advance(by: 10)
        #expect(monitor.isInMeeting)
        #expect(monitor.evidence == .microphone(app: zoom))
    }

    /// A notification chime grabbing the mic for a moment must not count.
    @Test func aBriefBurstOfActivityIsIgnored() {
        let monitor = makeMonitor()
        monitor.start()
        startMeeting()
        clock.advance(by: 6)
        endMeeting()
        clock.advance(by: 60)
        #expect(!monitor.isInMeeting)
    }

    @Test func detectionCanBeImmediate() {
        let monitor = makeMonitor(delay: 0)
        monitor.start()
        startMeeting()
        clock.advance(by: MeetingMonitor.pollInterval)
        #expect(monitor.isInMeeting)
    }

    @Test func aMeetingHoldsThroughTheEndGraceBeforeEnding() {
        let monitor = makeMonitor()
        monitor.start()
        startMeeting()
        clock.advance(by: 20)
        #expect(monitor.isInMeeting)

        endMeeting()
        clock.advance(by: 20)
        #expect(monitor.isInMeeting)

        clock.advance(by: 20)
        #expect(!monitor.isInMeeting)
    }

    /// Muting can drop the capture briefly; reminders must not slip back in.
    @Test func aShortDropInsideTheGraceKeepsTheMeetingOn() {
        let monitor = makeMonitor()
        monitor.start()
        startMeeting()
        clock.advance(by: 20)

        endMeeting()
        clock.advance(by: 10)
        startMeeting()
        clock.advance(by: 120)
        #expect(monitor.isInMeeting)
    }

    @Test func changesAreReportedOnlyOnceEachWay() {
        let monitor = makeMonitor()
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }
        monitor.start()

        startMeeting()
        clock.advance(by: 60)
        endMeeting()
        clock.advance(by: 60)
        #expect(changes == [true, false])
    }

    /// Switching off has to report the end of a meeting already under way:
    /// that report is what releases the scheduler's hold.
    @Test func switchingOffStopsPollingAndClearsTheMeeting() {
        let monitor = makeMonitor()
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }
        monitor.start()
        startMeeting()
        clock.advance(by: 20)
        #expect(monitor.isInMeeting)

        monitor.apply(settings: MeetingSettings(isEnabled: false, apps: [zoom]))
        #expect(!monitor.isInMeeting)
        #expect(changes == [true, false])

        let before = probe.sampleCount
        clock.advance(by: 120)
        #expect(probe.sampleCount == before)
    }

    @Test func nothingIsPolledWhileSwitchedOff() {
        let monitor = MeetingMonitor(
            settings: MeetingSettings(isEnabled: false),
            probe: probe,
            clock: clock
        )
        monitor.start()
        clock.advance(by: 120)
        #expect(probe.sampleCount == 0)
    }

    /// Removing the app the current meeting was detected from ends the hold.
    @Test func removingTheDetectedAppEndsTheMeeting() {
        let monitor = makeMonitor()
        monitor.start()
        startMeeting()
        clock.advance(by: 20)
        #expect(monitor.isInMeeting)

        monitor.apply(settings: MeetingSettings(isEnabled: true, apps: [], detectionDelay: 15))
        #expect(!monitor.isInMeeting)
    }

    /// With other apps still chosen the removal goes through a fresh reading
    /// rather than the empty-list shortcut, and it still ends at once.
    @Test func removingTheDetectedAppWhileOthersRemainEndsTheMeetingAtOnce() {
        let monitor = makeMonitor()
        monitor.start()
        startMeeting()
        clock.advance(by: 20)
        #expect(monitor.isInMeeting)

        let slack = ChosenApp.preset(for: "com.tinyspeck.slackmacgap")!
        monitor.apply(settings: MeetingSettings(isEnabled: true, apps: [slack], detectionDelay: 15))
        #expect(!monitor.isInMeeting)
    }

    /// Watching may begin with a call already on — the app launched, or the
    /// feature switched on, mid-meeting — and that is not a chime to wait out.
    @Test func aCallAlreadyOnWhenWatchingStartsHoldsAtOnce() {
        let monitor = makeMonitor()
        startMeeting()
        monitor.start()
        #expect(monitor.isInMeeting)
    }

    @Test func nothingIsPolledWhileAsleep() {
        let monitor = makeMonitor()
        monitor.start()
        monitor.systemDidSuspend()
        let before = probe.sampleCount
        clock.advance(by: 120)
        #expect(probe.sampleCount == before)
    }

    /// The call ended while the Mac slept; waking must not report a meeting
    /// for another grace period.
    @Test func wakingWithNoCallEndsTheMeetingAtOnce() {
        let monitor = makeMonitor()
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }
        monitor.start()
        startMeeting()
        clock.advance(by: 20)
        monitor.systemDidSuspend()
        endMeeting()
        clock.advance(by: 3_600)

        monitor.systemDidResume()
        #expect(!monitor.isInMeeting)
        #expect(changes == [true, false])
    }

    /// A call still going, or begun during the lock, holds without waiting
    /// out the detection delay, and polling picks back up afterwards.
    @Test func wakingIntoACallHoldsAtOnceAndResumesPolling() {
        let monitor = makeMonitor()
        monitor.start()
        monitor.systemDidSuspend()
        startMeeting()
        monitor.systemDidResume()
        #expect(monitor.isInMeeting)

        endMeeting()
        clock.advance(by: 60)
        #expect(!monitor.isInMeeting)
    }
}

@MainActor
struct MeetingSettingsTests {
    @Test func addingAnAppInheritsThePresetsProcessPrefixes() {
        var settings = MeetingSettings()
        // As the installed-apps list would offer it: bundle ID and name only.
        settings.add(ChosenApp(bundleID: "us.zoom.xos", name: "zoom.us"))
        #expect(settings.apps[0].matches(processBundleID: "us.zoom.caphost"))
    }

    /// A browser picked from the installed list knows only its bundle ID and
    /// name; the preset supplies the camera rule.
    @Test func addingABrowserInheritsThePresetsCameraRule() {
        var settings = MeetingSettings()
        settings.add(ChosenApp(bundleID: "com.google.Chrome", name: "Google Chrome"))
        settings.add(ChosenApp(bundleID: "com.acme.meet", name: "Acme Meet"))
        #expect(!settings.apps[0].attributesCamera)
        #expect(settings.apps[1].attributesCamera)
    }

    /// Apps saved before the camera rule existed have no key for it.
    @Test func anAppSavedWithoutTheCameraRuleDecodesAsCounting() throws {
        let saved = #"{"bundleID":"us.zoom.xos","name":"Zoom","extraPrefixes":["us.zoom."]}"#
        let app = try JSONDecoder().decode(ChosenApp.self, from: Data(saved.utf8))
        #expect(app.attributesCamera)
        #expect(app.extraPrefixes == ["us.zoom."])
    }

    /// A chip seeded before its preset learned about a sibling process has an
    /// empty prefix list on disk; reading it back fills the list in, so the fix
    /// reaches installs that already have the app chosen.
    @Test func anAppSavedWithoutPrefixesPicksUpThePresetsOnLoad() throws {
        let saved = #"{"bundleID":"com.apple.FaceTime","name":"FaceTime","extraPrefixes":[]}"#
        let app = try JSONDecoder().decode(ChosenApp.self, from: Data(saved.utf8))
        #expect(app.matches(processBundleID: "com.apple.avconferenced"))

        // An app with no preset keeps its empty list; nothing is invented.
        let unknown = #"{"bundleID":"com.acme.meet","name":"Acme Meet"}"#
        #expect(try JSONDecoder().decode(ChosenApp.self, from: Data(unknown.utf8)).extraPrefixes.isEmpty)
    }

    @Test func appsAreNotAddedTwice() {
        var settings = MeetingSettings()
        settings.add(ChosenApp(bundleID: "us.zoom.xos", name: "Zoom"))
        settings.add(ChosenApp(bundleID: "US.ZOOM.XOS", name: "Zoom"))
        #expect(settings.apps.count == 1)
    }

    @Test func removingAnAppIsCaseInsensitive() {
        var settings = MeetingSettings(isEnabled: true, apps: [ChosenApp(bundleID: "us.zoom.xos", name: "Zoom")])
        settings.remove("US.ZOOM.XOS")
        #expect(settings.apps.isEmpty)
    }

    /// Settings written by a build that predates a new option have to survive
    /// being read back, rather than resetting every other option with them.
    @Test func settingsFromAnOlderBuildKeepTheirValues() throws {
        let saved = """
        {"isEnabled":true,"apps":[{"bundleID":"us.zoom.xos","name":"Zoom","extraPrefixes":["us.zoom."]}],\
        "detectionDelay":5,"endGrace":45,"countsCamera":false,"hasSeededApps":true}
        """
        let settings = try JSONDecoder().decode(MeetingSettings.self, from: Data(saved.utf8))

        #expect(settings.isEnabled)
        #expect(settings.apps.map(\.name) == ["Zoom"])
        #expect(settings.detectionDelay == 5)
        #expect(settings.endGrace == 45)
        #expect(!settings.countsCamera)
        #expect(settings.hasSeededApps)
        // The option the older build had never heard of falls back to its default.
        #expect(!settings.countsAudioOutput)
    }

    @Test func settingsSurviveARoundTrip() throws {
        var original = MeetingSettings(isEnabled: true, apps: [ChosenApp.meetingPresets[0]])
        original.countsAudioOutput = true
        let decoded = try JSONDecoder().decode(
            MeetingSettings.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }

    @Test func seedingPicksUpOnlyTheInstalledPresets() {
        var settings = MeetingSettings()
        let didSeed = settings.seedApps(installed: ["us.zoom.xos", "com.acme.spreadsheets"])
        #expect(didSeed)
        #expect(settings.apps.map(\.bundleID) == ["us.zoom.xos"])
    }

    /// Clearing the list has to stay cleared, so seeding happens once only.
    @Test func seedingHappensOnlyOnce() {
        var settings = MeetingSettings()
        _ = settings.seedApps(installed: ["us.zoom.xos"])
        settings.remove("us.zoom.xos")
        let didSeedAgain = settings.seedApps(installed: ["us.zoom.xos"])
        #expect(!didSeedAgain)
        #expect(settings.apps.isEmpty)
    }
}
