import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(model.statusText)

        Divider()

        Button(model.isPaused ? "Resume Reminders" : "Pause Reminders") {
            model.togglePause()
        }
        Button("Take a Break Now") {
            model.breakNow()
        }
        .disabled(model.isBreaking)

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLogin($0) }
        ))
        if let error = model.launchAtLoginError {
            Text(error).font(.caption)
        }

        Divider()

        Button("Quit Look Away") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
