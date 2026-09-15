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
        model.installedApps.matches(query, excluding: settings)
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

// MARK: - Token field

/// The chosen apps as removable chips over a search field, with the matching
/// installed apps listed underneath while the field is in use.
private struct AppTokenField: View {
    let apps: [MeetingApp]
    @Binding var query: String
    @FocusState.Binding var isSearching: Bool
    let results: [InstalledApp]
    let add: (MeetingApp) -> Void
    let remove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            if isSearching {
                Divider()
                resultList
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSearching ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
        )
        .animation(.snappy(duration: 0.15), value: isSearching)
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

    @ViewBuilder private var resultList: some View {
        if results.isEmpty {
            Text(query.isEmpty ? "Looking for installed apps…" : "No app matches “\(query)”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { app in
                        AppResultRow(app: app, add: { add(app.meetingApp) })
                    }
                }
                .padding(4)
            }
            // Tall enough to browse, short enough to leave the panel usable.
            .frame(maxHeight: 176)
        }
    }
}

/// One chosen app. The whole chip carries the app's ID as its tooltip, since
/// two apps can share a display name.
private struct AppChip: View {
    let app: MeetingApp
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(app.name).font(.subheadline)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(app.name)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
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
