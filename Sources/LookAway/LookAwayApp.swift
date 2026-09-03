import SwiftUI

@main
struct LookAwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: appDelegate.model)
        } label: {
            Image(systemName: appDelegate.model.iconName)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var systemEvents: SystemEvents?

    func applicationDidFinishLaunching(_ notification: Notification) {
        systemEvents = SystemEvents(
            onSuspend: { [model] in model.systemDidSuspend() },
            onResume: { [model] in model.systemDidResume() }
        )
        LaunchAtLogin.registerOnFirstInstalledLaunch()
        model.refreshLaunchAtLogin()
        model.start()
    }
}
