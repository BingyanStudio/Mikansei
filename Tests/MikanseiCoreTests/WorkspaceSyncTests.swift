import Foundation
import XCTest
@testable import MikanseiCore

final class WorkspaceSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func entry(_ title: String) -> Entry { Entry(title: title, createdAt: now, updatedAt: now) }
    func testOfflineIndependentAddsConvergeInBothDirections() {
        var a = WorkspaceReplica(), b = WorkspaceReplica()
        a.capture(entries: [entry("手机")], courses: []); b.capture(entries: [entry("电脑")], courses: [])
        let left = a.document, right = b.document
        a.receive(right); b.receive(left)
        XCTAssertEqual(a.document, b.document); XCTAssertEqual(a.entries.count, 2)
    }
    func testConcurrentSameItemEditsHaveDeterministicWinner() {
        let original = entry("原事项")
        var a = WorkspaceReplica(), b = WorkspaceReplica()
        a.capture(entries: [original], courses: []); b.receive(a.document)
        var left = original; left.title = "手机编辑"
        var right = original; right.title = "电脑编辑"
        a.capture(entries: [left], courses: []); b.capture(entries: [right], courses: [])
        let ad = a.document, bd = b.document; a.receive(bd); b.receive(ad)
        XCTAssertEqual(a.entries, b.entries)
        XCTAssertEqual(a.entries.first?.title, a.device.uuidString > b.device.uuidString ? left.title : right.title)
    }
    func testCompletionAndChecklistSurviveAnOfflineUnchangedCopy() {
        var item = entry("作业"); item.checklist = [ChecklistItem(title: "上传")]
        var phone = WorkspaceReplica(), mac = WorkspaceReplica()
        phone.capture(entries: [item], courses: []); mac.receive(phone.document)
        item.setCompleted(true, at: now); phone.capture(entries: [item], courses: [])
        phone.receive(mac.document); mac.receive(phone.document)
        XCTAssertEqual(mac.entries.first?.isCompleted, true)
        XCTAssertEqual(mac.entries.first?.checklist.first?.isDone, true)
    }
    func testDeletedItemsAndCoursesCannotResurrectAfterRestart() throws {
        let item = entry("删除我"); var course = Course(); course.name = "课程"
        var a = WorkspaceReplica(), b = WorkspaceReplica()
        a.capture(entries: [item], courses: [course]); b.receive(a.document)
        a.capture(entries: [], courses: [])
        let saved = try EntryArchive.decode(EntryArchive(entries: [], replica: a).encoded())
        a = try XCTUnwrap(saved.replica); a.receive(b.document); b.receive(a.document)
        XCTAssertTrue(a.entries.isEmpty); XCTAssertTrue(b.courses.isEmpty)
        XCTAssertEqual(a.document.entries.count, 1); XCTAssertNil(a.document.entries[0].value)
    }
    func testCapturingUnchangedStateDoesNotAdvanceOrRewriteRevisions() {
        let item = entry("保持")
        var replica = WorkspaceReplica(); replica.capture(entries: [item], courses: [])
        let original = replica; replica.capture(entries: [item], courses: [])
        XCTAssertEqual(original, replica)
    }
    func testReceivingLaterClockMakesNextLocalEditNewer() {
        var a = WorkspaceReplica(), b = WorkspaceReplica(); var item = entry("初始")
        for number in 0..<15 { item.title = "\(number)"; a.capture(entries: [item], courses: []) }
        b.receive(a.document); item.title = "下一次修改"; b.capture(entries: [item], courses: []); a.receive(b.document)
        XCTAssertEqual(a.entries.first?.title, item.title); XCTAssertEqual(b.counter, 16)
    }
    func testWireValidationRejectsDuplicatesFutureFormatAndInvalidClock() throws {
        var replica = WorkspaceReplica(); replica.capture(entries: [entry("有效")], courses: [])
        XCTAssertEqual(try WorkspaceSyncDocument.decode(replica.document.encoded()), replica.document)
        var future = replica.document; future.version = 2
        XCTAssertThrowsError(try WorkspaceSyncDocument.decode(future.encoded()))
        var duplicate = replica.document; duplicate.entries += duplicate.entries
        XCTAssertThrowsError(try WorkspaceSyncDocument.decode(duplicate.encoded()))
        var invalid = replica.document
        invalid.entries[0] = SyncedRecord(id: invalid.entries[0].id, revision: SyncRevision(counter: UInt64.max, device: UUID()), value: invalid.entries[0].value)
        XCTAssertThrowsError(try WorkspaceSyncDocument.decode(invalid.encoded()))
    }
    func testLegacyBackupWithoutReplicaStillDecodes() throws {
        let archive = try EntryArchive.decode(EntryArchive(entries: [entry("旧版")]).encoded())
        XCTAssertNil(archive.replica); XCTAssertEqual(archive.entries.count, 1)
    }
    func testMalformedLocalReplicaClockIsRejectedBeforeEditing() throws {
        var replica = WorkspaceReplica(); replica.capture(entries: [entry("保护我")], courses: [])
        let bytes = try EntryArchive(entries: replica.entries, replica: replica).encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var saved = try XCTUnwrap(object["replica"] as? [String: Any])
        saved["counter"] = 0; object["replica"] = saved
        XCTAssertThrowsError(try EntryArchive.decode(JSONSerialization.data(withJSONObject: object)))
        saved["counter"] = 1_000_000_000_000; object["replica"] = saved
        XCTAssertThrowsError(try EntryArchive.decode(JSONSerialization.data(withJSONObject: object)))
    }
    func testDeletedCalendarOccurrenceIsSharedWithoutSharingSourceSelection() throws {
        let identity = CalendarEventIdentity(calendarID: "phone-calendar", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "shared-event", occurrence: "time:1800000000")
        var phone = WorkspaceReplica(), mac = WorkspaceReplica()
        phone.capture(entries: [], courses: [], suppressed: [identity]); mac.receive(phone.document)
        let decoded = try WorkspaceSyncDocument.decode(mac.document.encoded())
        XCTAssertEqual(decoded.deletedCalendarOccurrences, [identity])
        var archived = EntryArchive(entries: [], replica: mac)
        archived.calendarSync.selected = [CalendarSelection(id: "mac-calendar", title: "学习", sourceTitle: "iCloud")]
        let saved = try EntryArchive.decode(archived.encoded())
        XCTAssertEqual(saved.calendarSync.selected.first?.id, "mac-calendar")
        XCTAssertEqual(saved.replica?.document.deletedCalendarOccurrences, [identity])
    }
    func testCalendarSuppressionUnionConvergesWithDifferentDeviceCalendarIDs() {
        let aID = CalendarEventIdentity(calendarID: "phone", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "event")
        let bID = CalendarEventIdentity(calendarID: "mac", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "event")
        var a = WorkspaceReplica(), b = WorkspaceReplica()
        a.capture(entries: [], courses: [], suppressed: [aID]); b.capture(entries: [], courses: [], suppressed: [bID])
        let ad = a.document, bd = b.document; a.receive(bd); b.receive(ad)
        XCTAssertEqual(a.document, b.document)
        XCTAssertEqual(a.document.deletedCalendarOccurrences?.count, 2)
    }
    func testIndependentCalendarImportsCollapseWithoutDiscardingCustomizedCopy() {
        let identity = CalendarEventIdentity(calendarID: "shared", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "lecture")
        let event = CalendarEventRecord(identity: identity, title: "上课", start: now, end: now.addingTimeInterval(3600))
        let imported = CalendarImport.merge(events: [event], into: [], settings: CalendarSyncSettings(), now: now).entries[0]
        var other = imported; other.id = UUID()
        var phone = WorkspaceReplica(), mac = WorkspaceReplica()
        phone.capture(entries: [imported], courses: []); mac.capture(entries: [other], courses: [])
        let ad = phone.document, bd = mac.document; phone.receive(bd); mac.receive(ad)
        XCTAssertEqual(phone.entries, mac.entries); XCTAssertEqual(phone.entries.count, 1)
        other.body = "我添加的备注"; mac.capture(entries: [other], courses: [])
        phone.receive(mac.document)
        XCTAssertEqual(phone.entries.count, 1); XCTAssertEqual(phone.entries.first?.body, other.body)
    }
    func testDeviceCalendarRebindingDoesNotCreateSyncPingPong() {
        let phoneID = CalendarEventIdentity(calendarID: "phone", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "lecture", localEventID: "phone-event")
        let macID = CalendarEventIdentity(calendarID: "mac", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "lecture", localEventID: "mac-event")
        let phoneEvent = CalendarEventRecord(identity: phoneID, title: "上课", start: now, end: now.addingTimeInterval(3600))
        let macEvent = CalendarEventRecord(identity: macID, title: "上课", start: now, end: now.addingTimeInterval(3600))
        var imported = CalendarImport.merge(events: [phoneEvent], into: [], settings: CalendarSyncSettings(), now: now).entries[0]
        var replica = WorkspaceReplica(); replica.capture(entries: [imported], courses: [])
        let original = replica
        imported.calendarEvent = CalendarEventLink(event: macEvent, timing: .start); imported.updatedAt = now.addingTimeInterval(5)
        replica.capture(entries: [imported], courses: [])
        XCTAssertEqual(replica, original)
        imported.body = "实际修改"; replica.capture(entries: [imported], courses: [])
        XCTAssertGreaterThan(replica.counter, original.counter)
    }
    func testSuppressedCalendarOccurrenceCannotReturnThroughOfflineImport() {
        let identity = CalendarEventIdentity(calendarID: "shared", calendarTitle: "学习", sourceTitle: "iCloud", eventID: "lecture")
        let event = CalendarEventRecord(identity: identity, title: "上课", start: now, end: now.addingTimeInterval(3600))
        let imported = CalendarImport.merge(events: [event], into: [], settings: CalendarSyncSettings(), now: now).entries[0]
        var a = WorkspaceReplica(), b = WorkspaceReplica()
        a.capture(entries: [], courses: [], suppressed: [identity]); b.capture(entries: [imported], courses: [])
        b.receive(a.document); XCTAssertTrue(b.entries.isEmpty)
    }
    func testOfflineRoutineCompletionGeneratesOnlyOneSuccessor() throws {
        var original = entry("洗衣服"); original.dueDate = now; original.repeatRule = .daily
        let aNext = try XCTUnwrap(original.nextOccurrence(after: now))
        let bNext = try XCTUnwrap(original.nextOccurrence(after: now.addingTimeInterval(60)))
        var a = WorkspaceReplica(), b = WorkspaceReplica()
        a.capture(entries: [aNext], courses: []); b.capture(entries: [bNext], courses: [])
        let ad = a.document, bd = b.document; a.receive(bd); b.receive(ad)
        XCTAssertEqual(a.entries, b.entries); XCTAssertEqual(a.entries.count, 1)
        a.capture(entries: a.entries, courses: []); b.receive(a.document)
        XCTAssertEqual(b.entries.count, 1)
    }
    func testConcurrentFocusStartsKeepOnlyOneRunningTimer() {
        var first = entry("手机专注"), second = entry("电脑专注")
        first.startedAt = now; second.startedAt = now.addingTimeInterval(60)
        var phone = WorkspaceReplica(), mac = WorkspaceReplica()
        phone.capture(entries: [first], courses: []); mac.capture(entries: [second], courses: [])
        let left = phone.document, right = mac.document
        phone.receive(right); mac.receive(left)
        XCTAssertEqual(phone.entries, mac.entries)
        XCTAssertEqual(phone.entries.filter { $0.startedAt != nil }.count, 1)
        phone.capture(entries: phone.entries, courses: [])
        mac.receive(phone.document)
        XCTAssertEqual(mac.entries.filter { $0.startedAt != nil }.count, 1)
    }
    #if os(macOS)
    func testTwoDeviceFolderRoundTripAndDeletion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var phone = WorkspaceReplica(), mac = WorkspaceReplica(); let first = entry("手机事项"), second = entry("电脑事项")
        phone.capture(entries: [first], courses: []); mac.capture(entries: [second], courses: [])
        phone.receive(try FolderSyncTransport.exchange(snapshot: phone, folder: folder))
        mac.receive(try FolderSyncTransport.exchange(snapshot: mac, folder: folder))
        phone.receive(try FolderSyncTransport.exchange(snapshot: phone, folder: folder))
        XCTAssertEqual(Set(phone.entries.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(phone.document, mac.document)
        phone.capture(entries: [second], courses: [])
        phone.receive(try FolderSyncTransport.exchange(snapshot: phone, folder: folder))
        mac.receive(try FolderSyncTransport.exchange(snapshot: mac, folder: folder))
        XCTAssertEqual(mac.entries.map(\.id), [second.id])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Mikansei-sync").path).count, 2)
    }
    func testUnreadableRemoteStopsUploadWithoutOverwriting() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = folder.appendingPathComponent("Mikansei-sync")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let corrupt = directory.appendingPathComponent("replica-corrupt.json")
        let data = Data("malformed".utf8); try data.write(to: corrupt)
        var replica = WorkspaceReplica(); replica.capture(entries: [entry("本地")], courses: [])
        XCTAssertThrowsError(try FolderSyncTransport.exchange(snapshot: replica, folder: folder))
        XCTAssertEqual(try Data(contentsOf: corrupt), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("replica-\(replica.device.uuidString).json").path))
    }
    #endif
}
