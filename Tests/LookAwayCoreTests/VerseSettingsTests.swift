import Foundation
import Testing
@testable import LookAwayCore

/// Dates are read in a fixed UTC calendar so a day is always the same day.
struct VerseSettingsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private let a = Verse(text: "A", reference: "A 1:1")
    private let b = Verse(text: "B", reference: "B 1:1")
    private let c = Verse(text: "C", reference: "C 1:1")

    private func mine(_ verses: [Verse], next: Int = 0) -> VerseSettings {
        VerseSettings(isEnabled: true, source: .myVerses, myVerses: verses, nextIndex: next)
    }

    // MARK: Opt-in

    @Test func standardIsOffOnTheVerseOfTheDayWithNothingOfYourOwn() {
        #expect(VerseSettings.standard.isEnabled == false)
        #expect(VerseSettings.standard.source == .dailyVerse)
        #expect(VerseSettings.standard.myVerses.isEmpty)
    }

    @Test func showsNothingWhileSwitchedOff() {
        var settings = mine([a, b])
        settings.isEnabled = false
        #expect(settings.verse(on: date(2026, 9, 26), calendar: calendar) == nil)
        #expect(!settings.isRotating)
    }

    // MARK: Verse of the day

    @Test func verseOfTheDayIsTheSameAllDay() {
        let settings = VerseSettings(isEnabled: true)
        let morning = settings.verse(on: date(2026, 9, 26, hour: 0), calendar: calendar)
        let evening = settings.verse(on: date(2026, 9, 26, hour: 23), calendar: calendar)
        #expect(morning != nil)
        #expect(morning == evening)
    }

    @Test func verseOfTheDayChangesTheNextDay() {
        let settings = VerseSettings(isEnabled: true)
        #expect(settings.verse(on: date(2026, 9, 26), calendar: calendar)
                != settings.verse(on: date(2026, 9, 27), calendar: calendar))
    }

    @Test func dailyListStartsOnItsFirstDayAndCarriesOnPastTheEnd() {
        let count = DailyVerses.all.count
        let first = date(2026, 1, 1)
        #expect(DailyVerses.index(on: first, calendar: calendar) == 0)
        let lastDay = calendar.date(byAdding: .day, value: count - 1, to: first)!
        #expect(DailyVerses.index(on: lastDay, calendar: calendar) == count - 1)
        let wrapped = calendar.date(byAdding: .day, value: count, to: first)!
        #expect(DailyVerses.index(on: wrapped, calendar: calendar) == 0)
    }

    @Test func aClockSetBeforeTheFirstDayStillLandsOnAVerse() {
        let dayBefore = date(2025, 12, 31)
        #expect(DailyVerses.index(on: dayBefore, calendar: calendar) == DailyVerses.all.count - 1)
    }

    @Test func anEmptyListOfYourOwnFallsBackToTheVerseOfTheDay() {
        let settings = mine([])
        let today = date(2026, 9, 26)
        #expect(!settings.isRotating)
        #expect(settings.verse(on: today, calendar: calendar) == DailyVerses.verse(on: today, calendar: calendar))
    }

    // MARK: Your own verses

    @Test func showsTheNextOfYourVersesUntilItAdvances() {
        var settings = mine([a, b, c])
        let today = date(2026, 9, 26)
        #expect(settings.isRotating)
        #expect(settings.verse(on: today, calendar: calendar) == a)
        #expect(settings.verse(on: today, calendar: calendar) == a)
        settings.advance()
        #expect(settings.verse(on: today, calendar: calendar) == b)
    }

    @Test func advancingPastTheLastGoesBackToTheFirst() {
        var settings = mine([a, b], next: 1)
        settings.advance()
        #expect(settings.nextIndex == 0)
    }

    @Test func anOutOfRangeIndexIsPulledBackIntoTheList() {
        #expect(mine([a, b], next: 7).nextIndex == 1)
        #expect(mine([a, b], next: -3).nextIndex == 0)
        #expect(mine([], next: 4).nextIndex == 0)
    }

    // MARK: Editing keeps your place

    @Test func removingAnEarlierVerseKeepsTheSameVerseNext() {
        var settings = mine([a, b, c], next: 2)
        settings.remove(a.id)
        #expect(settings.myVerses == [b, c])
        #expect(settings.myVerses[settings.nextIndex] == c)
    }

    @Test func removingTheNextVerseMakesTheOneAfterItNext() {
        var settings = mine([a, b, c], next: 1)
        settings.remove(b.id)
        #expect(settings.myVerses[settings.nextIndex] == c)
    }

    @Test func removingTheLastVerseWhenItIsNextWrapsToTheFirst() {
        var settings = mine([a, b, c], next: 2)
        settings.remove(c.id)
        #expect(settings.nextIndex == 0)
    }

    @Test func removingEverythingLeavesAnEmptyListAtTheStart() {
        var settings = mine([a], next: 0)
        settings.remove(a.id)
        #expect(settings.myVerses.isEmpty)
        #expect(settings.nextIndex == 0)
    }

    @Test func movingVersesKeepsTheSameVerseNext() {
        var settings = mine([a, b, c], next: 1)
        settings.move(c.id, to: 0)
        #expect(settings.myVerses == [c, a, b])
        #expect(settings.myVerses[settings.nextIndex] == b)
        settings.move(c.id, to: 3)
        #expect(settings.myVerses == [a, b, c])
        #expect(settings.myVerses[settings.nextIndex] == b)
    }

    @Test func updatingAVerseReplacesItInPlace() {
        var settings = mine([a, b])
        var edited = b
        edited.text = "B, edited"
        settings.update(edited)
        #expect(settings.myVerses == [a, edited])
    }

    @Test func addingAppendsToTheEnd() {
        var settings = mine([a])
        settings.add(b)
        #expect(settings.myVerses == [a, b])
    }

    // MARK: Decoding

    @Test func anOlderSettingsFileKeepsWhatItHas() throws {
        let data = Data(#"{"isEnabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(VerseSettings.self, from: data)
        #expect(settings == VerseSettings(isEnabled: true))
    }
}

/// Serialized because every test shares one preferences suite, wiped in `init`.
/// Its own suite, not the schedule store's, since the two run side by side.
@Suite(.serialized)
@MainActor
struct VerseSettingsStoreTests {
    private static let suiteName = "com.connortorrell.LookAway.tests.verses"

    let defaults: UserDefaults
    let store: UserDefaultsVerseSettingsStore

    init() {
        defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        store = UserDefaultsVerseSettingsStore(defaults: defaults)
    }

    @Test func loadsTheDefaultWhenNothingIsStored() {
        #expect(store.load() == .standard)
    }

    @Test func roundTripsSavedSettings() {
        let settings = VerseSettings(
            isEnabled: true,
            source: .myVerses,
            myVerses: [Verse(text: "Be still", reference: "Psalm 46:10"), Verse(text: "No reference")],
            nextIndex: 1
        )
        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func fallsBackToTheDefaultWhenTheStoredDataIsUnreadable() {
        defaults.set(Data("not json".utf8), forKey: "verseSettings")
        #expect(store.load() == .standard)
    }
}

struct DailyVersesTests {
    @Test func coversAYearWithoutRepeating() {
        #expect(DailyVerses.all.count >= 365)
        #expect(Set(DailyVerses.all.map(\.reference)).count == DailyVerses.all.count)
    }

    @Test func everyVerseHasTextAndAReferenceAndFitsAtAGlance() {
        for verse in DailyVerses.all {
            #expect(!verse.text.isEmpty, "\(verse.reference) has no text")
            #expect(!verse.reference.isEmpty)
            #expect(verse.text.count <= VerseSettings.softLimit, "\(verse.reference) is too long")
        }
    }
}
