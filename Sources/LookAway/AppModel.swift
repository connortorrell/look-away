import AppKit
import LookAwayCore
import Observation

/// Glue between the scheduler and the UI. Owns the popup panel and exposes
/// observable display state for the menu and the break view.
@MainActor
@Observable
final class AppModel {
    enum BreakPhase { case counting, done }

    private(set) var statusText = "Starting…"
    private(set) var iconName = "eye"
    private(set) var isPaused = false
    private(set) var isBreaking = false
    private(set) var remainingSeconds = 0
    private(set) var breakPhase: BreakPhase = .counting
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginError: String?

    let config: Config
    private let scheduler: BreakScheduler
    private let clock: Timekeeper
    private var panel: BreakPanelController?
    private var doneHide: ScheduledTask?
    private var statusTimer: Timer?

    init(config: Config = .standard) {
        self.config = config
        let clock = SystemTimekeeper()
        self.clock = clock
        scheduler = BreakScheduler(config: config, clock: clock)
        scheduler.onEvent = { [unowned self] event in self.handle(event) }
    }

    func start() {
        scheduler.start()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
    }

    // MARK: User actions

    func snooze(_ length: BreakScheduler.SnoozeLength) { scheduler.snooze(length) }
    func decline() { scheduler.decline() }
    func breakNow() { scheduler.breakNow() }
    func togglePause() { isPaused ? scheduler.resume() : scheduler.pause() }
    func systemDidSuspend() { scheduler.systemDidSuspend() }
    func systemDidResume() { scheduler.systemDidResume() }

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
        refreshStatus()
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

    private func refreshStatus() {
        let state = scheduler.state
        let text: String
        let icon: String
        switch state {
        case .stopped:
            text = "Starting…"
            icon = "eye"
        case .idle(let fireAt):
            text = "Next break in \(Self.format(fireAt.timeIntervalSince(clock.now())))"
            icon = "eye"
        case .breaking:
            text = "Break in progress"
            icon = "eye.slash"
        case .snoozed(let until):
            text = "Delayed — back in \(Self.format(until.timeIntervalSince(clock.now())))"
            icon = "eye"
        case .paused(let byUser):
            text = byUser ? "Paused" : "Paused (screen locked)"
            icon = "pause.circle"
        }
        if text != statusText { statusText = text }
        if icon != iconName { iconName = icon }
        let paused = if case .paused = state { true } else { false }
        if paused != isPaused { isPaused = paused }
        let breaking = if case .breaking = state { true } else { false }
        if breaking != isBreaking { isBreaking = breaking }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
