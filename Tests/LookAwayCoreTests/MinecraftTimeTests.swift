import Testing
import Foundation
@testable import LookAwayCore

@Suite("Minecraft time")
struct MinecraftTimeTests {
    @Test("A day is twenty real minutes")
    func dayIsTwentyMinutes() {
        #expect(MinecraftTime.seconds(ticks: MinecraftTime.ticksPerDay) == 20 * 60)
    }

    @Test("The standard config is unchanged, just correctly named")
    func standardConfigMatchesTheOldNumbers() {
        #expect(Config.standard.workInterval == 20 * 60)
        #expect(Config.standard.breakSeconds == 20)
        #expect(Config.standard.snoozeInterval == 5 * 60)
    }

    @Test("A break is four hundred ticks")
    func breakIsFourHundredTicks() {
        #expect(Config.standard.breakTicks == 400)
        #expect(Config.standard.workTicks == 24_000)
    }

    @Test("Phases follow the vanilla cycle")
    func phasesFollowVanillaBoundaries() {
        #expect(MinecraftTime.phase(atTick: 0) == .day)
        #expect(MinecraftTime.phase(atTick: 11_999) == .day)
        #expect(MinecraftTime.phase(atTick: 12_000) == .sunset)
        #expect(MinecraftTime.phase(atTick: 13_000) == .night)
        #expect(MinecraftTime.phase(atTick: 22_999) == .night)
        #expect(MinecraftTime.phase(atTick: 23_000) == .sunrise)
    }

    @Test("The cycle wraps in both directions")
    func cycleWraps() {
        #expect(MinecraftTime.phase(atTick: MinecraftTime.ticksPerDay) == .day)
        #expect(MinecraftTime.phase(atTick: -1) == .sunrise)
    }

    @Test("Mobs only spawn at night")
    func mobsSpawnAtNight() {
        #expect(MinecraftTime.Phase.night.spawnsHostileMobs)
        #expect(MinecraftTime.Phase.allCases.filter(\.spawnsHostileMobs).count == 1)
    }
}
