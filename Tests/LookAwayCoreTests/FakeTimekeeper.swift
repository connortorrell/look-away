import Foundation
import LookAwayCore

/// Deterministic clock. Time only moves when a test calls `advance(by:)`,
/// firing scheduled tasks in order as it passes them.
@MainActor
final class FakeTimekeeper: Timekeeper {
    private(set) var current = Date(timeIntervalSinceReferenceDate: 0)
    private var tasks: [Task] = []

    final class Task: ScheduledTask {
        let fireAt: Date
        let action: @MainActor () -> Void
        var cancelled = false
        init(fireAt: Date, action: @escaping @MainActor () -> Void) {
            self.fireAt = fireAt
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    func now() -> Date { current }

    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledTask {
        let task = Task(fireAt: current.addingTimeInterval(interval), action: action)
        tasks.append(task)
        return task
    }

    func advance(by interval: TimeInterval) {
        let target = current.addingTimeInterval(interval)
        while let next = tasks.filter({ !$0.cancelled }).min(by: { $0.fireAt < $1.fireAt }), next.fireAt <= target {
            tasks.removeAll { $0 === next }
            current = next.fireAt
            next.action()
        }
        tasks.removeAll { $0.cancelled }
        current = target
    }

    var pendingCount: Int { tasks.filter { !$0.cancelled }.count }
}
