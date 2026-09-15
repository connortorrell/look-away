import Foundation

/// What the machine looks like at one instant, as far as meetings go.
public struct MeetingActivity: Equatable, Sendable {
    /// Bundle IDs of the processes currently pulling audio off an input device.
    /// This is real capture, not "the app is open" or "the app is in front".
    public var capturingBundleIDs: Set<String>
    /// Bundle IDs of the processes currently playing audio out. A far weaker
    /// signal than capture — a video or a notification sound looks the same as
    /// a call — so on its own it only counts when explicitly asked for.
    public var playingBundleIDs: Set<String>
    /// Whether some process is reading a camera. The system reports this per
    /// device rather than per process, so it can never be pinned on an app by
    /// itself — it only corroborates an app that is already on the audio
    /// devices.
    public var isCameraInUse: Bool

    public init(
        capturingBundleIDs: Set<String> = [],
        playingBundleIDs: Set<String> = [],
        isCameraInUse: Bool = false
    ) {
        self.capturingBundleIDs = capturingBundleIDs
        self.playingBundleIDs = playingBundleIDs
        self.isCameraInUse = isCameraInUse
    }
}

/// Reads the current microphone, camera and running-app state. A protocol so
/// the monitor can be tested without a real meeting.
@MainActor
public protocol MeetingActivityProbing: AnyObject {
    func sample() -> MeetingActivity
}

/// Why the monitor thinks a meeting is on. Drives the wording in the menu.
public enum MeetingEvidence: Equatable, Sendable {
    case microphone(app: MeetingApp)
    case camera(app: MeetingApp)
    case audioOutput(app: MeetingApp)

    public var app: MeetingApp {
        switch self {
        case .microphone(let app), .camera(let app), .audioOutput(let app): return app
        }
    }
}

/// Decides whether the raw activity counts as a meeting, given the settings.
///
/// Every answer names the app responsible, and an app only becomes responsible
/// by actually being on a device — never by merely running. Anything that
/// cannot be attributed to a chosen app is not a meeting, however busy the
/// hardware looks.
///
/// Pure, so the matching rules can be tested on their own.
public func meetingEvidence(
    in activity: MeetingActivity,
    settings: MeetingSettings
) -> MeetingEvidence? {
    guard settings.isEnabled, !settings.apps.isEmpty else { return nil }

    // The microphone is the strong signal: it names the process holding it.
    for bundleID in activity.capturingBundleIDs.sorted() {
        if let app = settings.app(owning: bundleID) { return .microphone(app: app) }
    }

    // The camera cannot be attributed on its own, so it counts only as a
    // second signal on an app that is already playing the call's audio — being
    // muted on video still reads as a meeting. A chosen app merely being open
    // is not enough: that would make Photo Booth, or a camera-using app the
    // user never chose, look like a meeting in any browser's company.
    if settings.countsCamera, activity.isCameraInUse {
        for bundleID in activity.playingBundleIDs.sorted() {
            if let app = settings.app(owning: bundleID) { return .camera(app: app) }
        }
    }

    // Last and weakest: a chosen app playing audio, with nothing corroborating
    // it. Catches a listen-only call that released the mic and has no video, at
    // the cost of counting ordinary videos and alert sounds.
    if settings.countsAudioOutput {
        for bundleID in activity.playingBundleIDs.sorted() {
            if let app = settings.app(owning: bundleID) { return .audioOutput(app: app) }
        }
    }

    return nil
}

/// Watches for meetings and reports when one starts or ends.
///
/// The raw signal is jumpy — apps grab and release the microphone around
/// joining, muting and screen sharing — so a reading has to hold for
/// `detectionDelay` before a meeting starts and stay clear for `endGrace`
/// before it ends. Nothing is polled at all while the feature is off.
@MainActor
public final class MeetingMonitor {
    /// How often the probe is read. Cheap enough to do on a short cycle, and
    /// short enough that the delay and grace periods land accurately.
    public static let pollInterval: TimeInterval = 2

    public private(set) var isInMeeting = false
    public private(set) var evidence: MeetingEvidence?
    /// Called only when `isInMeeting` actually flips.
    public var onChange: (@MainActor (Bool) -> Void)?

    private var settings: MeetingSettings
    private let probe: MeetingActivityProbing
    private let clock: Timekeeper
    private var poll: ScheduledTask?
    /// When the current run of "looks like a meeting" / "looks clear" began.
    private var pendingSince: Date?

    public init(
        settings: MeetingSettings = .standard,
        probe: MeetingActivityProbing,
        clock: Timekeeper
    ) {
        self.settings = settings
        self.probe = probe
        self.clock = clock
    }

    /// Begin watching, if the feature is on.
    public func start() {
        stopPolling()
        guard settings.isEnabled, !settings.apps.isEmpty else {
            clearMeeting()
            return
        }
        check()
        schedulePoll()
    }

    public func stop() {
        stopPolling()
        clearMeeting()
    }

    /// Adopt edited settings and re-evaluate straight away.
    public func apply(settings: MeetingSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        pendingSince = nil
        start()
    }

    // MARK: - Polling

    private func schedulePoll() {
        poll = clock.schedule(after: Self.pollInterval) { [weak self] in
            guard let self else { return }
            self.check()
            self.schedulePoll()
        }
    }

    private func stopPolling() {
        poll?.cancel()
        poll = nil
    }

    /// One reading, debounced into a start or an end.
    private func check() {
        let found = meetingEvidence(in: probe.sample(), settings: settings)
        let looksLikeMeeting = found != nil
        guard looksLikeMeeting != isInMeeting else {
            // The reading agrees with where we are; drop any part-run and keep
            // the evidence current so the menu can name the right app.
            pendingSince = nil
            if let found { evidence = found }
            return
        }

        let now = clock.now()
        let since = pendingSince ?? now
        pendingSince = since
        let required = looksLikeMeeting ? settings.detectionDelay : settings.endGrace
        guard now.timeIntervalSince(since) >= required else { return }

        pendingSince = nil
        isInMeeting = looksLikeMeeting
        evidence = found
        onChange?(looksLikeMeeting)
    }

    private func clearMeeting() {
        pendingSince = nil
        evidence = nil
        guard isInMeeting else { return }
        isInMeeting = false
        onChange?(false)
    }
}
