import Foundation

/// All durations the app uses. Change values here and rebuild.
public struct Config: Sendable, Equatable {
    /// Screen time between breaks.
    public var workInterval: TimeInterval
    /// Length of the look-away countdown, in whole seconds.
    public var breakSeconds: Int
    /// Snooze lengths offered on the popup.
    public var shortSnooze: TimeInterval
    public var longSnooze: TimeInterval

    public init(workInterval: TimeInterval, breakSeconds: Int, shortSnooze: TimeInterval, longSnooze: TimeInterval) {
        self.workInterval = workInterval
        self.breakSeconds = breakSeconds
        self.shortSnooze = shortSnooze
        self.longSnooze = longSnooze
    }

    /// The 20/20/20 rule with 5 and 10 minute snoozes.
    public static let standard = Config(
        workInterval: 20 * 60,
        breakSeconds: 20,
        shortSnooze: 5 * 60,
        longSnooze: 10 * 60
    )
}
