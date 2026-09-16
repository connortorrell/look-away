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
    case microphone(app: ChosenApp)
    case camera(app: ChosenApp)
    case audioOutput(app: ChosenApp)

    public var app: ChosenApp {
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
    // user never chose, look like a meeting in any browser's company. Nor is a
    // browser playing audio enough: one is playing something most of the day,
    // so only apps that carry the camera rule can be credited.
    if settings.countsCamera, activity.isCameraInUse {
        for bundleID in activity.playingBundleIDs.sorted() {
            if let app = settings.cameraApp(owning: bundleID) { return .camera(app: app) }
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

    public var isInMeeting: Bool { core.isActive }
    public var evidence: MeetingEvidence? { core.reading }
    /// Called only when `isInMeeting` actually flips.
    public var onChange: (@MainActor (Bool) -> Void)? {
        get { core.onChange }
        set { core.onChange = newValue }
    }

    private var settings: MeetingSettings
    private let probe: MeetingActivityProbing
    private let clock: Timekeeper
    private lazy var core = DebouncedMonitor<MeetingEvidence>(
        pollInterval: Self.pollInterval,
        clock: clock,
        sample: { [unowned self] in
            .init(meetingEvidence(in: self.probe.sample(), settings: self.settings))
        },
        delay: { [unowned self] entering in
            entering ? self.settings.detectionDelay : self.settings.endGrace
        }
    )

    public init(
        settings: MeetingSettings = .standard,
        probe: MeetingActivityProbing,
        clock: Timekeeper
    ) {
        self.settings = settings
        self.probe = probe
        self.clock = clock
    }

    /// Begin watching, if the feature is on. The first reading is taken at
    /// face value: a call already under way when watching starts holds
    /// straight away rather than after the detection delay, and a hold left
    /// over from before is released at once if nothing is on.
    public func start() {
        guard settings.isEnabled, !settings.apps.isEmpty else {
            core.stop()
            return
        }
        core.start()
    }

    public func stop() {
        core.stop()
    }

    /// Adopt edited settings and re-evaluate straight away.
    public func apply(settings: MeetingSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        start()
    }

    /// The Mac is going to sleep or the screen is locking. Nothing is polled
    /// until it comes back; what was known stands until then.
    public func systemDidSuspend() {
        core.suspend()
    }

    /// Woke or unlocked. Whatever the debounce had been building towards is
    /// stale — the call may have ended hours ago, or begun on the phone and
    /// moved over — so the current reading is taken as it is, like a start.
    public func systemDidResume() {
        start()
    }
}
