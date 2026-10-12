import Foundation
import XCTest
@testable import MikanseiCore

final class TaskBoardWidgetTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    private var lateNight: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23, minute: 59))! }

    func testCompletedItemsStayAtEndUntilLocalMidnightAndCanBeReopened() {
        let now = lateNight
        let open = Entry(title: "未完成")
        var first = Entry(title: "刚完成的作业", kind: .homework, dueDate: now.addingTimeInterval(-3600))
        var second = Entry(title: "完成的家务")
        first.setCompleted(true, at: now.addingTimeInterval(-30))
        second.setCompleted(true, at: now)
        let old = Entry(title: "昨天完成", isCompleted: true, completedAt: now.addingTimeInterval(-86400))
        let board = TaskBoard(entries: [second, old, open, first], now: now, calendar: calendar)
        XCTAssertEqual(board.visible.map(\.id), [open.id, first.id, second.id])
        XCTAssertEqual(board.history.map(\.id), [old.id])
        XCTAssertTrue(board.overdue.isEmpty)
        let tomorrow = TaskBoard(entries: board.entries, now: now.addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(tomorrow.visible.map(\.id), [open.id])
        XCTAssertEqual(tomorrow.history.map(\.id), [second.id, first.id, old.id])
        first.setCompleted(false, at: now)
        let reopened = TaskBoard(entries: [open, first, second], now: now, calendar: calendar)
        XCTAssertEqual(reopened.overdue.map(\.id), [first.id])
        XCTAssertEqual(reopened.finishedToday.map(\.id), [second.id])
    }

    func testPriorityThenDeadlineAndOverdueSectionComesBeforeUrgentFuture() {
        let now = lateNight
        let overdue = Entry(title: "普通但已超时", dueDate: now.addingTimeInterval(-10))
        let important = Entry(title: "重要", priority: .important, dueDate: now.addingTimeInterval(10))
        let urgentLater = Entry(title: "紧急但晚一点", priority: .urgent, dueDate: now.addingTimeInterval(300))
        let urgentFirst = Entry(title: "紧急且更早", priority: .urgent, dueDate: now.addingTimeInterval(100))
        let urgentUndated = Entry(title: "紧急无日期", priority: .urgent)
        let board = TaskBoard(entries: [important, urgentUndated, urgentLater, overdue, urgentFirst], now: now, calendar: calendar)
        XCTAssertEqual(board.visible.map(\.id), [overdue.id, urgentFirst.id, urgentLater.id, urgentUndated.id, important.id])
    }

    func testLegacyCompletionWithoutDateGoesToHistoryAndNotesNeverEnterBoard() {
        let legacy = Entry(title: "旧版本完成项", isCompleted: true)
        let note = Entry(title: "笔记", kind: .note, isCompleted: true, completedAt: lateNight)
        let board = TaskBoard(entries: [legacy, note], now: lateNight, calendar: calendar)
        XCTAssertEqual(board.history.map(\.id), [legacy.id])
        XCTAssertTrue(board.visible.isEmpty)
    }

    func testSnapshotOmitsPrivateDetailsAndRecomputesCompletionAfterMidnight() throws {
        var task = Entry(title: "写作业", body: "私有内容", kind: .homework,
                         checklist: [ChecklistItem(title: "私有步骤")], dueDate: lateNight)
        task.source = "私有消息"; task.platform = "私有平台"
        var done = Entry(title: "已完成")
        done.setCompleted(true, at: lateNight)
        let snapshot = WidgetSnapshot(entries: [task, done, Entry(title: "私有笔记", kind: .note)], now: lateNight, calendar: calendar)
        let data = try JSONEncoder().encode(snapshot)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("私有"))
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded.board(at: lateNight, calendar: calendar).focus.map(\.id), [task.id, done.id])
        let next = decoded.board(at: lateNight.addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(next.focus.map(\.id), [task.id])
        XCTAssertEqual(next.overdue.map(\.id), [task.id])
    }

    func testWidgetRoutesRoundTripAndRejectUnknownInput() {
        let routes: [AppRoute] = [.today, .tasks, .new(.task), .new(.homework), .new(.note), .entry(UUID()), .focus(UUID(), .start), .focus(UUID(), .pause)]
        for route in routes { XCTAssertEqual(AppRoute(url: route.url), route) }
        for raw in ["https://today", "mikansei://entry/not-a-uuid", "mikansei://unknown", "mikansei://new?kind=unknown", "mikansei://focus/not-a-uuid?action=start", "mikansei://focus/\(UUID())?action=unknown"] {
            XCTAssertNil(AppRoute(url: URL(string: raw)!))
        }
    }

    func testFocusPauseResumeCompletionAndRoutineReset() throws {
        let now = lateNight
        var task = Entry(title: "作业", dueDate: now)
        task.repeatRule = .daily
        task = try XCTUnwrap(FocusSession.updating([task], id: task.id, isRunning: true, at: now)?.first)
        XCTAssertEqual(task.focusDuration(at: now.addingTimeInterval(60)), 60)
        task.pauseFocus(at: now.addingTimeInterval(90))
        XCTAssertEqual(task.focusDuration(at: now.addingTimeInterval(600)), 90)
        task = try XCTUnwrap(FocusSession.updating([task], id: task.id, isRunning: true, at: now.addingTimeInterval(600))?.first)
        task.setCompleted(true, at: now.addingTimeInterval(660))
        XCTAssertNil(task.startedAt)
        XCTAssertEqual(task.focusDuration(at: now.addingTimeInterval(2000)), 150)
        XCTAssertEqual(task.focusTimeLabel(), "2:30")
        let next = try XCTUnwrap(task.nextOccurrence(after: now.addingTimeInterval(660), calendar: calendar))
        XCTAssertEqual(next.elapsedSeconds, 0)
        XCTAssertNil(next.startedAt)
        XCTAssertNil(FocusSession.updating([task], id: task.id, isRunning: true, at: now))
    }

    func testOnlyOneFocusRunsAndRepeatedWidgetCommandsAreIdempotent() throws {
        let now = lateNight
        var a = Entry(title: "A"); a.startedAt = now
        let b = Entry(title: "B")
        var entries = try XCTUnwrap(FocusSession.updating([a, b], id: b.id, isRunning: true, at: now.addingTimeInterval(30)))
        XCTAssertNil(entries[0].startedAt)
        XCTAssertEqual(entries[0].elapsedSeconds, 30)
        XCTAssertEqual(entries[1].startedAt, now.addingTimeInterval(30))
        let repeated = try XCTUnwrap(FocusSession.updating(entries, id: b.id, isRunning: true, at: now.addingTimeInterval(60)))
        XCTAssertEqual(entries, repeated)
        entries = try XCTUnwrap(FocusSession.updating(entries, id: b.id, isRunning: false, at: now.addingTimeInterval(90)))
        XCTAssertEqual(entries[1].elapsedSeconds, 60)
        XCTAssertEqual(FocusSession.updating(entries, id: b.id, isRunning: false, at: now.addingTimeInterval(120)), entries)
    }

    func testFocusPersistsAcrossBackupAndOldArchivesDefaultToZero() throws {
        var task = Entry(title: "作业")
        task.elapsedSeconds = 120; task.startedAt = lateNight
        let data = try EntryArchive(entries: [task]).encoded()
        let restored = try XCTUnwrap(EntryArchive.decode(data).entries.first)
        XCTAssertEqual(restored.focusDuration(at: lateNight.addingTimeInterval(180)), 300)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "elapsedSeconds")
        entries[0].removeValue(forKey: "startedAt")
        json["entries"] = entries
        let legacy = try XCTUnwrap(EntryArchive.decode(JSONSerialization.data(withJSONObject: json)).entries.first)
        XCTAssertEqual(legacy.elapsedSeconds, 0)
        XCTAssertNil(legacy.startedAt)
    }

    func testFocusedSnapshotShowsActiveThenPausedAndEndsAtMidnight() throws {
        var a = Entry(title: "A"); a.elapsedSeconds = 90; a.updatedAt = lateNight.addingTimeInterval(-10)
        var b = Entry(title: "B"); b.startedAt = lateNight
        var snapshot = WidgetSnapshot(entries: [a, b], now: lateNight, calendar: calendar)
        XCTAssertEqual(snapshot.focusedTask(at: lateNight, calendar: calendar)?.id, b.id)
        b.pauseFocus(at: lateNight.addingTimeInterval(10))
        snapshot = WidgetSnapshot(entries: [a, b], now: lateNight, calendar: calendar)
        XCTAssertEqual(snapshot.focusedTask(at: lateNight, calendar: calendar)?.elapsedSeconds, 10)
        b.setCompleted(true, at: lateNight.addingTimeInterval(20))
        snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(WidgetSnapshot(entries: [a, b], now: lateNight, calendar: calendar)))
        XCTAssertTrue(try XCTUnwrap(snapshot.focusedTask(at: lateNight, calendar: calendar)).isCompleted)
        XCTAssertEqual(snapshot.focusedTask(at: lateNight.addingTimeInterval(60), calendar: calendar)?.id, a.id)
    }
}
