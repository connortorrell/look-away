import AppKit
import LookAwayCore
import Observation

/// Glue between the scheduler and the UI. Owns the popup panel and exposes
/// observable display state for the menu and the break view.
@MainActor
@Observable
final class AppModel {
    enum BreakPhase { case counting, done }

    private(set) var iconName = "eye"
    private(set) var remainingSeconds = 0
    private(set) var breakPhase: BreakPhase = .counting
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginError: String?

    /// Mirrors the scheduler's schedule so SwiftUI sees edits immediately.
    private(set) var schedule: Schedule
    /// Same idea for the meeting settings.
    private(set) var meetingSettings: MeetingSettings
    /// The meeting the monitor currently sees, if any. Stored rather than
    /// computed so SwiftUI can watch it; the monitor itself is not observable.
    private(set) var meetingInProgress: MeetingEvidence?
    /// And for the list of apps that pause reminders on their own.
    private(set) var appPauseSettings: AppPauseSettings

    let config: Config
    let installedApps = InstalledApps()
    private let scheduler: BreakScheduler
    private let clock: Timekeeper
    private let scheduleStore: ScheduleStoring
    private let meetingStore: MeetingSettingsStoring
    private let appPauseStore: AppPauseSettingsStoring
    private let meetings: MeetingMonitor
    private let focusedApps: FocusedAppMonitor
    private var panel: BreakPanelController?
    private var doneHide: ScheduledTask?

    init(
        config: Config = .standard,
        scheduleStore: ScheduleStoring = UserDefaultsScheduleStore(),
        meetingStore: MeetingSettingsStoring = UserDefaultsMeetingSettingsStore(),
        appPauseStore: AppPauseSettingsStoring = UserDefaultsAppPauseSettingsStore()
    ) {
        self.config = config
        self.scheduleStore = scheduleStore
        self.meetingStore = meetingStore
        self.appPauseStore = appPauseStore
        let clock = SystemTimekeeper()
        self.clock = clock
        let schedule = scheduleStore.load()
        self.schedule = schedule
        let meetingSettings = meetingStore.load()
        self.meetingSettings = meetingSettings
        let appPauseSettings = appPauseStore.load()
        self.appPauseSettings = appPauseSettings
        scheduler = BreakScheduler(config: config, schedule: schedule, clock: clock)
        meetings = MeetingMonitor(
            settings: meetingSettings,
            probe: SystemActivityProbe(),
            clock: clock
        )
        focusedApps = FocusedAppMonitor(
            settings: appPauseSettings,
            probe: WorkspaceFrontmostAppProbe(),
            clock: clock,
            ownBundleID: Bundle.main.bundleIdentifier
        )
        scheduler.onEvent = { [unowned self] event in self.handle(event) }
        meetings.onChange = { [unowned self] isInMeeting in
            isInMeeting ? self.scheduler.hold(.meeting) : self.scheduler.release(.meeting)
            // A hold or release the scheduler makes emits an event, which
            // refreshes the display; paused or off-schedule it makes neither,
            // so the panel's status is refreshed here as well.
            self.refreshMeetingStatus()
        }
        focusedApps.onChange = { [unowned self] isInPausingApp in
            isInPausingApp ? self.scheduler.hold(.app) : self.scheduler.release(.app)
        }
    }

    func start() {
        scheduler.start()
        meetings.start()
        focusedApps.start()
    }

    // MARK: User actions

    func snooze() { scheduler.snooze() }
    func decline() { scheduler.decline() }
    func breakNow() { scheduler.breakNow() }
    func togglePause() { isPaused ? scheduler.resume() : scheduler.pause() }
    func systemDidSuspend() {
        scheduler.systemDidSuspend()
        meetings.systemDidSuspend()
    }

    /// The monitor goes first so the scheduler re-arms knowing whether a call
    /// is on right now, not what was on before the Mac slept.
    func systemDidResume() {
        meetings.systemDidResume()
        scheduler.systemDidResume()
    }
    func clockDidChange() { scheduler.clockDidChange() }

    /// Single write path for schedule edits: persist, then apply. The
    /// scheduler's `scheduleChanged` event refreshes the display.
    func updateSchedule(_ schedule: Schedule) {
        guard schedule != self.schedule else { return }
        self.schedule = schedule
        scheduleStore.save(schedule)
        scheduler.apply(schedule: schedule)
    }

    /// Single write path for meeting-setting edits, mirroring `updateSchedule`.
    /// The monitor re-reads the current state at once under the new settings:
    /// switching the feature off, or dropping the app a meeting was detected
    /// from, reports that meeting's end straight away, which releases the
    /// scheduler's hold through `onChange`; switching it on during a call
    /// holds straight away.
    func updateMeetingSettings(_ settings: MeetingSettings) {
        guard settings != meetingSettings else { return }
        meetingSettings = settings
        meetingStore.save(settings)
        meetings.apply(settings: settings)
    }

    /// Single write path for the pause list, mirroring `updateMeetingSettings`:
    /// the monitor re-reads at once, and an edit that takes its hold away —
    /// switching off, or dropping the app you are in — reports the end
    /// through `onChange`.
    func updateAppPauseSettings(_ settings: AppPauseSettings) {
        guard settings != appPauseSettings else { return }
        appPauseSettings = settings
        appPauseStore.save(settings)
        focusedApps.apply(settings: settings)
    }

    /// Called when the settings panel opens. Fills an untouched app list with
    /// the meeting apps actually installed, so switching the feature on does
    /// something sensible without the user picking anything first.
    func prepareMeetingSettings() {
        Task {
            let installed = await installedApps.load()
            var seeded = meetingSettings
            guard seeded.seedApps(installed: Set(installed.map(\.bundleID))) else { return }
            updateMeetingSettings(seeded)
        }
    }

    /// Called when the settings panel opens. The pause list has nothing to
    /// seed, but its search field still needs the installed-apps scan under
    /// way, and the panel can be opened with the meeting section switched off.
    func loadInstalledApps() {
        Task { await installedApps.load() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
    }

    // MARK: Scheduler events

    private func handle(_ event: BreakScheduler.Event) {
        switch event {
        case .breakStarted:
            cancelDoneHide()
            breakPhase = .counting
            remainingSeconds = config.breakSeconds
            showPanel()
        case .countdownTicked(let remaining):
            remainingSeconds = remaining
        case .breakCompleted:
            breakPhase = .done
            Sound.playChime()
            doneHide = clock.schedule(after: 1.2) { [weak self] in self?.panel?.hide() }
        case .breakDismissed:
            cancelDoneHide()
            panel?.hide()
        case .scheduleChanged:
            break
        }
        refreshIcon()
        refreshMeetingStatus()
    }

    private func refreshMeetingStatus() {
        let current = meetings.isInMeeting ? meetings.evidence : nil
        if current != meetingInProgress { meetingInProgress = current }
    }

    private func showPanel() {
        if panel == nil {
            panel = BreakPanelController(content: BreakView(model: self))
        }
        panel?.show()
    }

    private func cancelDoneHide() {
        doneHide?.cancel()
        doneHide = nil
    }

    // MARK: Display state

    var isPaused: Bool {
        if case .paused = scheduler.state { return true }
        return false
    }

    var isBreaking: Bool {
        if case .breaking = scheduler.state { return true }
        return false
    }

    /// Computed on demand so a menu can poll it every second while open.
    var statusText: String {
        switch scheduler.state {
        case .stopped:
            return "Starting…"
        case .idle(let fireAt):
            return "Next break in \(Self.format(fireAt.timeIntervalSince(clock.now())))"
        case .breaking:
            return "Break in progress"
        case .snoozed(let until):
            return "Delayed — back in \(Self.format(until.timeIntervalSince(clock.now())))"
        case .paused(let byUser):
            return byUser ? "Paused" : "Paused (screen locked)"
        case .offSchedule(let until):
            // `until` is only nil when no day is switched on.
            guard let until else { return "No days scheduled" }
            return "Outside schedule — back \(Self.formatOpening(until, from: clock.now()))"
        case .held(let dueAt, let reason):
            let lead = Self.lead(for: reason, meeting: meetingInProgress?.app, app: focusedApps.app)
            let remaining = dueAt.timeIntervalSince(clock.now())
            // The countdown keeps running through a hold, so it can already be owed.
            guard remaining > 0 else { return "\(lead) — \(Self.owed(for: reason))" }
            return "\(lead) — next break in \(Self.format(remaining))"
        }
    }

    private func refreshIcon() {
        let icon: String
        switch scheduler.state {
        case .breaking: icon = "eye.slash"
        case .paused: icon = "pause.circle"
        case .offSchedule: icon = "moon.zzz"
        case .held(_, .meeting): icon = "video"
        case .held(_, .app): icon = "macwindow"
        case .stopped, .idle, .snoozed: icon = "eye"
        }
        if icon != iconName { iconName = icon }
    }

    /// What the menu leads with while a hold is on. Naming the app is the
    /// point: "In a meeting" is only reached when detection lost track of which
    /// app it was.
    private static func lead(for reason: BreakScheduler.HoldReason, meeting: ChosenApp?, app: ChosenApp?) -> String {
        switch reason {
        case .meeting:
            return meeting.map { "\($0.name) meeting" } ?? "In a meeting"
        case .app:
            return app?.name ?? "In a paused app"
        }
    }

    /// How the menu puts a break that is already owed and waiting on the hold.
    private static func owed(for reason: BreakScheduler.HoldReason) -> String {
        switch reason {
        case .meeting: return "break when you're free"
        case .app: return "break when you're done"
        }
    }

    /// "at 9:00 AM" for later today, "Mon at 9:00 AM" within the week, and
    /// "next Mon at 9:00 AM" when the opening is a full week away, so a
    /// Monday-only schedule read on Monday evening does not look like today.
    private static func formatOpening(_ date: Date, from now: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "at \(time)" }
        let weekday = date.formatted(.dateTime.weekday(.abbreviated))
        let daysAway = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        return daysAway >= 7 ? "next \(weekday) at \(time)" : "\(weekday) at \(time)"
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
