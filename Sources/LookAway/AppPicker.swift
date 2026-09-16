import AppKit
import LookAwayCore
import SwiftUI

/// The app picker shared by the two lists in the settings panel: the meeting
/// apps and the apps that pause reminders on their own. Chosen apps show as
/// removable chips over a search field, with the matching installed apps in a
/// dropdown underneath while the field is in use.

/// The chosen apps as removable chips over a search field, with the matching
/// installed apps listed underneath while the field is in use.
struct AppTokenField: View {
    let apps: [ChosenApp]
    @Binding var query: String
    @FocusState.Binding var isSearching: Bool
    let results: [InstalledApp]
    /// The installed-apps scan has not finished, so an empty `results` means
    /// "not yet" rather than "no match".
    let isLoadingResults: Bool
    /// Names this field's frames in the window's click guard. Two fields share
    /// one panel, so each needs its own entry or the second overwrites the
    /// first and clicks in it start blurring the field.
    let focusRegion: String
    let add: (ChosenApp) -> Void
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
            focusGuard.regions[focusRegion] = frame
        }
    }

    private var resultsDropdown: some View {
        resultList
            .background(fieldBackground(lit: false))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                focusGuard.regions[focusRegion + ".results"] = frame
            }
            .onDisappear { focusGuard.regions[focusRegion + ".results"] = nil }
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
                    if let first = results.first { add(first.chosen) }
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
                        AppResultRow(app: app, add: { add(app.chosen) })
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
struct AppChip: View {
    let app: ChosenApp
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
struct AppResultRow: View {
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
struct FlowLayout: Layout {
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
