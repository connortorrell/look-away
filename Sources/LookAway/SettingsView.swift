import SwiftUI
import LookAwayCore

/// The settings panel: when reminders are allowed to fire, and when they
/// should get out of the way. Both halves are opt-in and both stay collapsed
/// to a single toggle until switched on, so the panel opens quiet.
struct SettingsView: View {
    /// The window's content width: wide enough for a row of app chips to read
    /// well. The content fills whatever is left of it beside the scroll bar.
    static let width: CGFloat = 460

    let model: AppModel
    @State private var isCustomizingDays: Bool

    /// Opens with the per-day list showing whenever there is something in it.
    init(model: AppModel) {
        self.model = model
        _isCustomizingDays = State(initialValue: !model.schedule.overrides.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                scheduleSection
                Divider().padding(.vertical, 20)
                MeetingSettingsView(model: model)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.snappy(duration: 0.2), value: schedule.isEnabled)
        .animation(.snappy(duration: 0.2), value: isCustomizingDays)
        .animation(.snappy(duration: 0.2), value: schedule.activeDays)
    }

    /// Schedule editor. Everything below the opt-in toggle stays hidden until
    /// the user turns the schedule on, and per-day hours stay hidden until they
    /// ask for them, so the common 9-to-5 case is two controls and nothing else.
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

    // MARK: Sections

    private var header: some View {
        SettingsToggleRow(
            "Only remind me on a schedule",
            detail: "Off means reminders run any time you're at the computer.",
            prominence: .section,
            isOn: binding(\.isEnabled)
        )
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

/// A switch on the trailing edge with its title and explanation on the leading
/// side. Every switch in the panel goes through this so they all share one
/// edge, whatever the length of the text beside them.
struct SettingsToggleRow: View {
    enum Prominence { case section, option }

    let title: String
    let detail: String
    let prominence: Prominence
    @Binding var isOn: Bool

    init(_ title: String, detail: String, prominence: Prominence = .option, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.prominence = prominence
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(prominence == .section ? .headline : .subheadline.weight(.medium))
                Text(detail)
                    .font(prominence == .section ? .subheadline : .footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(title)
        }
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
