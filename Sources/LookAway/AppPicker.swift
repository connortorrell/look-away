import AppKit
import LookAwayCore
import SwiftUI

/// The app picker shared by the two lists in the settings panel: the meeting
/// apps and the apps that pause reminders on their own. Chosen apps show as
/// removable chips over a search field, with the matching installed apps
/// listed underneath while the field is in use.

struct AppTokenField: View {
    let apps: [ChosenApp]
    @Binding var query: String
    @FocusState.Binding var isSearching: Bool
    let results: [InstalledApp]
    let add: (ChosenApp) -> Void
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
                    if let first = results.first { add(first.chosen) }
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
                        AppResultRow(app: app, add: { add(app.chosen) })
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
struct AppChip: View {
    let app: ChosenApp
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
