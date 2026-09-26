import LookAwayCore
import SwiftUI

/// Verse editor: one opt-in toggle, and — once it is on — a choice between the
/// built-in verse of the day and a list of your own. Laid out like the other
/// sections, down to the status line at the foot.
struct VerseSettingsView: View {
    let model: AppModel

    /// The verse being edited, or nil while the form below the list adds a
    /// new one.
    @State private var editingID: Verse.ID?
    @State private var draftText = ""
    @State private var draftReference = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if settings.isEnabled {
                sourcePicker.padding(.top, 20)
                Group {
                    switch settings.source {
                    case .dailyVerse: dailySection
                    case .myVerses: myVersesSection
                    }
                }
                .padding(.top, 16)
            }

            summary.padding(.top, 18)
        }
        .animation(.snappy(duration: 0.2), value: settings.isEnabled)
        .animation(.snappy(duration: 0.2), value: settings.source)
        .animation(.snappy(duration: 0.2), value: settings.myVerses)
    }

    // MARK: Sections

    private var header: some View {
        SettingsToggleRow(
            "Show a verse during breaks",
            detail: "Something to meditate on while you look away. Read it, then rest your eyes on it.",
            prominence: .section,
            isOn: binding(\.isEnabled)
        )
    }

    private var sourcePicker: some View {
        Picker("Verses", selection: binding(\.source)) {
            Text("Verse of the day").tag(VerseSource.dailyVerse)
            Text("My verses").tag(VerseSource.myVerses)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel("Today")
            VersePreview(verse: DailyVerses.verse(on: Date()))
            Text("A new verse each day, the same one at every break. From the Berean Standard Bible, which is in the public domain.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var myVersesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel("My verses")
            if !settings.myVerses.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(settings.myVerses.enumerated()), id: \.element.id) { index, verse in
                        row(for: verse, at: index)
                    }
                }
            }
            editor.padding(.top, settings.myVerses.isEmpty ? 0 : 6)
            Text("Shown one per break, in this order. Drag to reorder. A delayed or declined break brings the same verse back.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(for verse: Verse, at index: Int) -> some View {
        MyVerseRow(
            verse: verse,
            isNext: settings.isRotating && index == settings.nextIndex,
            isEditing: editingID == verse.id,
            canMoveUp: index > 0,
            canMoveDown: index < settings.myVerses.count - 1,
            edit: { startEditing(verse) },
            moveUp: { edit { $0.move(verse.id, to: index - 1) } },
            moveDown: { edit { $0.move(verse.id, to: index + 2) } },
            delete: {
                if editingID == verse.id { clearDraft() }
                edit { $0.remove(verse.id) }
            }
        )
        .draggable(verse.id.uuidString) {
            VersePreview(verse: verse).frame(width: 300)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)),
                  let source = settings.myVerses.firstIndex(where: { $0.id == id }),
                  source != index
            else { return false }
            // Dropped on a row, a verse takes that row's place: after it when
            // coming from above, before it when coming from below.
            edit { $0.move(id, to: source < index ? index + 1 : index) }
            return true
        }
    }

    /// Adds a verse, or saves the one being edited. A long verse is still
    /// accepted; the count only warns.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Type or paste a verse", text: $draftText, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                TextField("Reference (optional)", text: $draftReference)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitDraft)
                Text("\(trimmedText.count)/\(VerseSettings.softLimit)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(isTooLong ? Color.orange : Color.secondary)
                    .help(isTooLong ? "Long verses are hard to take in at a glance." : "")
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if editingID != nil {
                    Button("Cancel", action: clearDraft)
                }
                Button(editingID == nil ? "Add Verse" : "Save", action: commitDraft)
                    .disabled(trimmedText.isEmpty)
            }
        }
    }

    /// One plain-language line at the foot of the section, like the others.
    private var summary: some View {
        Text(summaryText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Data

    private var settings: VerseSettings { model.verseSettings }

    private var trimmedText: String { draftText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isTooLong: Bool { trimmedText.count > VerseSettings.softLimit }

    private var summaryText: String {
        guard settings.isEnabled else { return "Breaks show only the countdown." }
        switch settings.source {
        case .dailyVerse:
            return "Every break today shows \(DailyVerses.verse(on: Date()).reference)."
        case .myVerses:
            guard settings.isRotating else { return "No verses yet, so breaks show the verse of the day." }
            return "The next break shows \(Self.name(for: settings.myVerses[settings.nextIndex])), then moves on once it finishes."
        }
    }

    /// A verse's reference, or its opening words when it has none.
    private static func name(for verse: Verse) -> String {
        guard verse.reference.isEmpty else { return verse.reference }
        let words = verse.text.split(separator: " ")
        let opening = words.prefix(5).joined(separator: " ")
        return "“\(opening)\(words.count > 5 ? "…" : "")”"
    }

    private func startEditing(_ verse: Verse) {
        editingID = verse.id
        draftText = verse.text
        draftReference = verse.reference
    }

    private func commitDraft() {
        guard !trimmedText.isEmpty else { return }
        let reference = draftReference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingID {
            edit { $0.update(Verse(id: editingID, text: trimmedText, reference: reference)) }
        } else {
            edit { $0.add(Verse(text: trimmedText, reference: reference)) }
        }
        clearDraft()
    }

    private func clearDraft() {
        editingID = nil
        draftText = ""
        draftReference = ""
    }

    private func edit(_ change: (inout VerseSettings) -> Void) {
        var updated = settings
        change(&updated)
        model.updateVerseSettings(updated)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<VerseSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in edit { $0[keyPath: keyPath] = value } }
        )
    }
}

/// A verse set the way the popup sets it, on a quiet card.
private struct VersePreview: View {
    let verse: Verse

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verse.text)
                .font(.system(.body, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            if !verse.reference.isEmpty {
                Text(verse.reference)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// One of your verses: its opening lines and reference, a marker on the one
/// the next break shows, and a menu for everything else.
private struct MyVerseRow: View {
    let verse: Verse
    let isNext: Bool
    let isEditing: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let edit: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verse.text)
                    .font(.system(.subheadline, design: .serif))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !verse.reference.isEmpty {
                        Text(verse.reference)
                    }
                    if isNext {
                        Text("Next")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Edit", action: edit)
                Button("Move Up", action: moveUp).disabled(!canMoveUp)
                Button("Move Down", action: moveDown).disabled(!canMoveDown)
                Divider()
                Button("Delete", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for \(verse.reference.isEmpty ? "verse" : verse.reference)")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isEditing ? 0.12 : 0.06))
        )
        .contentShape(Rectangle())
    }
}
