import LookAwayCore
import SwiftUI

/// Pause-list editor: one opt-in toggle, and — once it is on — the apps that
/// hold reminders back just by being the app you are in. Laid out like the two
/// sections above it, down to the status line at the foot, so the panel reads
/// as one thing.
struct AppPauseSettingsView: View {
    let model: AppModel
    /// Cleared by the window whenever it takes the keyboard back — Esc, or a
    /// click anywhere that is not a field — so the results list never sticks.
    @FocusState private var isSearching: Bool

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if settings.isEnabled {
                appsSection.padding(.top, 20)
            }

            summary.padding(.top, 18)
        }
        .animation(.snappy(duration: 0.2), value: settings.isEnabled)
        .animation(.snappy(duration: 0.2), value: settings.apps)
        .onAppear { model.loadInstalledApps() }
        // Leaving the field puts it back to its placeholder, so clicking in
        // again never opens onto a stale search.
        .onChange(of: isSearching) { _, isFocused in
            if !isFocused { query = "" }
        }
    }

    // MARK: Sections

    private var header: some View {
        SettingsToggleRow(
            "Pause reminders in certain apps",
            detail: "Holds the popup while one of the apps below is in front.",
            prominence: .section,
            isOn: binding(\.isEnabled)
        )
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel("Apps that pause reminders")
            AppTokenField(
                apps: settings.apps,
                query: $query,
                isSearching: $isSearching,
                results: results,
                isLoadingResults: !model.installedApps.isLoaded,
                focusRegion: "pauseApps",
                add: { app in
                    edit { $0.add(app) }
                    query = ""
                },
                remove: { bundleID in edit { $0.remove(bundleID) } }
            )
            // The results dropdown hangs below the field, over the footnote.
            .zIndex(1)
            Text("Counts only while the app is in front. Kicks in after \(Int(AppPauseSettings.settleDelay)) seconds; reminders come back \(Int(AppPauseSettings.leaveGrace)) seconds after you leave.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // And over the summary below it.
        .zIndex(1)
    }

    /// One plain-language line at the foot of the section, like the meeting
    /// section's: what will happen, and what detection sees right now.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if model.appInFront != nil {
                Image(systemName: "macwindow")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
            Text(summaryText)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Data

    private var settings: AppPauseSettings { model.appPauseSettings }

    private var results: [InstalledApp] {
        model.installedApps.matches(query, excluding: settings.apps, frontmostOnly: true)
    }

    private var summaryText: String {
        guard settings.isEnabled else { return "Reminders run whatever app is in front." }
        guard !settings.apps.isEmpty else { return "No apps chosen, so nothing here will pause reminders." }
        if let app = model.appInFront {
            return "\(app.name) is in front. Reminders are held until you leave it."
        }
        return "Not in a chosen app right now. Reminders will hold while \(chosenAppNames) is in front."
    }

    /// "Minecraft or Steam", or "Minecraft, Steam or 4 other apps" once the
    /// list would run long.
    private var chosenAppNames: String {
        let names = settings.apps.map(\.name)
        guard names.count > 3 else { return names.formatted(.list(type: .or)) }
        return (names.prefix(2) + ["\(names.count - 2) other apps"]).formatted(.list(type: .or))
    }

    private func edit(_ change: (inout AppPauseSettings) -> Void) {
        var updated = settings
        change(&updated)
        model.updateAppPauseSettings(updated)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppPauseSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in edit { $0[keyPath: keyPath] = value } }
        )
    }
}
