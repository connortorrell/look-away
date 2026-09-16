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
                add: { app in
                    edit { $0.add(app) }
                    query = ""
                },
                remove: { bundleID in edit { $0.remove(bundleID) } }
            )
            // The results dropdown hangs below the field, over the footnote.
            .zIndex(1)
            Text(appsFootnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // And over the sections below this one.
        .zIndex(1)
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
        model.installedApps.matches(query, excluding: settings)
    }

    private var appsFootnote: String {
        guard !settings.apps.isEmpty else {
            return "No apps chosen, so nothing will be detected as a meeting."
        }
        return "Detected from real microphone and camera use — not from which app is in front."
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

// MARK: - Token field

/// The chosen apps as removable chips over a search field, with the matching
/// installed apps listed underneath while the field is in use.
private struct AppTokenField: View {
    let apps: [MeetingApp]
    @Binding var query: String
    @FocusState.Binding var isSearching: Bool
    let results: [InstalledApp]
    /// The installed-apps scan has not finished, so an empty `results` means
    /// "not yet" rather than "no match".
    let isLoadingResults: Bool
    let add: (MeetingApp) -> Void
    let remove: (String) -> Void
    @Environment(ClickFocusGuard.self) private var focusGuard
    /// Height of the chips-and-field box, which is where the dropdown hangs from.
    @State private var fieldHeight: CGFloat = 0
    /// Height the result rows would like; the list scrolls once it is capped.
    @State private var resultsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !apps.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(apps) { app in
                        AppChip(app: app, remove: { remove(app.bundleID) })
                    }
                }
            }
            searchField
        }
        .padding(8)
        .background(fieldBackground(lit: isSearching))
        // The results float over whatever is below rather than pushing it
        // down: opening and closing the list then moves nothing else in the
        // panel, so a switch clicked while the list is open is still under
        // the pointer when the mouse comes back up.
        .overlay(alignment: .top) {
            if isSearching {
                resultsDropdown
                    .offset(y: fieldHeight + 4)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.15), value: isSearching)
        // A click anywhere in here — a result, a chip, the field — keeps the
        // field focused, so several apps can be added in a row and a result
        // is still where it was when the mouse comes back up.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            fieldHeight = frame.height
            focusGuard.regions["apps"] = frame
        }
    }

    private var resultsDropdown: some View {
        resultList
            .background(fieldBackground(lit: false))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                focusGuard.regions["appResults"] = frame
            }
            .onDisappear { focusGuard.regions["appResults"] = nil }
    }

    private func fieldBackground(lit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(lit ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
            )
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search installed apps…", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearching)
                // Enter takes the top match, so a full name can be typed
                // without reaching for the mouse.
                .onSubmit {
                    if let first = results.first { add(first.meetingApp) }
                }
        }
    }

    private var emptyResultsMessage: String {
        if isLoadingResults { return "Looking for installed apps…" }
        if query.isEmpty { return "Every installed app is already in the list." }
        return "No app matches “\(query)”."
    }

    @ViewBuilder private var resultList: some View {
        if results.isEmpty {
            Text(emptyResultsMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { app in
                        AppResultRow(app: app, add: { add(app.meetingApp) })
                    }
                }
                .padding(4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resultsHeight = $0 }
            }
            // A scroll view takes whatever height it is offered, so it is
            // sized to its rows here: tall enough to browse, short enough to
            // leave the panel usable.
            .frame(height: min(resultsHeight, 176))
        }
    }
}

/// One chosen app. The whole chip carries the app's ID as its tooltip, since
/// two apps can share a display name.
private struct AppChip: View {
    let app: MeetingApp
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(app.name).font(.subheadline)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    // The glyph is tiny; the target it sits in is not.
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(app.name)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 1)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.primary.opacity(0.09)))
        .help(app.bundleID)
    }
}

/// One row of the search results, with the app's real icon so near-identical
/// names are still tellable apart.
private struct AppResultRow: View {
    let app: InstalledApp
    let add: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(app.name).font(.subheadline)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(app.bundleID)
    }
}

// MARK: - Layout

/// Left-aligned wrapping row of views, for the chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, in: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
