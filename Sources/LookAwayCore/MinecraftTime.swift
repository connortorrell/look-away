import Foundation

/// Minecraft time, which is the only time this app has ever actually kept.
///
/// The game runs at 20 ticks per second and a full day-night cycle is 24000
/// ticks. That is exactly 20 real minutes — the same 20 minutes the 20/20/20
/// rule has been quietly asking for since 1.0. The break is 20 seconds, which
/// is 400 ticks. The delay is 5 minutes, which is 6000 ticks, which is a
/// quarter of a day.
///
/// None of the numbers had to change. They were always these numbers.
public enum MinecraftTime {
    /// The server tick rate. Everything below is derived from it.
    public static let ticksPerSecond = 20
    /// One full day-night cycle.
    public static let ticksPerDay = 24_000

    /// Real seconds for a number of ticks.
    public static func seconds(ticks: Int) -> TimeInterval {
        TimeInterval(ticks) / TimeInterval(ticksPerSecond)
    }

    /// Ticks for a number of real seconds, rounded down like the game does.
    public static func ticks(seconds: TimeInterval) -> Int {
        Int((seconds * TimeInterval(ticksPerSecond)).rounded(.down))
    }

    /// Where a tick falls in the cycle. Tick 0 is sunrise.
    public enum Phase: String, Sendable, CaseIterable {
        case day, sunset, night, sunrise

        /// What the menu bar says you are living through.
        public var label: String {
            switch self {
            case .day: return "Day"
            case .sunset: return "Sunset"
            case .night: return "Night"
            case .sunrise: return "Sunrise"
            }
        }

        /// Light level drops below 8 and things start climbing out of caves.
        public var spawnsHostileMobs: Bool {
            self == .night
        }
    }

    /// The vanilla cycle boundaries, in ticks.
    public static func phase(atTick tick: Int) -> Phase {
        switch tick.mod(ticksPerDay) {
        case 0..<12_000: return .day
        case 12_000..<13_000: return .sunset
        case 13_000..<23_000: return .night
        default: return .sunrise
        }
    }

    /// Ticks elapsed in the current cycle, given how far into it we are.
    public static func tick(secondsIntoDay seconds: TimeInterval) -> Int {
        ticks(seconds: seconds).mod(ticksPerDay)
    }

    /// "5,440 ticks" — shown next to every countdown, because a countdown in
    /// minutes and seconds tells a player nothing useful.
    public static func formatted(ticks: Int) -> String {
        let count = NumberFormatter.localizedString(
            from: NSNumber(value: ticks), number: .decimal
        )
        return "\(count) ticks"
    }
}

private extension Int {
    /// Floored modulo, so a negative offset still lands inside the cycle.
    func mod(_ divisor: Int) -> Int {
        let remainder = self % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }
}
