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

    func testSortOrderLeadsTaskBoardOrder() {
        var first = Entry(title: "手动第一", dueDate: now.addingTimeInterval(86400), createdAt: now, updatedAt: now)
        first.sortOrder = 1
        var second = Entry(title: "手动第二", priority: .urgent, dueDate: now.addingTimeInterval(60), createdAt: now, updatedAt: now)
        second.sortOrder = 2
        let unsorted = Entry(title: "未排序", priority: .urgent, dueDate: now, createdAt: now, updatedAt: now)
        XCTAssertTrue(TaskBoard.order(first, second))
        XCTAssertFalse(TaskBoard.order(second, first))
        XCTAssertTrue(TaskBoard.order(second, unsorted))
        XCTAssertFalse(TaskBoard.order(unsorted, first))
        // 两个未排序的回退到原有规则：先比优先级。
        let fallbackDate = Entry(title: "回退日期", dueDate: now, createdAt: now, updatedAt: now)
        let fallbackUrgent = Entry(title: "回退紧急", priority: .urgent, dueDate: now.addingTimeInterval(86400), createdAt: now, updatedAt: now)
        XCTAssertTrue(TaskBoard.order(fallbackUrgent, fallbackDate))
        let board = TaskBoard(entries: [unsorted, second, first], now: now, calendar: calendar)
        XCTAssertEqual(board.open.map(\.id), [first.id, second.id, unsorted.id])
    }

    func testPlannedDaysIncludeTodayInBoardToday() {
        var planned = Entry(title: "规划今天", createdAt: now, updatedAt: now)
        planned.plannedDays = [now.addingTimeInterval(-3600), calendar.date(byAdding: .day, value: 2, to: now)!]
        var future = Entry(title: "只规划后天", createdAt: now, updatedAt: now)
        future.plannedDays = [calendar.date(byAdding: .day, value: 2, to: now)!]
        var overdue = Entry(title: "超时不进今天", dueDate: now.addingTimeInterval(-3600), createdAt: now, updatedAt: now)
        overdue.plannedDays = [now]
        let board = TaskBoard(entries: [planned, future, overdue], now: now, calendar: calendar)
        XCTAssertEqual(board.today.map(\.id), [planned.id])
    }

    func testEntryCodableRoundTripKeepsSortOrderAndPlannedDays() throws {
        var entry = Entry(title: "同步字段", createdAt: now, updatedAt: now)
        entry.sortOrder = -3
        entry.plannedDays = [now, now.addingTimeInterval(3600)]
        let restored = try EntryArchive.decode(EntryArchive(entries: [entry]).encoded()).entries[0]
        XCTAssertEqual(restored.sortOrder, -3)
        XCTAssertEqual(restored.plannedDays, [now, now.addingTimeInterval(3600)])
        // 归一化把规划日期折叠到按天并去重；笔记清空规划日期。
        var dated = Entry(title: "按天", createdAt: now, updatedAt: now)
        dated.plannedDays = [now.addingTimeInterval(-3600), now.addingTimeInterval(3600)]
        XCTAssertEqual(dated.normalized(at: now).plannedDays, [calendar.startOfDay(for: now)])
        var note = Entry(title: "笔记", kind: .note, createdAt: now, updatedAt: now)
        note.plannedDays = [now]; note.sortOrder = 5
        XCTAssertNil(note.normalized(at: now).plannedDays)
        // 缺失新键的旧归档按 nil 处理。
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: EntryArchive(entries: [entry]).encoded()) as? [String: Any])
        var entries = raw["entries"] as! [[String: Any]]
        entries[0].removeValue(forKey: "sortOrder"); entries[0].removeValue(forKey: "plannedDays")
        raw["entries"] = entries
        let legacy = try EntryArchive.decode(JSONSerialization.data(withJSONObject: raw)).entries[0]
        XCTAssertNil(legacy.sortOrder)
        XCTAssertNil(legacy.plannedDays)
    }

    func testPlannedBlockStartReminderOpensFocusAndSkipsSchedulesAndDuplicates() throws {
        let start = calendar.startOfDay(for: now).addingTimeInterval(15 * 3600)
        let before = start.addingTimeInterval(-1800)
        var task = Entry(title: "整理错题", createdAt: before.addingTimeInterval(-86400), updatedAt: before.addingTimeInterval(-86400))
        task.plannedStart = start; task.plannedEnd = start.addingTimeInterval(1800)
        var schedule = Entry(title: "看牙医", kind: .schedule, createdAt: before.addingTimeInterval(-86400))
        schedule.plannedStart = start; schedule.plannedEnd = start.addingTimeInterval(1800)
        var finished = Entry(title: "已完成", isCompleted: true, completedAt: before.addingTimeInterval(-3600), createdAt: before, updatedAt: before)
        finished.plannedStart = start; finished.plannedEnd = start.addingTimeInterval(1800)
        var tomorrow = Entry(title: "明天的时段", createdAt: before, updatedAt: before)
        tomorrow.plannedStart = start.addingTimeInterval(86400); tomorrow.plannedEnd = start.addingTimeInterval(86400 + 1800)
        let plan = NotificationPlan.pending(entries: [task, schedule, finished, tomorrow], courses: [], now: before, calendar: calendar)
        let block = try XCTUnwrap(plan.first { $0.entryID == task.id })
        XCTAssertEqual(block.date, start)
        XCTAssertEqual(block.title, "到点了：整理错题")
        XCTAssertEqual(block.body, "规划时段开始，回来专注吧")
        XCTAssertEqual(block.openURL, AppRoute.focus(task.id, .start).url.absoluteString)
        XCTAssertEqual(block.delivery, .popup)
        XCTAssertTrue(block.isStillEnabled(entries: [task], courses: []))
        XCTAssertTrue(plan.filter { $0.entryID == schedule.id && $0.title.hasPrefix("到点了：") }.isEmpty)
        XCTAssertNil(plan.first { $0.entryID == finished.id })
        XCTAssertTrue(plan.filter { $0.entryID == tomorrow.id }.isEmpty)
        // 已有提醒恰好落在开始时刻时不再重复推送。
        task.reminder = .atTime; task.reminderAnchor = .execution
        let deduped = NotificationPlan.pending(entries: [task], courses: [], now: before, calendar: calendar)
        XCTAssertEqual(deduped.filter { $0.date == start }.count, 1)
    }

    func testNextPlannedBlockPicksEarliestUnfinishedWithinSixtyMinutes() {
        var soon = Entry(title: "半小时后", createdAt: now, updatedAt: now)
        soon.plannedStart = now.addingTimeInterval(1800); soon.plannedEnd = now.addingTimeInterval(3600)
        var later = Entry(title: "五十八分钟后", createdAt: now, updatedAt: now)
        later.plannedStart = now.addingTimeInterval(3480); later.plannedEnd = now.addingTimeInterval(5280)
        var beyond = Entry(title: "两小时后", createdAt: now, updatedAt: now)
        beyond.plannedStart = now.addingTimeInterval(7200); beyond.plannedEnd = now.addingTimeInterval(9000)
        var done = Entry(title: "已完成", isCompleted: true, completedAt: now, createdAt: now, updatedAt: now)
        done.plannedStart = now.addingTimeInterval(60); done.plannedEnd = now.addingTimeInterval(120)
        let snapshot = WidgetSnapshot(entries: [later, beyond, done, soon], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.nextPlannedBlock(at: now)?.id, soon.id)
        XCTAssertEqual(snapshot.nextPlannedBlock(at: now.addingTimeInterval(1801))?.id, later.id)
        XCTAssertNil(snapshot.nextPlannedBlock(at: now.addingTimeInterval(3481)))
    }
}
