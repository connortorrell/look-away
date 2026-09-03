import Foundation

/// All durations the app uses. Change values here and rebuild.
public struct Config: Sendable, Equatable {
    /// Screen time between breaks.
    public var workInterval: TimeInterval
    /// Length of the look-away countdown, in whole seconds.
    public var breakSeconds: Int
    /// How long "Delay" hides the popup before it returns.
    public var snoozeInterval: TimeInterval

    public init(workInterval: TimeInterval, breakSeconds: Int, snoozeInterval: TimeInterval) {
        self.workInterval = workInterval
        self.breakSeconds = breakSeconds
        self.snoozeInterval = snoozeInterval
    }

    /// The 20/20/20 rule with a 5 minute snooze.
    public static let standard = Config(
        workInterval: 20 * 60,
        breakSeconds: 20,
        snoozeInterval: 5 * 60
    )
}
