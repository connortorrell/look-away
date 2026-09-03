import Foundation
import ServiceManagement

enum LaunchAtLogin {
    private static let registeredKey = "didRegisterLoginItem"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Default-on behaviour: register once, and only when running from
    /// /Applications so a dev build in ./build never becomes the login item.
    static func registerOnFirstInstalledLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: registeredKey) else { return }
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        try? SMAppService.mainApp.register()
        defaults.set(true, forKey: registeredKey)
    }
}
