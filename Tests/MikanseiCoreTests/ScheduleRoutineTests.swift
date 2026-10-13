import Foundation
import XCTest
@testable import MikanseiCore

final class ScheduleRoutineTests: XCTestCase {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.firstWeekday = 2
        return c
    }
    private func date(_ day: Int, _ hour: Int = 9, month: Int = 10, calendar c: Calendar? = nil) -> Date {
        (c ?? calendar()).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func schedule(_ start: Date, minutes: Int = 90) -> Entry {
        var e = Entry(title: "练琴", kind: .schedule, createdAt: start)
        e.plannedStart = start; e.plannedEnd = start.addingTimeInterval(Double(minutes) * 60)
        return e
    }
    func testScheduleDefaultsToStartAlarmAndDoesNotBecomeOverdue() throws {
        let start = date(12)
        var e = schedule(start)
        XCTAssertNil(e.dueDate)
        XCTAssertEqual(e.reminderDelivery, .alarm)
        XCTAssertEqual(e.reminderAnchor, .execution)
        XCTAssertEqual(e.reminderDate, start)
        e.dueDate = start.addingTimeInterval(-3600) // Switching type clears the old DDL.
        let saved = e.normalized(at: start)
        XCTAssertNil(saved.dueDate)
        XCTAssertEqual(saved.attentionDate, start)
        XCTAssertFalse(saved.isOverdue(at: date(15)))
        XCTAssertEqual(NotificationPlan.pending(entries: [saved], courses: [], now: start.addingTimeInterval(-60)).first?.delivery, .alarm)
        let restored = try EntryArchive.decode(EntryArchive(entries: [saved]).encoded()).entries[0]
        XCTAssertEqual(restored.plannedEnd, e.plannedEnd)
        XCTAssertEqual(restored.kind, .schedule)
    }
    func testDailyScheduleCompletionPreservesDurationAndResetsPersonalState() throws {
        var e = schedule(date(12)); e.repeatRule = .daily
        e.checklist = [ChecklistItem(title: "热身", isDone: true)]
        e.elapsedSeconds = 600; e.setCompleted(true, at: date(12, 11))
        let next = try XCTUnwrap(e.nextOccurrence(after: date(12, 11), calendar: calendar()))
        XCTAssertEqual(next.plannedStart, date(13)); XCTAssertEqual(next.plannedEnd, date(13).addingTimeInterval(5400))
        XCTAssertNil(next.dueDate); XCTAssertFalse(next.isCompleted); XCTAssertEqual(next.elapsedSeconds, 0)
        XCTAssertFalse(next.checklist[0].isDone); XCTAssertEqual(next.previousOccurrenceID, e.id)
        XCTAssertEqual(next.reminderDelivery, .alarm)
        XCTAssertEqual(next.repeatAnchorDate, date(12))
    }
    func testMonthlyMonthEndDoesNotDriftAfterCompletionAndBackup() throws {
        var e = schedule(date(31, month: 1)); e.repeatRule = .monthly
        let feb = try XCTUnwrap(e.nextOccurrence(after: date(31, 11, month: 1), calendar: calendar()))
        XCTAssertEqual(feb.plannedStart, date(28, month: 2))
        let saved = try EntryArchive.decode(EntryArchive(entries: [feb]).encoded()).entries[0]
        let march = try XCTUnwrap(saved.nextOccurrence(after: date(28, 11, month: 2), calendar: calendar()))
        XCTAssertEqual(march.plannedStart, date(31, month: 3))
        e.repeatIntervalMonths = 2
        XCTAssertEqual(e.nextOccurrence(after: date(31, 11, month: 1), calendar: calendar())?.plannedStart, date(31, month: 3))
    }
    func testWeeklyMultipleWeekdaysAndCustomIntervalUseSameDatesForCalendarAndReminders() {
        var e = schedule(date(12)); e.repeatRule = .weekly; e.repeatWeekdays = [1, 3, 5]
        let dates = e.occurrenceDates(in: date(12, 0)..<date(19, 0), calendar: calendar())
        XCTAssertEqual(dates, [date(12), date(14), date(16)])
        let reminders = NotificationPlan.pending(entries: [e], courses: [], now: date(12, 0), calendar: calendar())
        XCTAssertEqual(Array(reminders.prefix(3).map(\.date)), dates)
        XCTAssertEqual(CalendarDisplay.items(on: date(14), entries: [e], calendar: calendar()).first?.date, date(14))
        XCTAssertTrue(CalendarDisplay.items(on: date(15), entries: [e], calendar: calendar()).isEmpty)
        e.repeatRule = .custom; e.repeatIntervalDays = 10
        XCTAssertEqual(e.nextOccurrence(after: date(12, 11), calendar: calendar())?.plannedStart, date(22))
    }
    func testIrregularDatesAreFiniteDeduplicatedAndResetOnCompletion() throws {
        var e = schedule(date(12)); e.repeatRule = .dates
        e.repeatDates = [date(12, 0), date(20, 0), date(20, 0), date(3, 0, month: 11)]
        let dates = e.occurrenceDates(in: date(12, 0)..<date(1, 0, month: 12), calendar: calendar())
        XCTAssertEqual(dates, [date(12), date(20), date(3, month: 11)])
        XCTAssertEqual(e.nextOccurrence(after: date(21), calendar: calendar())?.plannedStart, date(3, month: 11))
        XCTAssertNil(e.nextOccurrence(after: date(4, month: 11), calendar: calendar()))
        XCTAssertTrue(CalendarDisplay.items(on: date(19), entries: [e], calendar: calendar()).isEmpty)
        let plan = NotificationPlan.pending(entries: [e], courses: [], now: date(19), calendar: calendar())
        XCTAssertEqual(plan.map(\.date), [date(20), date(3, month: 11)])
        let restored = try EntryArchive.decode(EntryArchive(entries: [e]).encoded()).entries[0]
        XCTAssertEqual(restored.repeatDates, e.repeatDates)
        e.repeatDates = []
        XCTAssertThrowsError(try EntryArchive.decode(EntryArchive(entries: [e]).encoded()))
    }
    func testRoutineIsTagForTaskAndScheduleButNeverNote() {
        var task = Entry(title: "清理书桌", dueDate: date(12)); task.repeatRule = .monthly
        XCTAssertTrue(task.isRoutine); XCTAssertEqual(task.kind, .task)
        var e = schedule(date(12)); e.repeatRule = .daily
        XCTAssertTrue(e.isRoutine); XCTAssertEqual(e.kind, .schedule)
        e.kind = .note
        XCTAssertFalse(e.normalized().isRoutine)
        XCTAssertNil(e.normalized().plannedStart)
    }
    func testFutureLeadReminderStillOccursWhenCurrentLeadHasPassed() {
        var e = schedule(date(12)); e.repeatRule = .daily; e.reminder = .oneDay
        let now = date(12, 8)
        let plan = NotificationPlan.pending(entries: [e], courses: [], now: now, calendar: calendar())
        XCTAssertEqual(plan.first?.date, date(12)) // Tomorrow's 09:00 event reminds today at 09:00.
        XCTAssertTrue(plan.allSatisfy { $0.date > now })
    }
    func testRoutineExecutionReminderIsIndependentOfLaterDeadline() {
        var e = Entry(title: "写报告", dueDate: date(14), reminder: .atTime)
        e.repeatRule = .daily; e.reminderAnchor = .execution
        e.plannedStart = date(12); e.plannedEnd = date(12, 11)
        let plan = NotificationPlan.pending(entries: [e], courses: [], now: date(12, 8), calendar: calendar())
        XCTAssertEqual(plan.first?.date, date(12))
        e.plannedStart = date(16); e.plannedEnd = date(16, 11)
        XCTAssertEqual(NotificationPlan.pending(entries: [e], courses: [], now: date(16, 8), calendar: calendar()).first?.date, date(16))
    }
    func testWallClockAndDurationAcrossDSTAndAllDayExclusiveEnd() throws {
        let c = calendar("America/Los_Angeles")
        var e = schedule(date(7, 9, month: 3, calendar: c)); e.repeatRule = .daily
        let next = try XCTUnwrap(e.nextOccurrence(after: date(7, 10, month: 3, calendar: c), calendar: c))
        XCTAssertEqual(next.plannedStart, date(8, 9, month: 3, calendar: c))
        XCTAssertEqual(next.plannedEnd!.timeIntervalSince(next.plannedStart!), 5400)
        XCTAssertEqual(next.plannedStart!.timeIntervalSince(e.plannedStart!), 23 * 3600)
        e.plannedAllDay = true; e.plannedStart = date(7, 0, month: 3, calendar: c); e.plannedEnd = date(8, 0, month: 3, calendar: c)
        let allDay = try XCTUnwrap(e.nextOccurrence(after: date(7, 10, month: 3, calendar: c), calendar: c))
        XCTAssertEqual(allDay.plannedStart, date(8, 0, month: 3, calendar: c))
        XCTAssertEqual(allDay.plannedEnd, date(9, 0, month: 3, calendar: c))
        XCTAssertEqual(allDay.plannedEnd!.timeIntervalSince(allDay.plannedStart!), 23 * 3600)
    }
    func testCrossMidnightRoutineAndEarlierExecutionThanDeadlineAppearOnCorrectDays() {
        var e = schedule(date(12, 23), minutes: 180); e.repeatRule = .daily
        let items = CalendarDisplay.items(on: date(14, 0), entries: [e], calendar: calendar())
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.date), [date(13, 23), date(14, 23)])
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
        var task = Entry(title: "报告", dueDate: date(14, 20)); task.repeatRule = .daily
        task.plannedStart = date(12); task.plannedEnd = date(12, 11)
        let execution = CalendarDisplay.items(on: date(13), entries: [task], calendar: calendar())
        XCTAssertEqual(execution.first?.date, date(13)); XCTAssertEqual(execution.first?.kind, .execution)
    }
    func testReopenedPreviousOccurrenceDoesNotDuplicateSuccessorProjectionOrReminders() throws {
        var e = schedule(date(12)); e.repeatRule = .daily
        let next = try XCTUnwrap(e.nextOccurrence(after: date(12, 11), calendar: calendar()))
        let items = CalendarDisplay.items(on: date(14), entries: [e, next], calendar: calendar())
        XCTAssertEqual(items.count, 1); XCTAssertEqual(items.first?.entry.id, next.id)
        let plan = NotificationPlan.pending(entries: [e, next], courses: [], now: date(13, 0), calendar: calendar())
        XCTAssertEqual(plan.filter { $0.date == date(14) }.count, 1)
    }
    func testLegacyRoutineFieldsDecodeWithoutNewKeys() throws {
        var e = Entry(title: "旧常态", dueDate: date(12)); e.repeatRule = .weekly
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: EntryArchive(entries: [e]).encoded()) as? [String: Any])
        var entries = raw["entries"] as! [[String: Any]]
        for key in ["repeatDates", "repeatWeekdays", "repeatIntervalMonths", "repeatAnchorDate"] { entries[0].removeValue(forKey: key) }
        raw["entries"] = entries
        let restored = try EntryArchive.decode(JSONSerialization.data(withJSONObject: raw)).entries[0]
        XCTAssertEqual(restored.nextOccurrence(after: date(12), calendar: calendar())?.dueDate, date(19))
        XCTAssertEqual(restored.repeatIntervalMonths, 1)
    }
    func testTimelineLongPressSnapsWithinNormalAndDSTDays() {
        for c in [calendar(), calendar("America/Los_Angeles")] {
            let day = date(8, 0, month: 3, calendar: c)
            XCTAssertEqual(CalendarTimelineLayout.start(on: day, minuteOffset: 9 * 60 + 29, calendar: c), day.addingTimeInterval(9 * 3600 + 15 * 60))
            XCTAssertEqual(CalendarTimelineLayout.start(on: day, minuteOffset: -50, calendar: c), day)
            let end = c.date(byAdding: .day, value: 1, to: day)!
            XCTAssertEqual(CalendarTimelineLayout.start(on: day, minuteOffset: 9999, calendar: c), end.addingTimeInterval(-900))
            XCTAssertNil(CalendarTimelineLayout.start(on: day, minuteOffset: .nan, calendar: c))
        }
    }
}
