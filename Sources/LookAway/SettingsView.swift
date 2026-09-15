import SwiftUI
import LookAwayCore

/// The settings panel: when reminders are allowed to fire, and when they
/// should get out of the way. Both halves are opt-in and both stay collapsed
/// to a single toggle until switched on, so the panel opens quiet.
struct SettingsView: View {
    /// Wide enough for a row of app chips to read well.
    static let width: CGFloat = 460

    let model: AppModel
    /// Makes the AppKit time pickers give up the keyboard. Reports whether one
    /// of them actually had it.
    let endEditing: () -> Bool
    /// Called when Escape is pressed with nothing focused.
    let close: () -> Void
    @State private var isCustomizingDays: Bool
    /// Focus for the app search field, held here so a click anywhere else in
    /// the panel — or Escape — can give it up. Without that there is no way
    /// out of the field once it is in, and its results list stays open.
    @FocusState private var isSearchingApps: Bool

    /// Opens with the per-day list showing whenever there is something in it.
    init(model: AppModel, endEditing: @escaping () -> Bool, close: @escaping () -> Void) {
        self.model = model
        self.endEditing = endEditing
        self.close = close
        _isCustomizingDays = State(initialValue: !model.schedule.overrides.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                scheduleSection
                Divider().padding(.vertical, 20)
                MeetingSettingsView(model: model, isSearching: $isSearchingApps)
            }
            .padding(24)
            .frame(width: Self.width, alignment: .leading)
        }
        // Behind everything, and spanning the whole panel rather than just the
        // content, so a click in the empty space below still counts as one
        // that missed the fields. Controls sit in front and get the click first.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { giveUpFocus() }
        )
        // Escape hands back whatever holds the keyboard; pressed again, with
        // nothing focused, it closes the panel the way Escape usually does.
        .onExitCommand {
            if !giveUpFocus() { close() }
        }
        .animation(.snappy(duration: 0.2), value: schedule.isEnabled)
        .animation(.snappy(duration: 0.2), value: isCustomizingDays)
        .animation(.snappy(duration: 0.2), value: schedule.activeDays)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if schedule.isEnabled {
                Divider().padding(.vertical, 16)
                daysSection
                hoursSection.padding(.top, 20)
                customizeSection.padding(.top, 16)
            }

            Text(schedule.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 18)
        }
    }

    /// Leaves nothing focused, covering both kinds of field in the panel.
    /// Reports whether anything was holding the keyboard to begin with, so
    /// Escape can fall through to closing the window when nothing was.
    @discardableResult
    private func giveUpFocus() -> Bool {
        let wasSearching = isSearchingApps
        isSearchingApps = false
        // Both run: the time pickers are AppKit and answer separately.
        return endEditing() || wasSearching
    }

    // MARK: Sections

    private var header: some View {
        Toggle(isOn: binding(\.isEnabled)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Only remind me on a schedule").font(.headline)
                Text("Off means reminders run any time you're at the computer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel("Days")
            HStack(spacing: 8) {
                ForEach(Weekday.week, id: \.self) { day in
                    DayToggle(
                        day: day,
                        isActive: schedule.isActive(day),
                        hasCustomHours: schedule.hasOverride(day),
                        toggle: { edit { $0.toggleActive(day) } },
                        customize: { customize(day) },
                        useDefaultHours: { edit { $0.removeOverride(for: day) } }
                    )
                }
            }
        }
    }

    private var hoursSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(schedule.overrides.isEmpty ? "Hours" : "Default hours")
            HStack(spacing: 8) {
                TimeField(time: binding(\.hours.start))
                Text("to").foregroundStyle(.secondary)
                TimeField(time: binding(\.hours.end))
            }
            .disabled(schedule.activeDays.isEmpty)

            // The pickers cannot show that the window rolls past midnight.
            if let note = schedule.hours.spanNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The unobtrusive way in: one quiet disclosure row, and the per-day
    /// pickers only exist once it is open.
    @ViewBuilder private var customizeSection: some View {
        if !schedule.activeDays.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    isCustomizingDays.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(isCustomizingDays ? 90 : 0))
                        Text("Different hours on some days")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if isCustomizingDays {
                    VStack(spacing: 6) {
                        ForEach(activeDays, id: \.self) { day in
                            DayHoursRow(
                                day: day,
                                override: overrideBinding(day),
                                defaultHours: schedule.hours,
                                customize: { edit { $0.addOverride(for: day) } },
                                useDefaultHours: { edit { $0.removeOverride(for: day) } }
                            )
                        }
                    }
                    .padding(.leading, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: Editing

    private var schedule: Schedule { model.schedule }

    private var activeDays: [Weekday] { Weekday.week.filter(schedule.isActive) }

    /// Every edit funnels through the model so it is persisted and applied.
    private func edit(_ change: (inout Schedule) -> Void) {
        var updated = schedule
        change(&updated)
        model.updateSchedule(updated)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Schedule, Value>) -> Binding<Value> {
        Binding(get: { schedule[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func overrideBinding(_ day: Weekday) -> Binding<TimeWindow?> {
        Binding(
            get: { schedule.overrides[day] },
            set: { window in
                edit { schedule in
                    if let window {
                        schedule.setOverride(window, for: day)
                    } else {
                        schedule.removeOverride(for: day)
                    }
                }
            }
        )
    }

    /// Reveals the per-day list so a day customized from its circle is visible.
    private func customize(_ day: Weekday) {
        edit { $0.addOverride(for: day) }
        isCustomizingDays = true
    }
}

// MARK: - Pieces

/// One letter in the S M T W T F S row. Click toggles the day; the dot marks a
/// day that has its own hours.
private struct DayToggle: View {
    let day: Weekday
    let isActive: Bool
    let hasCustomHours: Bool
    let toggle: () -> Void
    let customize: () -> Void
    let useDefaultHours: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: toggle) {
                Text(day.initial)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isActive ? Color.accentColor : Color.primary.opacity(0.12))
                    )
                    .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.65))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isActive ? "\(day.name) is scheduled" : "\(day.name) is off")
            .accessibilityLabel(day.name)
            .accessibilityValue(isActive ? "scheduled" : "off")

            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .opacity(hasCustomHours ? 1 : 0)
        }
        .contextMenu {
            if isActive {
                if hasCustomHours {
                    Button("Use Default Hours", action: useDefaultHours)
                } else {
                    Button("Custom Hours…", action: customize)
                }
            }
        }
    }
}

/// A single day inside the customization list: either "same as default" with a
/// way in, or its own pair of time fields with a way back out.
private struct DayHoursRow: View {
    let day: Weekday
    @Binding var override: TimeWindow?
    let defaultHours: TimeWindow
    let customize: () -> Void
    let useDefaultHours: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(day.name)
                    .font(.subheadline)
                // Pickers cannot show a roll past midnight; the label can.
                if let note = override?.shortSpanNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 82, alignment: .leading)

            if let window = override {
                TimeField(time: windowBinding(window).start)
                Text("to").font(.subheadline).foregroundStyle(.secondary)
                TimeField(time: windowBinding(window).end)
                Spacer(minLength: 0)
                Button("Reset", action: useDefaultHours)
                    .buttonStyle(.link)
                    .font(.subheadline)
            } else {
                Text(defaultHours.formatted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Customize", action: customize)
                    .buttonStyle(.link)
                    .font(.subheadline)
            }
        }
        // Picker rows are taller than text rows; one height keeps the rhythm.
        .frame(minHeight: 26)
    }

    private func windowBinding(_ window: TimeWindow) -> (start: Binding<TimeOfDay>, end: Binding<TimeOfDay>) {
        (
            Binding(get: { window.start }, set: { override = TimeWindow(start: $0, end: window.end) }),
            Binding(get: { window.end }, set: { override = TimeWindow(start: window.start, end: $0) })
        )
    }
}

/// Hour/minute stepper field over a `TimeOfDay`.
private struct TimeField: View {
    @Binding var time: TimeOfDay

    var body: some View {
        DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
            .labelsHidden()
            .fixedSize()
    }

    /// `DatePicker` needs a `Date`; the day it sits on is irrelevant.
    private var dateBinding: Binding<Date> {
        let calendar = Calendar.current
        let today = Date()
        return Binding(
            get: { time.date(on: today, calendar: calendar) },
            set: { date in
                if let parsed = TimeOfDay(date: date, calendar: calendar) { time = parsed }
            }
        )
    }
}

/// Shared by both sections of the panel.
struct SettingsSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Presentation

private extension TimeWindow {
    var isAllDay: Bool { start == end }

    var formatted: String {
        if isAllDay { return "All day" }
        let span = "\(start.formatted) – \(end.formatted)"
        return isOvernight ? "\(span) (next day)" : span
    }

    /// Footnote under the shared-hours pickers, or nil for an ordinary day.
    var spanNote: String? {
        if isAllDay { return "Runs all day." }
        if isOvernight { return "Ends the next day." }
        return nil
    }

    /// Same information squeezed under a day name.
    var shortSpanNote: String? {
        if isAllDay { return "all day" }
        if isOvernight { return "ends next day" }
        return nil
    }
}

private extension TimeOfDay {
    var formatted: String {
        date(on: Date(), calendar: .current).formatted(date: .omitted, time: .shortened)
    }
}

private extension Schedule {
    /// One plain-language line describing what is actually going to happen.
    var summary: String {
        guard isEnabled else { return "Reminders run all day, every day." }
        let days = Weekday.week.filter(isActive)
        guard !days.isEmpty else { return "No days selected — reminders are off." }
        let names = days.map { String($0.name.prefix(3)) }.formatted(.list(type: .and))
        guard overrides.isEmpty else { return "Reminders run on \(names), with custom hours on some days." }
        if hours.isAllDay { return "Reminders run all day on \(names)." }
        return "Reminders run on \(names), \(hours.formatted)."
    }
}
