import Foundation
import XCTest
@testable import MikanseiCore

final class DeadlineActivityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12))! }

    func testOnlyOpenTodayOverdueAndUndatedEntriesAppear() throws {
        let today = Entry(title: "今日报告", dueDate: now.addingTimeInterval(3600))
        let overdue = Entry(title: "昨天的作业", dueDate: now.addingTimeInterval(-86400))
        let undated = Entry(title: "联系家里")
        var completed = Entry(title: "已完成", dueDate: now); completed.setCompleted(true, at: now)
        let future = Entry(title: "未来事项", priority: .urgent, dueDate: now.addingTimeInterval(86400))
        let note = Entry(title: "笔记", kind: .note)
        let state = try XCTUnwrap(DeadlineActivitySnapshot.make(entries: [completed, future, note, today, overdue, undated], now: now, calendar: calendar))
        XCTAssertEqual(state.totalCount, 3)
        XCTAssertEqual(state.items.map(\.id), [overdue.id, today.id, undated.id])
        XCTAssertEqual(state.validUntil, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
    }
    func testImportanceThenDeadlineSelectsPrimaryAndCompletionPromotesNext() throws {
        let overdue = Entry(title: "普通超时", dueDate: now.addingTimeInterval(-60))
        var urgent = Entry(title: "最紧急", priority: .urgent, dueDate: now.addingTimeInterval(1800))
        let urgentLater = Entry(title: "紧急但更晚", priority: .urgent, dueDate: now.addingTimeInterval(3600))
        var state = try XCTUnwrap(DeadlineActivitySnapshot.make(entries: [overdue, urgentLater, urgent], now: now, calendar: calendar))
        XCTAssertEqual(state.primary?.id, urgent.id)
        XCTAssertEqual(state.primary?.deadline, urgent.dueDate)
        urgent.setCompleted(true, at: now)
        state = try XCTUnwrap(DeadlineActivitySnapshot.make(entries: [overdue, urgentLater, urgent], now: now, calendar: calendar))
        XCTAssertEqual(state.primary?.id, urgentLater.id)
        XCTAssertEqual(state.totalCount, 2)
    }
    func testScheduleUsesStartWhileDDLRemainsSeparate() throws {
        var schedule = Entry(title: "社团例会", kind: .schedule, priority: .urgent)
        schedule.plannedStart = now.addingTimeInterval(1800)
        schedule.plannedEnd = now.addingTimeInterval(5400)
        let state = try XCTUnwrap(DeadlineActivitySnapshot.make(entries: [schedule], now: now, calendar: calendar))
        XCTAssertTrue(try XCTUnwrap(state.primary).isSchedule)
        XCTAssertEqual(state.primary?.deadline, schedule.plannedStart)
        XCTAssertNil(schedule.dueDate)
        var legacyTask = Entry(title: "只有执行时段的旧待办")
        legacyTask.plannedStart = now; legacyTask.plannedEnd = now.addingTimeInterval(3600)
        let legacy = try XCTUnwrap(DeadlineActivitySnapshot.make(entries: [legacyTask], now: now, calendar: calendar))
        XCTAssertNil(legacy.primary?.deadline, "普通待办不能把隐藏的开始时间伪装成 DDL")
    }
    func testEmptyAndFinishedListsEndTheActivity() {
        XCTAssertNil(DeadlineActivitySnapshot.make(entries: [], now: now, calendar: calendar))
        var completed = Entry(title: "完成"); completed.setCompleted(true, at: now)
        XCTAssertNil(DeadlineActivitySnapshot.make(entries: [completed], now: now, calendar: calendar))
        XCTAssertNil(DeadlineActivitySnapshot.make(entries: [Entry(title: "明天", dueDate: now.addingTimeInterval(86400))], now: now, calendar: calendar))
    }
    func testPayloadIsBoundedAndContainsNoNotesOrPlatform() throws {
        var entries = (0..<200).map { Entry(title: String(repeating: "作业", count: 100) + "\($0)", body: "私密备注", category: "科目", checklist: [ChecklistItem(title: "私密步骤")]) }
        entries[0].platform = "私密平台"; entries[0].source = "群消息原文"
        let state = try XCTUnwrap(DeadlineActivitySnapshot.make(entries: entries, now: now, calendar: calendar))
        XCTAssertEqual(state.items.count, 3)
        XCTAssertEqual(state.totalCount, 200)
        let data = try JSONEncoder().encode(state)
        XCTAssertLessThan(data.count, 4096)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for privateText in ["私密备注", "私密步骤", "私密平台", "群消息原文"] { XCTAssertFalse(text.contains(privateText)) }
        XCTAssertEqual(try JSONDecoder().decode(DeadlineActivitySnapshot.self, from: data), state)
    }
    func testExpirationUsesLocalMidnightAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let state = try XCTUnwrap(DeadlineActivitySnapshot.make(entries: [Entry(title: "无日期")], now: start, calendar: calendar))
            XCTAssertEqual(state.dayEnd.timeIntervalSince(start), Double(hours * 3600))
            XCTAssertEqual(state.validUntil, state.dayEnd)
        }
    }
}
