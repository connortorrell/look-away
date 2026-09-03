import AppKit
import Observation

/// Menu bar item and dropdown, built with AppKit so the status line can tick
/// live while the menu is open. (SwiftUI's menu-style MenuBarExtra blocks
/// updates for as long as the menu is showing.)
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "", action: #selector(togglePause), keyEquivalent: "")
    private let breakNowItem = NSMenuItem(title: "Take a Break Now", action: #selector(breakNow), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let loginErrorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var refreshTimer: Timer?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        buildMenu()
        statusItem.menu = menu
        observeIcon()
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        statusLine.isEnabled = false
        loginErrorItem.isEnabled = false
        loginErrorItem.isHidden = true

        let quitItem = NSMenuItem(title: "Quit Look Away", action: #selector(quit), keyEquivalent: "q")

        for item in [pauseItem, breakNowItem, loginItem, quitItem] {
            item.target = self
        }

        menu.items = [
            statusLine,
            .separator(),
            pauseItem,
            breakNowItem,
            .separator(),
            loginItem,
            loginErrorItem,
            .separator(),
            quitItem,
        ]
        refreshItems()
    }

    // MARK: Live updates

    func menuWillOpen(_ menu: NSMenu) {
        refreshItems()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshItems() }
        }
        // Menu tracking runs the loop in event-tracking mode; .common covers it.
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshItems() {
        statusLine.title = model.statusText
        pauseItem.title = model.isPaused ? "Resume Reminders" : "Pause Reminders"
        breakNowItem.isEnabled = !model.isBreaking
        loginItem.state = model.launchAtLoginEnabled ? .on : .off
        loginErrorItem.title = model.launchAtLoginError ?? ""
        loginErrorItem.isHidden = model.launchAtLoginError == nil
    }

    /// Re-applies the icon whenever `model.iconName` changes.
    private func observeIcon() {
        withObservationTracking {
            let image = NSImage(systemSymbolName: model.iconName, accessibilityDescription: "Look Away")
            image?.isTemplate = true
            statusItem.button?.image = image
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeIcon() }
        }
    }

    // MARK: Actions

    @objc private func togglePause() { model.togglePause() }
    @objc private func breakNow() { model.breakNow() }
    @objc private func toggleLaunchAtLogin() { model.setLaunchAtLogin(!model.launchAtLoginEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }
}
