import AppKit

/// Forwards sleep/wake and screen lock/unlock to the scheduler.
@MainActor
final class SystemEvents {
    /// Lives for the whole process; observers are never removed.
    private var tokens: [NSObjectProtocol] = []

    init(onSuspend: @escaping @MainActor () -> Void, onResume: @escaping @MainActor () -> Void) {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(workspace, NSWorkspace.willSleepNotification, onSuspend)
        observe(workspace, NSWorkspace.didWakeNotification, onResume)
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), onSuspend)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), onResume)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        tokens.append(token)
    }
}
