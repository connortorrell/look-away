import Foundation

/// A handle to a scheduled callback that can be cancelled before it fires.
@MainActor
public protocol ScheduledTask {
    func cancel()
}

/// Source of time and one-shot timers. Injected so the scheduler can be
/// tested deterministically with a fake.
@MainActor
public protocol Timekeeper: AnyObject {
    func now() -> Date
    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledTask
}

/// Real implementation backed by the main dispatch queue.
@MainActor
public final class SystemTimekeeper: Timekeeper {
    public init() {}

    public func now() -> Date { Date() }

    public func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledTask {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, interval), execute: item)
        return DispatchTask(item: item)
    }

    private struct DispatchTask: ScheduledTask {
        let item: DispatchWorkItem
        func cancel() { item.cancel() }
    }
}
