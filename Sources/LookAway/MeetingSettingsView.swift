import LookAwayCore
import SwiftUI

/// Meeting editor: one opt-in toggle, and — once it is on — the list of apps
/// that count as a meeting plus the two knobs worth exposing. Laid out like the
/// schedule section above it, so the panel reads as one thing.
struct MeetingSettingsView: View {
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
                delaySection.padding(.top, 20)
                cameraToggle.padding(.top, 14)
                audioOutputToggle.padding(.top, 14)
            }
        }
        .animation(.snappy(duration: 0.2), value: settings.isEnabled)
        .animation(.snappy(duration: 0.2), value: settings.apps)
        .onAppear { model.prepareMeetingSettings() }
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
                Text("Pause reminders during meetings").font(.headline)
                Text("Holds the popup while one of the apps below is using the mic or camera.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel("Apps that count as a meeting")
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

    private var delaySection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Detection delay").font(.subheadline.weight(.medium))
                Text("How long the mic has to stay busy before it counts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Picker("", selection: binding(\.detectionDelay)) {
                ForEach(MeetingSettings.detectionDelayChoices, id: \.self) { delay in
                    Text(Self.label(for: delay)).tag(delay)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var cameraToggle: some View {
        Toggle(isOn: binding(\.countsCamera)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Count camera use too").font(.subheadline.weight(.medium))
                Text("Keeps you covered while muted but on video.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    /// Off by default, and honest about the cost of turning it on.
    private var audioOutputToggle: some View {
        Toggle(isOn: binding(\.countsAudioOutput)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Count audio playing too").font(.subheadline.weight(.medium))
                Text("Catches listen-only calls. May also pause for videos and notification sounds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: Data

    private var settings: MeetingSettings { model.meetingSettings }

    private var results: [InstalledApp] {
        model.installedApps.matches(query, excluding: settings.apps)
    }

    private var appsFootnote: String {
        guard !settings.apps.isEmpty else {
            return "No apps chosen, so nothing will be detected as a meeting."
        }
        return "Detected from real microphone and camera use — not from which app is in front."
    }

    private static func label(for delay: TimeInterval) -> String {
        delay == 0 ? "Immediately" : "\(Int(delay)) sec"
    }

    private func edit(_ change: (inout MeetingSettings) -> Void) {
        var updated = settings
        change(&updated)
        model.updateMeetingSettings(updated)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MeetingSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in edit { $0[keyPath: keyPath] = value } }
        )
    }
}
