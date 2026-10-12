import Foundation
import XCTest
@testable import MikanseiCore

final class MikanseiCoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return result
    }

    func testBoardSeparatesOverdueTodayUpcomingAndUnscheduledAcrossMidnight() {
        let late = Entry(title: "逾期作业", kind: .homework, dueDate: now.addingTimeInterval(-60))
        let today = Entry(title: "今天", dueDate: now.addingTimeInterval(60))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: now)!
        let future = Entry(title: "明天", dueDate: nextDay)
        let undated = Entry(title: "没有日期")
        let finished = Entry(title: "已完成", dueDate: now.addingTimeInterval(-60), isCompleted: true, completedAt: now)
        let note = Entry(title: "笔记", kind: .note)
        let board = TaskBoard(entries: [late, today, future, undated, finished, note], now: now, calendar: calendar)
        XCTAssertEqual(board.overdue.map(\.id), [late.id])
        XCTAssertEqual(board.today.map(\.id), [today.id])
        XCTAssertEqual(board.upcoming.map(\.id), [future.id])
        XCTAssertEqual(board.unscheduled.map(\.id), [undated.id])
        XCTAssertEqual(board.completedToday, 1)
        let midnight = calendar.startOfDay(for: nextDay)
        XCTAssertTrue(TaskBoard(entries: [today], now: midnight, calendar: calendar).today.isEmpty)
        XCTAssertEqual(TaskBoard(entries: [today], now: midnight, calendar: calendar).overdue.count, 1)
    }

    func testCompletingParentAndReopeningStepRestoresReminderEligibility() {
        let first = ChecklistItem(title: "阅读")
        var entry = Entry(title: "作业", checklist: [first, ChecklistItem(title: "提交")], dueDate: now.addingTimeInterval(3600), reminder: .fiveMinutes)
        entry.setCompleted(true, at: now)
        XCTAssertNil(entry.reminderDate)
        XCTAssertTrue(entry.checklist.allSatisfy(\.isDone))
        entry.toggleStep(first.id, at: now.addingTimeInterval(10))
        XCTAssertFalse(entry.isCompleted)
        XCTAssertNil(entry.completedAt)
        XCTAssertEqual(entry.completedSteps, 1)
        XCTAssertEqual(entry.reminderDate, now.addingTimeInterval(3300))
    }

    func testReminderPlanExcludesNotesCompletedAndPastAndLimitsNearestFirst() {
        let later = Entry(title: "后一个", dueDate: now.addingTimeInterval(7200), reminder: .atTime)
        let soon = Entry(title: "先一个", dueDate: now.addingTimeInterval(3600), reminder: .fiveMinutes)
        let completed = Entry(title: "完成", dueDate: now.addingTimeInterval(30), reminder: .atTime, isCompleted: true)
        let past = Entry(title: "过去", dueDate: now.addingTimeInterval(30), reminder: .fiveMinutes)
        let note = Entry(title: "笔记", kind: .note, dueDate: now.addingTimeInterval(30), reminder: .atTime)
        XCTAssertEqual(ReminderPlan.pending(entries: [later, past, completed, note, soon], now: now, limit: 1).map(\.id), [soon.id])
        XCTAssertTrue(ReminderPlan.pending(entries: [soon], now: now, limit: 0).isEmpty)
    }

    func testBackupRoundTripAndMergeKeepNewerLocalVersion() throws {
        let local = Entry(title: "修改后的作业", body: "中文与换行\n✓", kind: .homework, checklist: [ChecklistItem(title: "阅读")], createdAt: now, updatedAt: now)
        var older = local
        older.title = "旧标题"
        older.updatedAt = now.addingTimeInterval(-10)
        let added = Entry(title: "新笔记", kind: .note, createdAt: now, updatedAt: now)
        let decoded = try EntryArchive.decode(EntryArchive(entries: [older, added]).encoded())
        let merged = decoded.merging(into: [local])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first(where: { $0.id == local.id }), local)
        XCTAssertEqual(try EntryArchive.decode(EntryArchive(entries: [local]).encoded()).entries, [local])
    }

    func testInvalidBackupDoesNotOverwriteRepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = EntryRepository(fileURL: directory.appendingPathComponent("entries.json"))
        let entry = Entry(title: "保留的数据", createdAt: now, updatedAt: now)
        try repository.save([entry])
        XCTAssertThrowsError(try repository.save([entry, entry]))
        XCTAssertEqual(try repository.load(), [entry])
        XCTAssertThrowsError(try EntryArchive.decode(Data("{\"version\":2,\"entries\":[]}".utf8)))
        try Data("broken".utf8).write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), Data("broken".utf8))
    }

    func testConvertingTaskToNoteRemovesSchedulingAndCompletion() {
        let entry = Entry(title: "  灵感  ", kind: .note, checklist: [ChecklistItem(title: " "), ChecklistItem(title: "步骤")],
                          dueDate: now, reminder: .atTime, isCompleted: true, completedAt: now)
        let cleaned = entry.normalized(at: now)
        XCTAssertEqual(cleaned.title, "灵感")
        XCTAssertEqual(cleaned.checklist.count, 1)
        XCTAssertNil(cleaned.dueDate)
        XCTAssertNil(cleaned.reminder)
        XCTAssertNil(cleaned.completedAt)
        XCTAssertFalse(cleaned.isCompleted)
        XCTAssertTrue(cleaned.matches("步骤"))
    }
}
