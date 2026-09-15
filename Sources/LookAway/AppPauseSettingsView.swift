import LookAwayCore
import SwiftUI

/// Pause-list editor: one opt-in toggle, and — once it is on — the apps that
/// hold reminders back just by being the app you are in. Laid out like the two
/// sections above it, so the panel reads as one thing.
struct AppPauseSettingsView: View {
    let model: AppModel
    /// Owned by `SettingsView`, which needs to be able to clear it when a
    /// click lands anywhere else in the panel.
    @FocusState.Binding var isSearching: Bool

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if settings.isEnabled {
                appsSection.padding(.top, 20)
            }
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
        Toggle(isOn: binding(\.isEnabled)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pause reminders in certain apps").font(.headline)
                Text("Holds the popup while one of the apps below is the app you're in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel("Apps that pause reminders")
            AppTokenField(
                apps: settings.apps,
                query: $query,
                isSearching: $isSearching,
                results: results,
                add: { app in
                    edit { $0.add(app) }
                    query = ""
                },
                remove: { bundleID in edit { $0.remove(bundleID) } }
            )
            Text(appsFootnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Data

    private var settings: AppPauseSettings { model.appPauseSettings }

    private var results: [InstalledApp] {
        model.installedApps.matches(query, excluding: settings.apps)
    }

    private var appsFootnote: String {
        guard !settings.apps.isEmpty else {
            return "No apps chosen, so nothing here will pause reminders."
        }
        return "Nothing is asked of the microphone or the camera — only which app is in front. Reminders come back \(Int(AppPauseSettings.leaveGrace)) seconds after you leave."
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
