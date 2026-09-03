import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusMenu: StatusMenuController?
    private var systemEvents: SystemEvents?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenuController(model: model)
        systemEvents = SystemEvents(
            onSuspend: { [model] in model.systemDidSuspend() },
            onResume: { [model] in model.systemDidResume() }
        )
        LaunchAtLogin.registerOnFirstInstalledLaunch()
        model.refreshLaunchAtLogin()
        model.start()
    }
}
