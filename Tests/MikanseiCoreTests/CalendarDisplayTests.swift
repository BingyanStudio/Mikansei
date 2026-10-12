import XCTest
@testable import MikanseiCore

final class CalendarDisplayTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        value.firstWeekday = 2
        return value
    }
    private func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int, _ hour: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    func testMonthGridIncludesAdjacentMonthsAndLeapDayWithMondayFirst() {
        let c = calendar()
        let days = CalendarDisplay.monthDays(containing: date(2024, 2, 15, calendar: c), calendar: c)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(c.component(.weekday, from: days[0]), 2)
        XCTAssertTrue(days.contains(date(2024, 2, 29, calendar: c)))
        XCTAssertEqual(days[0], date(2024, 1, 29, calendar: c))
        XCTAssertEqual(days.last, date(2024, 3, 10, calendar: c))
    }
    func testCrossMidnightAndAllDayExclusiveEndAndDeadlineRemainDistinct() {
        let c = calendar()
        let first = date(2026, 10, 12, calendar: c)
        let second = date(2026, 10, 13, calendar: c)
        var overnight = Entry(title: "夜间活动", dueDate: date(2026, 10, 14, 18, calendar: c))
        overnight.plannedStart = date(2026, 10, 12, 23, calendar: c)
        overnight.plannedEnd = date(2026, 10, 13, 2, calendar: c)
        var allDay = Entry(title: "全天事项")
        allDay.plannedStart = first; allDay.plannedEnd = second; allDay.plannedAllDay = true
        XCTAssertEqual(CalendarDisplay.items(on: first, entries: [overnight, allDay], calendar: c).count, 2)
        let next = CalendarDisplay.items(on: second, entries: [overnight, allDay], calendar: c)
        XCTAssertEqual(next.map(\.entry.id), [overnight.id])
        let blocks = CalendarTimelineLayout.blocks(on: second, items: next, calendar: c)
        XCTAssertEqual(blocks[0].startMinute, 0); XCTAssertEqual(blocks[0].endMinute, 120)
        let deadline = CalendarDisplay.items(on: date(2026, 10, 14, calendar: c), entries: [overnight], calendar: c)
        XCTAssertEqual(deadline.first?.kind, .deadline)
        XCTAssertTrue(CalendarTimelineLayout.blocks(on: first, items: CalendarDisplay.items(on: first, entries: [allDay], calendar: c), calendar: c).isEmpty)
    }
    func testDeadlineAndUnscheduledTasksNeverReserveExecutionTimeAndCompletedFilterWorks() {
        let c = calendar(); let day = date(2026, 10, 12, calendar: c)
        var deadline = Entry(title: "最晚今天交", dueDate: date(2026, 10, 12, 22, calendar: c))
        let unscheduled = Entry(title: "买灯")
        let items = CalendarDisplay.items(on: day, entries: [deadline, unscheduled], calendar: c)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(CalendarTimelineLayout.blocks(on: day, items: items, calendar: c).isEmpty)
        deadline.setCompleted(true, at: day)
        XCTAssertEqual(CalendarDisplay.items(on: day, entries: [deadline], calendar: c).count, 1)
        XCTAssertTrue(CalendarDisplay.items(on: day, entries: [deadline], showCompleted: false, calendar: c).isEmpty)
    }
    func testOverlappingAppointmentsShareColumnsButAdjacentOnesReuseFullWidth() {
        let c = calendar(); let day = date(2026, 10, 12, calendar: c)
        func task(_ title: String, _ start: Int, _ end: Int) -> Entry {
            var e = Entry(title: title); e.plannedStart = date(2026, 10, 12, start, calendar: c); e.plannedEnd = date(2026, 10, 12, end, calendar: c); return e
        }
        let entries = [task("A", 9, 12), task("B", 10, 11), task("C", 11, 13), task("D", 13, 14)]
        let blocks = CalendarTimelineLayout.blocks(on: day, items: CalendarDisplay.items(on: day, entries: entries, calendar: c), calendar: c)
        XCTAssertEqual(blocks.map(\.column), [0, 1, 1, 0])
        XCTAssertEqual(blocks.map(\.columnCount), [2, 2, 2, 1])
    }
    func testDayTimelineHonorsActualDurationAcrossDaylightSavingTransitions() {
        let c = calendar("America/Los_Angeles")
        for (month, dayNumber, expectedHours) in [(3, 8, 23), (11, 1, 25)] {
            let day = date(2026, month, dayNumber, calendar: c)
            let end = c.date(byAdding: .day, value: 1, to: day)!
            var e = Entry(title: "跨全天时段"); e.plannedStart = day; e.plannedEnd = end
            let blocks = CalendarTimelineLayout.blocks(on: day, items: CalendarDisplay.items(on: day, entries: [e], calendar: c), calendar: c)
            XCTAssertEqual(blocks[0].endMinute, Double(expectedHours * 60))
        }
    }
    func testShortBackToBackEventsKeepReadableTapTargetsWithoutCoveringEachOther() {
        let c = calendar(); let day = date(2026, 10, 12, calendar: c)
        let start = date(2026, 10, 12, 9, calendar: c)
        var first = Entry(title: "五分钟通话"); first.plannedStart = start; first.plannedEnd = start.addingTimeInterval(300)
        var second = Entry(title: "接着签到"); second.plannedStart = start.addingTimeInterval(300); second.plannedEnd = start.addingTimeInterval(600)
        let blocks = CalendarTimelineLayout.blocks(on: day, items: CalendarDisplay.items(on: day, entries: [first, second], calendar: c), calendar: c)
        XCTAssertEqual(blocks.map(\.column), [0, 1])
        XCTAssertEqual(blocks.map(\.columnCount), [2, 2])
        XCTAssertEqual(blocks[0].endMinute, 545) // The readable box does not change the event's time.
    }
}
