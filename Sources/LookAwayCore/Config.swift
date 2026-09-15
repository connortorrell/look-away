import Foundation

/// All durations the app uses, expressed in the unit they were always in.
/// Change values here and rebuild.
public struct Config: Sendable, Equatable {
    /// Screen time between breaks. One full Minecraft day.
    public var workInterval: TimeInterval
    /// Length of the look-away countdown, in whole seconds.
    public var breakSeconds: Int
    /// How long "Sleep" hides the popup before it returns.
    public var snoozeInterval: TimeInterval

    public init(workInterval: TimeInterval, breakSeconds: Int, snoozeInterval: TimeInterval) {
        self.workInterval = workInterval
        self.breakSeconds = breakSeconds
        self.snoozeInterval = snoozeInterval
    }

    /// Ticks between breaks, for anything that would rather not think in
    /// seconds.
    public var workTicks: Int { MinecraftTime.ticks(seconds: workInterval) }
    /// Ticks in the countdown.
    public var breakTicks: Int { MinecraftTime.ticks(seconds: TimeInterval(breakSeconds)) }

    /// The 20/20/20 rule, which is one Minecraft day, a 400 tick look-away,
    /// and a quarter-day lie-down. The real numbers are unchanged from 1.0 —
    /// they simply have correct names now.
    public static let standard = Config(
        workInterval: MinecraftTime.seconds(ticks: MinecraftTime.ticksPerDay),
        breakSeconds: 20,
        snoozeInterval: MinecraftTime.seconds(ticks: MinecraftTime.ticksPerDay / 4)
    )
}
