import Foundation
import XCTest
@testable import MikanseiCore

final class CalendarSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(id: String = "event", calendarID: String = "calendar", occurrence: String = "", title: String = "会议",
                       offset: TimeInterval = 3600, notes: String = "备注", location: String = "图书馆", allDay: Bool = false,
                       cancelled: Bool = false) -> CalendarEventRecord {
        CalendarEventRecord(identity: CalendarEventIdentity(calendarID: calendarID, calendarTitle: "学习", sourceTitle: "iCloud",
                                                           eventID: id, occurrence: occurrence),
                            title: title, start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + (allDay ? 86400 : 3600)),
                            isAllDay: allDay, notes: notes, location: location, url: "https://example.com/meeting", isCancelled: cancelled)
    }
    func testRepeatedLaunchDoesNotDuplicateOrChangeUnmodifiedEntry() throws {
        let record = event(location: " 图书馆 ")
        let first = CalendarImport.merge(events: [record, record], into: [], settings: CalendarSyncSettings(), now: now)
        XCTAssertEqual(first.added, 1)
        let entry = try XCTUnwrap(first.entries.first)
        XCTAssertNil(entry.dueDate)
        XCTAssertEqual(entry.plannedStart, record.start)
        XCTAssertEqual(entry.location, "图书馆")
        XCTAssertEqual(entry.body, "备注")
        XCTAssertEqual(entry.platform, record.url)
        XCTAssertNil(entry.reminder)
        let second = CalendarImport.merge(events: [record], into: first.entries, settings: CalendarSyncSettings(), now: now.addingTimeInterval(300))
        XCTAssertEqual(second.entries, first.entries)
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.updated, 0)
    }
    func testSourceChangesMergeWithoutOverwritingPersonalEditsOrCompletion() throws {
        let old = event()
        var entry = try XCTUnwrap(CalendarImport.merge(events: [old], into: [], settings: CalendarSyncSettings(), now: now).entries.first)
        entry.title = "我自己的标题"; entry.body = "我补充的说明"; entry.priority = .urgent
        entry.checklist = [ChecklistItem(title: "自己的步骤")]
        entry.reminder = .fiveMinutes; entry.elapsedSeconds = 180
        entry.setCompleted(true, at: now)
        let changed = event(title: "日历改了标题", offset: 7200, notes: "新的日历备注", location: "办公室")
        let next = try XCTUnwrap(CalendarImport.merge(events: [changed], into: [entry], settings: CalendarSyncSettings(), now: now.addingTimeInterval(10)).entries.first)
        XCTAssertEqual(next.id, entry.id)
        XCTAssertEqual(next.title, entry.title); XCTAssertEqual(next.body, entry.body)
        XCTAssertEqual(next.location, "办公室"); XCTAssertEqual(next.plannedStart, changed.start)
        XCTAssertNil(next.dueDate)
        XCTAssertEqual(next.checklist, entry.checklist)
        XCTAssertTrue(next.isCompleted); XCTAssertEqual(next.completedAt, entry.completedAt)
        XCTAssertEqual(next.priority, .urgent); XCTAssertEqual(next.elapsedSeconds, 180)
        XCTAssertEqual(next.reminder, .fiveMinutes)
        XCTAssertEqual(next.calendarEvent?.event, changed)
    }
    func testMovingOneOffOrDetachedOccurrenceUpdatesSameTaskWhileRecurringDatesStaySeparate() throws {
        let oneOff = event()
        let first = CalendarImport.merge(events: [oneOff], into: [], settings: CalendarSyncSettings(), now: now)
        let moved = CalendarImport.merge(events: [event(offset: 10000)], into: first.entries, settings: CalendarSyncSettings(), now: now)
        XCTAssertEqual(moved.entries.count, 1); XCTAssertEqual(moved.entries[0].id, first.entries[0].id)
        let a = event(id: "series", occurrence: "time:day1")
        let b = event(id: "series", occurrence: "time:day2", offset: 90000)
        let recurring = CalendarImport.merge(events: [a, b], into: [], settings: CalendarSyncSettings(), now: now)
        XCTAssertEqual(recurring.entries.count, 2)
        let detached = event(id: "series", occurrence: "time:day1", offset: 12000)
        let updated = CalendarImport.merge(events: [detached, b], into: recurring.entries, settings: CalendarSyncSettings(), now: now)
        XCTAssertEqual(updated.entries.count, 2)
        XCTAssertEqual(updated.entries[0].id, recurring.entries[0].id)
        XCTAssertEqual(updated.entries[0].plannedStart, detached.start)
    }
    func testLiveDuplicateCalendarsRemainSeparateButResyncedCalendarRebinds() {
        let a = event(calendarID: "cal-a")
        let b = event(calendarID: "cal-b")
        let copies = CalendarImport.merge(events: [a, b], into: [], settings: CalendarSyncSettings(), now: now)
        XCTAssertEqual(copies.entries.count, 2)
        let one = CalendarImport.merge(events: [a], into: [], settings: CalendarSyncSettings(), now: now)
        let rebound = CalendarImport.merge(events: [b], into: one.entries, settings: CalendarSyncSettings(), now: now, availableCalendarIDs: ["cal-b"])
        XCTAssertEqual(rebound.entries.count, 1)
        XCTAssertEqual(rebound.entries[0].id, one.entries[0].id)
        XCTAssertEqual(rebound.entries[0].calendarEvent?.event.identity.calendarID, "cal-b")
    }
    func testDeletingAnImportedOccurrenceSuppressesOnlyThatOccurrence() {
        let a = event(id: "series", occurrence: "first")
        let b = event(id: "series", occurrence: "second", offset: 86400)
        var settings = CalendarSyncSettings(); settings.suppressed = [a.identity]
        let result = CalendarImport.merge(events: [a, b], into: [], settings: settings, now: now)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].calendarEvent?.event.identity, b.identity)
        let newCalendarID = event(id: "series", calendarID: "new-id", occurrence: "first")
        XCTAssertTrue(CalendarImport.merge(events: [newCalendarID], into: [], settings: settings, now: now).entries.isEmpty)
    }
    func testMissingSourceFlagsOnlyQueriedWindowAndNeverDeletesTask() {
        let inWindow = event()
        let old = event(id: "old", offset: -3600) // Ends exactly at the query boundary; no longer in the window.
        let deselected = event(id: "other", calendarID: "other-calendar")
        let imported = CalendarImport.merge(events: [inWindow, old, deselected], into: [], settings: CalendarSyncSettings(), now: now)
        let result = CalendarImport.merge(events: [], into: imported.entries, settings: CalendarSyncSettings(), now: now,
                                         range: now..<now.addingTimeInterval(86400), availableCalendarIDs: ["calendar", "other-calendar"], queriedCalendarIDs: ["calendar"])
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertEqual(result.entries[0].calendarEvent?.missingFromSource, true)
        XCTAssertEqual(result.entries[1].calendarEvent?.missingFromSource, false)
        XCTAssertEqual(result.entries[2].calendarEvent?.missingFromSource, false)
        let restored = CalendarImport.merge(events: [inWindow], into: result.entries, settings: CalendarSyncSettings(), now: now)
        XCTAssertEqual(restored.entries[0].calendarEvent?.missingFromSource, false)
    }
    func testAllDayExclusiveEndAndTimingChangesRespectCustomDate() throws {
        let allDay = event(allDay: true)
        XCTAssertNil(allDay.draft(timing: .start, now: now).dueDate)
        XCTAssertEqual(allDay.draft(timing: .start, now: now).plannedEnd, allDay.end)
        XCTAssertEqual(allDay.draft(timing: .end, now: now).dueDate, allDay.end.addingTimeInterval(-1))
        let timed = event()
        let original = CalendarImport.merge(events: [timed], into: [], settings: CalendarSyncSettings(), now: now)
        var settings = CalendarSyncSettings(); settings.timing = .end
        let endMode = CalendarImport.merge(events: [timed], into: original.entries, settings: settings, now: now)
        XCTAssertEqual(endMode.entries[0].dueDate, timed.end)
        XCTAssertEqual(endMode.entries[0].kind, .task)
        XCTAssertEqual(endMode.entries[0].reminderAnchor, .deadline)
        var custom = original.entries[0]; custom.dueDate = now.addingTimeInterval(500)
        XCTAssertEqual(CalendarImport.merge(events: [timed], into: [custom], settings: settings, now: now).entries[0].dueDate, custom.dueDate)
    }
    func testBackupCarriesSelectionSuppressionAndLegacyArchivesKeepLoading() throws {
        let record = event()
        var settings = CalendarSyncSettings()
        settings.selectionInitialized = true; settings.enabled = false
        settings.selected = [CalendarSelection(id: "calendar", title: "学习", sourceTitle: "iCloud")]
        settings.suppressed = [record.identity]
        let entries = CalendarImport.merge(events: [record], into: [], settings: CalendarSyncSettings(), now: now).entries
        let archive = EntryArchive(entries: entries, calendarSync: settings)
        let restored = try EntryArchive.decode(archive.encoded())
        XCTAssertEqual(restored.calendarSync, settings)
        XCTAssertEqual(restored.entries, entries)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: archive.encoded()) as? [String: Any])
        raw.removeValue(forKey: "calendarSync")
        let legacy = try EntryArchive.decode(JSONSerialization.data(withJSONObject: raw))
        XCTAssertTrue(legacy.calendarSync.enabled)
        XCTAssertFalse(legacy.calendarSync.selectionInitialized)
    }
    func testCancelledEventsAreNotNewTasksAndConversionToNoteIsRespected() throws {
        let cancelled = event(cancelled: true)
        XCTAssertTrue(CalendarImport.merge(events: [cancelled], into: [], settings: CalendarSyncSettings(), now: now).entries.isEmpty)
        let imported = CalendarImport.merge(events: [event()], into: [], settings: CalendarSyncSettings(), now: now)
        let result = CalendarImport.merge(events: [cancelled], into: imported.entries, settings: CalendarSyncSettings(), now: now)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].calendarEvent?.event.isCancelled, true)
        var note = imported.entries[0]; note.kind = .note; note = note.normalized(at: now)
        XCTAssertEqual(CalendarImport.merge(events: [event(title: "新标题")], into: [note], settings: CalendarSyncSettings(), now: now).entries, [note])
    }
}
