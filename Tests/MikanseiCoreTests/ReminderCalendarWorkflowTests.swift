import Foundation
import XCTest
@testable import MikanseiCore

final class ReminderCalendarWorkflowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testDeadlineOnlyAndUndatedEntriesDoNotBecomeCalendarBlocks() throws {
        let deadline = Entry(title: "周五前交作业", dueDate: now.addingTimeInterval(86400))
        let undated = Entry(title: "给家里打电话")
        let restored = try EntryArchive.decode(EntryArchive(entries: [deadline, undated]).encoded())
        XCTAssertTrue(restored.entries.allSatisfy { $0.plannedStart == nil && $0.calendarEvent == nil })
        XCTAssertEqual(TaskBoard(entries: restored.entries, now: now).unscheduled.map(\.id), [undated.id])
    }
    func testCalendarSlotIsIndependentOfDeadlineAndAppearsInWidgetAndFocus() throws {
        var task = Entry(title: "去校医院", reminder: .fiveMinutes)
        task.plannedStart = now.addingTimeInterval(1800); task.plannedEnd = now.addingTimeInterval(3600)
        XCTAssertEqual(task.reminderDate, now.addingTimeInterval(1500))
        XCTAssertFalse(task.isOverdue(at: now.addingTimeInterval(4000)))
        let widget = WidgetSnapshot(entries: [task], now: now).board(at: now)
        XCTAssertEqual(widget.today.map(\.id), [task.id])
        XCTAssertEqual(widget.open[0].plannedEnd, task.plannedEnd)
        task.dueDate = now.addingTimeInterval(86400)
        XCTAssertEqual(task.plannedStart, now.addingTimeInterval(1800))
        XCTAssertEqual(task.reminderDate, now.addingTimeInterval(86100))
        XCTAssertEqual(TaskBoard(entries: [task], now: now).today.map(\.id), [task.id])
        task.reminderAnchor = .execution
        XCTAssertEqual(task.reminderDate, now.addingTimeInterval(1500))
        _ = try EntryArchive.decode(EntryArchive(entries: [task]).encoded())
        task.dueDate = nil; task.plannedStart = now.addingTimeInterval(-172800); task.plannedEnd = now.addingTimeInterval(-169200)
        XCTAssertEqual(TaskBoard(entries: [task], now: now).focus.map(\.id), [task.id])
    }
    func testDeliveryAndSoundsPropagateThroughTaskRoutineAndCoursePlans() throws {
        var task = Entry(title: "洗衣服", dueDate: now.addingTimeInterval(3600), reminder: .atTime)
        task.reminderDelivery = .alarm; task.reminderSound = .pulse; task.snoozeMinutes = 10; task.repeatRule = .daily
        var course = Course(); course.name = "数学"; course.firstDate = now; course.lastDate = now.addingTimeInterval(86400 * 20)
        course.reminderDelivery = .popup; course.reminderSound = .chime
        let plan = NotificationPlan.pending(entries: [task], courses: [course], now: now)
        let alarms = plan.filter { $0.entryID == task.id }
        XCTAssertFalse(alarms.isEmpty); XCTAssertTrue(alarms.allSatisfy { $0.delivery == .alarm && $0.sound == .pulse && $0.snoozeMinutes == 10 })
        XCTAssertTrue(plan.filter { $0.courseID == course.id }.allSatisfy { $0.delivery == .popup && $0.sound == .chime })
        let restored = try EntryArchive.decode(EntryArchive(entries: [task], courses: [course]).encoded())
        XCTAssertEqual(restored.entries[0].reminderDelivery, .alarm)
        XCTAssertEqual(restored.courses[0].reminderSound, .chime)
        let next = try XCTUnwrap(task.nextOccurrence(after: now))
        XCTAssertEqual(next.reminderDelivery, .alarm); XCTAssertEqual(next.reminderSound, .pulse)
        XCTAssertNil(next.plannedStart)
    }
    func testRingingOrSnoozedAlarmSurvivesRefreshButCompletionChangeAndDeletionCancelIt() throws {
        var task = Entry(title: "疫苗预约", dueDate: now.addingTimeInterval(60), reminder: .atTime)
        task.reminderDelivery = .alarm
        let event = try XCTUnwrap(NotificationPlan.pending(entries: [task], courses: [], now: now).first)
        let record = AlarmRecord(event: event)
        let after = now.addingTimeInterval(120)
        func retained(_ tasks: [Entry]) -> [AlarmRecord] {
            AlarmReconciliation.retained([record], liveIDs: [record.id], desired: [], entries: tasks, courses: [], now: after)
        }
        XCTAssertEqual(retained([task]), [record])
        task.checklist = [ChecklistItem(title: "带身份证", isDone: true)]
        XCTAssertEqual(retained([task]), [record])
        var changed = task; changed.dueDate = now.addingTimeInterval(500)
        XCTAssertTrue(retained([changed]).isEmpty)
        changed = task; changed.reminderDelivery = .popup
        XCTAssertTrue(retained([changed]).isEmpty)
        task.setCompleted(true, at: after)
        XCTAssertTrue(retained([task]).isEmpty); XCTAssertTrue(retained([]).isEmpty)
    }
    func testLegacyCalendarMigrationPreservesCustomDeadlineAndOldReminderDefaults() throws {
        let event = CalendarEventRecord(identity: CalendarEventIdentity(calendarID: "cal", calendarTitle: "生活", sourceTitle: "iCloud", eventID: "event"),
            title: "预约", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200))
        var imported = event.draft(timing: .start, now: now)
        imported.calendarEvent = CalendarEventLink(event: event, timing: .start)
        var custom = imported; custom.id = UUID(); custom.dueDate = now.addingTimeInterval(86400)
        var course = Course(); course.name = "数学"
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: EntryArchive(entries: [imported, custom], courses: [course]).encoded()) as? [String: Any])
        var entries = try XCTUnwrap(raw["entries"] as? [[String: Any]])
        entries[0]["dueDate"] = ISO8601DateFormatter().string(from: event.start)
        for index in entries.indices {
            for key in ["plannedStart", "plannedEnd", "plannedAllDay", "reminderDelivery", "reminderSound", "snoozeMinutes"] { entries[index].removeValue(forKey: key) }
        }
        raw["entries"] = entries
        var courses = try XCTUnwrap(raw["courses"] as? [[String: Any]])
        for key in ["reminderDelivery", "reminderSound", "snoozeMinutes"] { courses[0].removeValue(forKey: key) }
        raw["courses"] = courses
        let restored = try EntryArchive.decode(JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(restored.entries[0].dueDate); XCTAssertEqual(restored.entries[0].plannedStart, event.start)
        XCTAssertEqual(restored.entries[1].dueDate, custom.dueDate)
        XCTAssertEqual(restored.entries[0].reminderDelivery, .popup); XCTAssertEqual(restored.courses[0].reminderSound, .system)
    }
    func testCalendarMoveKeepsLocallyEnteredDeadlineChecklistAndReminderStyle() throws {
        let identity = CalendarEventIdentity(calendarID: "cal", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "event")
        let original = CalendarEventRecord(identity: identity, title: "完成报告", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200))
        var task = try XCTUnwrap(CalendarImport.merge(events: [original], into: [], settings: CalendarSyncSettings(), now: now).entries.first)
        task.dueDate = now.addingTimeInterval(86400); task.reminder = .atTime; task.reminderDelivery = .alarm
        task.checklist = [ChecklistItem(title: "写提纲", isDone: true)]
        let moved = CalendarEventRecord(identity: identity, title: "完成报告", start: now.addingTimeInterval(10000), end: now.addingTimeInterval(14000))
        let next = try XCTUnwrap(CalendarImport.merge(events: [moved], into: [task], settings: CalendarSyncSettings(), now: now).entries.first)
        XCTAssertEqual(next.id, task.id); XCTAssertEqual(next.plannedStart, moved.start)
        XCTAssertEqual(next.dueDate, task.dueDate); XCTAssertEqual(next.checklist, task.checklist); XCTAssertEqual(next.reminderDelivery, .alarm)
    }
    func testFreshlyWrittenCalendarEventDoesNotDuplicateWhenExternalIDBecomesAvailable() throws {
        let initial = CalendarEventIdentity(calendarID: "cal", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "local", localEventID: "local")
        let synced = CalendarEventIdentity(calendarID: "cal", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "server-id", localEventID: "local")
        func record(_ identity: CalendarEventIdentity) -> CalendarEventRecord {
            CalendarEventRecord(identity: identity, title: "写报告", start: now, end: now.addingTimeInterval(3600))
        }
        let first = CalendarImport.merge(events: [record(initial)], into: [], settings: CalendarSyncSettings(), now: now)
        let next = CalendarImport.merge(events: [record(synced)], into: first.entries, settings: CalendarSyncSettings(), now: now)
        XCTAssertEqual(next.entries.count, 1); XCTAssertEqual(next.entries[0].id, first.entries[0].id)
        XCTAssertEqual(next.entries[0].calendarEvent?.event.identity.eventID, "server-id")
    }
}
