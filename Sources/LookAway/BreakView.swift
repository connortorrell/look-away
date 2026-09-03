import SwiftUI
import LookAwayCore

struct BreakView: View {
    let model: AppModel

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

            Text(model.breakPhase == .done
                 ? "Nice. Back to it."
                 : "Look at something 20 feet away")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Delay 5 min") { model.snooze(.short) }
                Button("Delay 10 min") { model.snooze(.long) }
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
