import SwiftUI
import LookAwayCore

struct BreakView: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: model.breakPhase == .done ? "checkmark.circle" : "eye")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            Text(model.breakPhase == .done ? "Done" : "\(model.remainingSeconds)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: model.remainingSeconds)
                .frame(minHeight: 84)

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)

            if let verse = model.currentVerse {
                VerseText(verse: verse)
                    .opacity(isVerseDimmed ? VerseSettings.dimmedOpacity : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: isVerseDimmed)
            }

            HStack(spacing: 10) {
                Button("Delay 5 min") { model.snooze() }
                Button("Decline") { model.decline() }
                    .buttonStyle(PanelButtonStyle(role: .quiet))
            }
            .buttonStyle(PanelButtonStyle(role: .normal))
            .opacity(model.breakPhase == .done ? 0 : 1)
            .disabled(model.breakPhase == .done)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 32)
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// The opening seconds of a break with a verse, meant for reading it.
    /// Taken from the countdown itself, so there is no second clock to keep
    /// in step.
    private var isReading: Bool {
        model.currentVerse != nil
            && model.breakPhase == .counting
            && model.remainingSeconds > model.config.breakSeconds - VerseSettings.readingTime
    }

    /// Dimmed, not hidden, once the reading time is up: the point is to look
    /// away, but a glance back should still find the words.
    private var isVerseDimmed: Bool {
        model.breakPhase == .counting && !isReading
    }

    private var subtitle: String {
        if model.breakPhase == .done { return "Nice. Back to it." }
        return isReading ? "Read, then look away and meditate" : "Look at something 20 feet away"
    }
}

/// A verse and its reference, set apart from the countdown's rounded type.
private struct VerseText: View {
    let verse: Verse

    var body: some View {
        VStack(spacing: 8) {
            Text(verse.text)
                .font(.system(.title2, design: .serif))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !verse.reference.isEmpty {
                Text(verse.reference)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Explicit styling so buttons look the same whether or not the panel is key.
struct PanelButtonStyle: ButtonStyle {
    enum Role { case normal, quiet }
    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                Capsule().fill(role == .normal
                               ? Color.accentColor.opacity(configuration.isPressed ? 0.6 : 0.85)
                               : Color.primary.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
            .foregroundStyle(role == .normal ? Color.white : Color.primary)
            .contentShape(Capsule())
    }
}
