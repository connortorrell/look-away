import LookAwayCore
import SwiftUI

/// Meeting editor: one opt-in toggle, and — once it is on — the list of apps
/// that count as a meeting plus the two knobs worth exposing. Laid out like the
/// schedule section above it, so the panel reads as one thing.
struct MeetingSettingsView: View {
    let model: AppModel
    /// Cleared by the window whenever it takes the keyboard back — Esc, or a
    /// click anywhere that is not a field — so the results list never sticks.
    @FocusState private var isSearching: Bool

    @State private var query = ""
    /// Opens with the listen-only option showing whenever it is switched on.
    @State private var isShowingListenOnly: Bool

    init(model: AppModel) {
        self.model = model
        _isShowingListenOnly = State(initialValue: model.meetingSettings.countsAudioOutput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if settings.isEnabled {
                appsSection.padding(.top, 20)
                delaySection.padding(.top, 20)
                cameraToggle.padding(.top, 14)
                listenOnlySection.padding(.top, 16)
            }

            summary.padding(.top, 18)
        }
        .animation(.snappy(duration: 0.2), value: settings.isEnabled)
        .animation(.snappy(duration: 0.2), value: settings.apps)
        .animation(.snappy(duration: 0.2), value: isShowingListenOnly)
        .onAppear { model.prepareMeetingSettings() }
        // Leaving the field puts it back to its placeholder, so clicking in
        // again never opens onto a stale search.
        .onChange(of: isSearching) { _, isFocused in
            if !isFocused { query = "" }
        }
    }

    // MARK: Sections

    private var header: some View {
        SettingsToggleRow(
            "Pause reminders during meetings",
            detail: "Holds the popup while you're on a call in one of the apps you choose.",
            prominence: .section,
            isOn: binding(\.isEnabled)
        )
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel("Apps that count as a meeting")
            AppTokenField(
                apps: settings.apps,
                query: $query,
                isSearching: $isSearching,
                results: results,
                isLoadingResults: !model.installedApps.isLoaded,
                focusRegion: "meetingApps",
                add: { app in
                    edit { $0.add(app) }
                    query = ""
                },
                remove: { bundleID in edit { $0.remove(bundleID) } }
            )
            // The results dropdown hangs below the field, over the footnote.
            .zIndex(1)
            Text("Detected from real microphone and camera use — not from which app is in front.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // And over the sections below this one.
        .zIndex(1)
    }

    /// One plain-language line at the foot of the section, like the schedule's:
    /// what will happen, and — since detection is invisible until it holds a
    /// break — what it sees right now.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if model.meetingInProgress != nil {
                Image(systemName: "video.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
            Text(summaryText)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var delaySection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Detection delay").font(.subheadline.weight(.medium))
                Text("How long the signal has to hold before it counts.")
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
        SettingsToggleRow(
            "Count camera use too",
            detail: "Keeps you covered while muted but on video in a meeting app. Browsers are left out, so a website using the camera doesn't count.",
            isOn: binding(\.countsCamera)
        )
    }

    /// The weakest signal stays out of the way, like the per-day hours in the
    /// schedule section: one quiet row, and the toggle only exists once it is
    /// open.
    private var listenOnlySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsDisclosureButton("Also detect listen-only calls", isExpanded: $isShowingListenOnly)

            if isShowingListenOnly {
                audioOutputToggle
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Off by default, and honest about the cost of turning it on.
    private var audioOutputToggle: some View {
        SettingsToggleRow(
            "Count audio playing too",
            detail: "Catches listen-only calls. May also pause for videos and notification sounds.",
            isOn: binding(\.countsAudioOutput)
        )
    }

    // MARK: Data

    private var settings: MeetingSettings { model.meetingSettings }

    private var results: [InstalledApp] {
        model.installedApps.matches(query, excluding: settings.apps)
    }

    private var summaryText: String {
        guard settings.isEnabled else { return "Reminders run through calls." }
        guard !settings.apps.isEmpty else { return "No apps chosen, so calls won't hold reminders." }
        if let meeting = model.meetingInProgress {
            return "\(meeting.app.name) is on a call. Reminders are held until it ends."
        }
        return "Not in a meeting right now. Calls in \(chosenAppNames) will hold reminders."
    }

    /// "Zoom, Slack and FaceTime", or "Zoom, Microsoft Teams and 4 other apps"
    /// once the list would run long.
    private var chosenAppNames: String {
        let names = settings.apps.map(\.name)
        guard names.count > 3 else { return names.formatted(.list(type: .and)) }
        return (names.prefix(2) + ["\(names.count - 2) other apps"]).formatted(.list(type: .and))
    }

    private static func label(for delay: TimeInterval) -> String {
        if delay == 0 { return "Immediately" }
        return delay < 60 ? "\(Int(delay)) sec" : "\(Int(delay / 60)) min"
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
