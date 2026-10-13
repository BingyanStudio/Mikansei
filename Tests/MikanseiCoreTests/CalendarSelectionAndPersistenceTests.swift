import Foundation
import XCTest
@testable import MikanseiCore

final class CalendarSelectionAndPersistenceTests: XCTestCase {
    private let study = CalendarSelection(id: "study", title: "学习", sourceTitle: "iCloud")
    private let holiday = CalendarSelection(id: "holiday", title: "中国大陆节假日", sourceTitle: "订阅")
    private func record(_ calendar: CalendarSelection) -> CalendarEventRecord {
        CalendarEventRecord(identity: CalendarEventIdentity(calendarID: calendar.id, calendarTitle: calendar.title, sourceTitle: calendar.sourceTitle, eventID: "event"),
                            title: "日历事件", start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_003_600))
    }
    func testFirstAccessIsOptInAndExplicitHolidayChoiceSurvivesLaterRefresh() {
        var settings = CalendarSyncSettings().refreshed(available: [study, holiday])
        XCTAssertTrue(settings.selectionInitialized); XCTAssertTrue(settings.selected.isEmpty)
        settings.selected = [holiday]
        XCTAssertEqual(settings.refreshed(available: [study, holiday]).selected, [holiday])
        settings.selected = []
        XCTAssertTrue(settings.refreshed(available: [study, holiday]).selected.isEmpty)
    }
    func testLegacyDefaultSourcesMigrateOnceAndAccountIDsRebind() throws {
        let raw = """
        {"enabled":true,"timing":"start","selectionInitialized":true,"selected":[{"id":"old-study","title":"学习","sourceTitle":"iCloud"},{"id":"holiday","title":"中国大陆节假日","sourceTitle":"订阅"}],"suppressed":[]}
        """
        let old = try JSONDecoder().decode(CalendarSyncSettings.self, from: Data(raw.utf8))
        XCTAssertEqual(old.selectionPolicyVersion, 0)
        var updated = old.refreshed(available: [study, holiday])
        XCTAssertEqual(updated.selected, [study]); XCTAssertEqual(updated.selectionPolicyVersion, 1)
        updated.selected.append(holiday)
        XCTAssertEqual(updated.refreshed(available: [study, holiday]).selected.count, 2)
        let archived = try EntryArchive.decode(EntryArchive(entries: [], calendarSync: updated).encoded())
        XCTAssertEqual(archived.calendarSync, updated)
    }
    func testAmbiguousAccountRebindDoesNotGuessAndEmptySelectionStaysEmpty() {
        var settings = CalendarSyncSettings(); settings.selectionInitialized = true; settings.selected = [study]
        let a = CalendarSelection(id: "a", title: study.title, sourceTitle: study.sourceTitle)
        let b = CalendarSelection(id: "b", title: study.title, sourceTitle: study.sourceTitle)
        XCTAssertEqual(settings.refreshed(available: [a, b]).selected, [study])
        XCTAssertFalse(CalendarSyncSettings().refreshed(available: []).selectionInitialized)
    }
    func testOnlyQueriedSourcesImportAsSchedulesWithoutUnsolicitedAlarms() {
        let result = CalendarImport.merge(events: [record(study), record(holiday)], into: [], settings: CalendarSyncSettings(), queriedCalendarIDs: [study.id])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].kind, .schedule)
        XCTAssertEqual(result.entries[0].reminderDelivery, .alarm)
        XCTAssertNil(result.entries[0].reminder)
        XCTAssertNil(result.entries[0].dueDate)
        XCTAssertTrue(CalendarImport.merge(events: [record(study)], into: [], settings: CalendarSyncSettings(), queriedCalendarIDs: []).entries.isEmpty)
    }
    func testCleanupPreservesPersonalChangesHistoryAndExplicitCalendarPlans() throws {
        let e = try XCTUnwrap(CalendarImport.merge(events: [record(holiday)], into: [], settings: CalendarSyncSettings()).entries.first)
        XCTAssertTrue(CalendarImport.canClean(e, selectedIDs: []))
        XCTAssertFalse(CalendarImport.canClean(e, selectedIDs: [holiday.id]))
        var edits: [Entry] = []
        var copy = e; copy.setCompleted(true); edits.append(copy)
        copy = e; copy.title = "自己的标题"; edits.append(copy)
        copy = e; copy.checklist = [ChecklistItem(title: "自己的步骤")]; edits.append(copy)
        copy = e; copy.elapsedSeconds = 5; edits.append(copy)
        copy = e; copy.reminderSound = .chime; edits.append(copy)
        copy = e; copy.calendarEvent?.wasAutomaticallyImported = false; edits.append(copy)
        XCTAssertTrue(edits.allSatisfy { !CalendarImport.canClean($0, selectedIDs: []) })
        copy = e; copy.calendarEvent?.wasAutomaticallyImported = nil
        XCTAssertTrue(CalendarImport.canClean(copy, selectedIDs: [])) // Legacy holiday imports can be cleaned.
        copy.calendarEvent = CalendarEventLink(event: record(study), timing: .start, wasAutomaticallyImported: nil)
        XCTAssertFalse(CalendarImport.canClean(copy, selectedIDs: [])) // Unknown legacy personal plans stay safe.
    }
    func testBackgroundWritesKeepRapidCompletionOrderAndProtectArchiveOnFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = EntryRepository(fileURL: root.appendingPathComponent("entries.json"))
        let writer = EntryArchiveWriter(repository: repository)
        let completed = expectation(description: "all snapshots persisted")
        completed.expectedFulfillmentCount = 40
        var entries = (0..<40).map { Entry(title: "事项 \($0)") }
        for index in entries.indices {
            entries[index].setCompleted(true)
            writer.save(EntryArchive(entries: entries)) { result in
                if case .failure(let error) = result { XCTFail("\(error)") }
                completed.fulfill()
            }
        }
        wait(for: [completed], timeout: 10)
        let restored = try repository.load()
        XCTAssertEqual(restored.count, 40); XCTAssertTrue(restored.allSatisfy(\.isCompleted))
        let rejected = expectation(description: "invalid write rejected")
        writer.save(EntryArchive(entries: [Entry(title: "")])) { result in
            if case .success = result { XCTFail("Invalid snapshot must not replace valid data") }
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 5)
        XCTAssertEqual(try repository.load(), restored)
        let recovered = expectation(description: "retry succeeds")
        writer.save(EntryArchive(entries: restored + [Entry(title: "重试成功")])) { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            recovered.fulfill()
        }
        wait(for: [recovered], timeout: 5)
        XCTAssertEqual(try repository.load().last?.title, "重试成功")
    }
}
