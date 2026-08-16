import XCTest
@testable import Miqat

/// Pins the scheduling core with a fixed calendar and known weekdays.
/// 2024-01-01 was a Monday, so in UTC: Jan 5 = Friday, Jan 6 = Saturday.

final class ScheduleTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    private func seconds(_ h: Int, _ m: Int) -> Int { h * 3_600 + m * 60 }

    // MARK: Next-occurrence — one-shot

    func testOneShotFiresLaterTheSameDay() {
        let spec = AlarmSpec(timeSecondsOfDay: seconds(18, 0), repeatDays: [])
        let now = date(2024, 1, 6, hour: 12)   // Saturday noon
        let next = AlarmScheduler.nextOccurrence(after: now, spec: spec, calendar: calendar)
        XCTAssertEqual(next, date(2024, 1, 6, hour: 18))
    }

    func testOneShotRollsOverWhenTheMomentHasPassed() {
        let spec = AlarmSpec(timeSecondsOfDay: seconds(18, 0), repeatDays: [])
        let now = date(2024, 1, 6, hour: 19)   // Saturday 7pm; the moment is gone
        let next = AlarmScheduler.nextOccurrence(after: now, spec: spec, calendar: calendar)
        XCTAssertEqual(next, date(2024, 1, 7, hour: 18))   // Sunday
    }

    func testOneShotAtTheExactNowFiresTomorrow() {
        // "strictly after" — an alarm whose moment is *now* has not fired yet.
        let spec = AlarmSpec(timeSecondsOfDay: seconds(12, 0), repeatDays: [])
        let now = date(2024, 1, 6, hour: 12)
        let next = AlarmScheduler.nextOccurrence(after: now, spec: spec, calendar: calendar)
        XCTAssertEqual(next, date(2024, 1, 7, hour: 12))
    }

    // MARK: Next-occurrence — repeats

    func testRepeatFiresTodayWhenTheWeekdayMatchesAndIsAhead() {
        let spec = AlarmSpec(timeSecondsOfDay: seconds(18, 0), repeatDays: [.saturday])
        let now = date(2024, 1, 6, hour: 12)   // a Saturday
        let next = AlarmScheduler.nextOccurrence(after: now, spec: spec, calendar: calendar)
        XCTAssertEqual(next, date(2024, 1, 6, hour: 18))
    }

    func testRepeatSkipsToTheNextMatchingDay() {
        // Now is Saturday; Fridays come before that in the week, so the next
        // fire must be six days out: Friday 2024-01-12.
        let spec = AlarmSpec(timeSecondsOfDay: seconds(18, 0), repeatDays: [.friday])
        let now = date(2024, 1, 6, hour: 12)
        let next = AlarmScheduler.nextOccurrence(after: now, spec: spec, calendar: calendar)
        XCTAssertEqual(next, date(2024, 1, 12, hour: 18))
        XCTAssertEqual(calendar.component(.weekday, from: next!), RepeatDay.friday.calendarWeekday)
    }

    func testRepeatEveryDayRollsToTomorrowWhenThisMornsMomentPassed() {
        let spec = AlarmSpec(timeSecondsOfDay: seconds(6, 0), repeatDays: Array(RepeatDay.allCases))
        let now = date(2024, 1, 6, hour: 12)
        let next = AlarmScheduler.nextOccurrence(after: now, spec: spec, calendar: calendar)
        XCTAssertEqual(next, date(2024, 1, 7, hour: 6))
    }

    // MARK: Invalid input

    func testInvalidTimesReturnNil() {
        for bad in [-1, 86_400, 90_000] {
            let spec = AlarmSpec(timeSecondsOfDay: bad, repeatDays: [.saturday])
            XCTAssertNil(AlarmScheduler.nextOccurrence(after: date(2024, 1, 6), spec: spec, calendar: calendar))
            XCTAssertFalse(AlarmSpec.isValidTime(bad))
        }
    }

    // MARK: Due-now decisions (the foreground watcher's rule)

    private func alarm(seconds s: Int, days: [RepeatDay], enabled: Bool = true) -> Alarm {
        var a = Alarm(timeSecondsOfDay: s, repeatDays: days)
        a.enabled = enabled
        return a
    }

    func testUnpaidMorningAlarmIsDueAtNoon() {
        let list = [alarm(seconds: seconds(5, 0), days: [.saturday])]
        let now = date(2024, 1, 6, hour: 12)   // Saturday
        XCTAssertEqual(AlarmScheduler.dueAlarms(now: now, alarms: list, calendar: calendar).count, 1)
    }

    func testPaidAlarmIsNotDueAgainThatDay() {
        var a = alarm(seconds: seconds(5, 0), days: [.saturday])
        a.lastFiredAt = date(2024, 1, 6, hour: 5, minute: 1)   // paid this morning
        let now = date(2024, 1, 6, hour: 12)
        XCTAssertEqual(AlarmScheduler.dueAlarms(now: now, alarms: [a], calendar: calendar), [])
    }

    func testRepeatOnTheWrongWeekdayIsNotDue() {
        let list = [alarm(seconds: seconds(5, 0), days: [.sunday])]
        let now = date(2024, 1, 6, hour: 12)   // Saturday — Sunday's alarm rests
        XCTAssertEqual(AlarmScheduler.dueAlarms(now: now, alarms: list, calendar: calendar), [])
    }

    func testDisabledAndFutureAlarmsAreNotDue() {
        let disabled = alarm(seconds: seconds(5, 0), days: [.saturday], enabled: false)
        let laterToday = alarm(seconds: seconds(18, 0), days: [.saturday])
        let now = date(2024, 1, 6, hour: 12)
        XCTAssertEqual(AlarmScheduler.dueAlarms(now: now, alarms: [disabled, laterToday], calendar: calendar), [])
    }

    func testOneShotUnpaidIsDueUntilItPays() {
        // A one-shot armed for this morning that never fired is owed all day.
        let list = [alarm(seconds: seconds(5, 0), days: [])]
        let now = date(2024, 1, 6, hour: 23)
        XCTAssertEqual(AlarmScheduler.dueAlarms(now: now, alarms: list, calendar: calendar).count, 1)
    }
}
