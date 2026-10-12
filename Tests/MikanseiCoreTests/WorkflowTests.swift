import Foundation
import XCTest
@testable import MikanseiCore

final class WorkflowTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    private func date(_ day: Int, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testRoutineCompletionSkipsMissedCyclesAndResetsSteps() {
        var entry = Entry(title: "洗衣服", checklist: [ChecklistItem(title: "晾晒", isDone: true)], dueDate: date(1), reminder: .atTime)
        entry.repeatRule = .everyThreeDays
        entry.setCompleted(true, at: date(12, hour: 10))
        let next = entry.nextOccurrence(after: date(12, hour: 10), calendar: calendar)!
        XCTAssertEqual(next.dueDate, date(13))
        XCTAssertEqual(next.previousOccurrenceID, entry.id)
        XCTAssertFalse(next.isCompleted)
        XCTAssertFalse(next.checklist[0].isDone)
        XCTAssertNotEqual(next.checklist[0].id, entry.checklist[0].id)
    }

    func testUnfinishedRoutineStillPlansFutureCycleReminders() {
        var entry = Entry(title: "给家里打电话", dueDate: date(1, hour: 20), reminder: .atTime)
        entry.repeatRule = .weekly
        let events = NotificationPlan.pending(entries: [entry], courses: [], now: date(12), calendar: calendar)
        XCTAssertEqual(events.first?.date, date(15, hour: 20))
        XCTAssertTrue(events.allSatisfy { $0.entryID == entry.id && $0.date > date(12) })
        entry.setCompleted(true)
        XCTAssertTrue(NotificationPlan.pending(entries: [entry], courses: [], now: date(12), calendar: calendar).isEmpty)
    }

    func testCourseRegistrationOnlyOccursOnMatchingDaysWithinTerm() {
        var course = Course()
        course.name = "数学"
        course.weekday = 1
        course.firstDate = date(12, hour: 0)
        course.lastDate = date(19, hour: 0)
        course.platform = "学习通"
        let events = NotificationPlan.pending(entries: [], courses: [course], now: date(12), calendar: calendar)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.date, date(12, hour: 9).addingTimeInterval(40 * 60))
        XCTAssertEqual(events.first?.courseID, course.id)
        XCTAssertNil(events.first?.entryID)
        XCTAssertEqual(course.homeworkDraft().platform, "学习通")
        XCTAssertEqual(course.homeworkDraft().category, "数学")
        course.reminderEnabled = false
        XCTAssertTrue(NotificationPlan.pending(entries: [], courses: [course], now: date(12), calendar: calendar).isEmpty)
    }

    func testNotificationLimitAppliesAcrossCourseAndTaskReminders() {
        var course = Course()
        course.name = "数学"
        course.weekday = 1
        course.firstDate = date(12, hour: 0)
        course.lastDate = date(19, hour: 0)
        let task = Entry(title: "交作业", dueDate: date(12, hour: 9), reminder: .atTime)
        let events = NotificationPlan.pending(entries: [task], courses: [course], now: date(12), limit: 1, calendar: calendar)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].entryID, task.id)
    }

    func testCSVQuotedCommasAndInvalidRowsAreHandledBeforeImport() throws {
        let text = "\(CourseCSV.header)\n\"课程, A\",1,08:00,09:40,教学楼,学习通,2026-10-12,2027-01-01\n"
        let courses = try CourseCSV.parse(text, calendar: calendar)
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].name, "课程, A")
        XCTAssertThrowsError(try CourseCSV.parse(text.replacingOccurrences(of: "09:40", with: "07:40"), calendar: calendar))
        XCTAssertThrowsError(try CourseCSV.parse(text.replacingOccurrences(of: "08:00", with: "25:00"), calendar: calendar))
        XCTAssertThrowsError(try CourseCSV.parse("\(CourseCSV.header)\n\"unfinished", calendar: calendar))
    }

    func testICSBiweeklyExpansionExcludesCancelledDateAndUnfoldsTitle() throws {
        let text = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:math
        SUMMARY:高等
         数学
        DTSTART;TZID=Asia/Shanghai:20261012T080000
        DTEND;TZID=Asia/Shanghai:20261012T094000
        RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=3;BYDAY=MO
        EXDATE;TZID=Asia/Shanghai:20261026T080000
        LOCATION:教学楼\\,A
        END:VEVENT
        END:VCALENDAR
        """
        let courses = try CourseICS.parse(text, calendar: calendar)
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(courses[0].name, "高等数学")
        XCTAssertEqual(courses[0].location, "教学楼,A")
        XCTAssertEqual(courses[0].firstDate, date(12, hour: 0))
        XCTAssertEqual(courses[1].firstDate, calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!)
        XCTAssertEqual(courses[1].endMinutes, 580)
        XCTAssertEqual(courses[0].firstDate, courses[0].lastDate)
    }

    func testICSUTCConvertsToShanghaiAndRejectsUnboundedOrUnsupportedRules() throws {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:物理
        DTSTART:20261012T000000Z
        DURATION:PT1H40M
        RRULE:FREQ=WEEKLY;COUNT=2
        END:VEVENT
        END:VCALENDAR
        """
        let courses = try CourseICS.parse(text, calendar: calendar)
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(courses[0].startMinutes, 480)
        XCTAssertEqual(courses[0].endMinutes, 580)
        XCTAssertThrowsError(try CourseICS.parse(text.replacingOccurrences(of: ";COUNT=2", with: ""), calendar: calendar))
        XCTAssertThrowsError(try CourseICS.parse(text.replacingOccurrences(of: "WEEKLY", with: "MONTHLY"), calendar: calendar))
        XCTAssertThrowsError(try CourseICS.parse(text.replacingOccurrences(of: "SUMMARY:物理", with: "SUMMARY:物理\nRECURRENCE-ID:20261012T000000Z"), calendar: calendar))
    }

    func testMessageSuggestionsPreserveSourceAndMarkRelativeDateAssumptions() {
        let text = "【英语】明天 18:00 提交阅读作业到学习通，预计 30 分钟"
        let parsed = MessageParser.parse(text, now: date(12), calendar: calendar)
        XCTAssertEqual(parsed.entry.kind, .homework)
        XCTAssertEqual(parsed.entry.category, "英语")
        XCTAssertEqual(parsed.entry.platform, "学习通")
        XCTAssertEqual(parsed.entry.estimatedMinutes, 30)
        XCTAssertEqual(parsed.entry.dueDate, date(13, hour: 18))
        XCTAssertEqual(parsed.entry.source, text)
        XCTAssertFalse(parsed.assumptions.isEmpty)
        XCTAssertNil(MessageParser.parse("周五记得打疫苗", now: date(12), calendar: calendar).entry.dueDate)
        XCTAssertNil(MessageParser.parse("2026-02-30 18:00 提交", now: date(12), calendar: calendar).entry.dueDate)
    }

    func testOldArchivesStillDecodeAndCourseBackupsRoundTrip() throws {
        let entry = Entry(title: "旧事项", createdAt: date(12), updatedAt: date(12))
        let data = try EntryArchive(entries: [entry]).encoded()
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "courses")
        var entries = json["entries"] as! [[String: Any]]
        for key in ["platform", "location", "estimatedMinutes", "source", "repeatRule", "repeatIntervalDays", "reminderPattern", "previousOccurrenceID", "startedAt"] { entries[0].removeValue(forKey: key) }
        json["entries"] = entries
        let decoded = try EntryArchive.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.entries[0].repeatRule, .never)
        XCTAssertTrue(decoded.courses.isEmpty)
        var course = Course()
        course.name = "测试课程"
        course.firstDate = date(12)
        course.lastDate = date(19)
        let courseArchive = try EntryArchive.decode(EntryArchive(entries: [entry], courses: [course]).encoded())
        XCTAssertEqual(courseArchive.courses, [course])
    }

    func testCustomRoutineRespectsIntervalAndRejectsMissingSchedule() throws {
        var entry = Entry(title: "换床单", dueDate: date(12), reminder: .atTime)
        entry.repeatRule = .custom
        entry.repeatIntervalDays = 10
        XCTAssertEqual(entry.nextOccurrence(after: date(12), calendar: calendar)?.dueDate, date(22))
        let events = NotificationPlan.pending(entries: [entry], courses: [], now: date(12, hour: 7), calendar: calendar)
        XCTAssertEqual(events.count, 3)
        entry.dueDate = nil
        XCTAssertThrowsError(try EntryArchive.decode(EntryArchive(entries: [entry]).encoded()))
        XCTAssertEqual(entry.normalized().repeatRule, .never)
    }

    func testMultipleMessageDatesRequireManualDeadlineChoice() {
        let result = MessageParser.parse("明天讨论，后天 18:00 提交作业", now: date(12), calendar: calendar)
        XCTAssertNil(result.entry.dueDate)
        XCTAssertNil(result.entry.reminder)
        XCTAssertTrue(result.assumptions.contains { $0.contains("多个日期") })
    }
}
