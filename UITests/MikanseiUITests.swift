import XCTest

final class MikanseiUITests: XCTestCase {
    @MainActor
    func testCalendarMonthNavigationDayTimelineAndViewPreference() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--calendar-view-demo"]
        app.launch()
        app.tabBars.buttons["日程"].tap()
        app.buttons["schedule-view-2"].tap()
        app.buttons["calendar-layout-0"].tap()
        let today = app.buttons["calendar-date-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isSelected)
        let period = app.staticTexts["calendar-period-title"]
        let original = period.label
        app.buttons["calendar-next"].tap()
        XCTAssertNotEqual(period.label, original)
        app.buttons["calendar-today"].tap()
        XCTAssertEqual(period.label, original)
        let month = XCTAttachment(screenshot: app.screenshot()); month.name = "月历视图"; month.lifetime = .keepAlways; add(month)
        app.buttons["calendar-layout-1"].tap()
        XCTAssertTrue(app.staticTexts["报告 DDL"].waitForExistence(timeout: 5))
        let blocks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar-block-"))
        XCTAssertTrue(blocks.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks.firstMatch.isHittable, "时间轴应自动定位到当天的执行时段")
        let timeline = XCTAttachment(screenshot: app.screenshot()); timeline.name = "日时间轴"; timeline.lifetime = .keepAlways; add(timeline)
        blocks.firstMatch.tap()
        XCTAssertTrue(app.textFields["entry-title"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        app.terminate(); app.launch()
        app.tabBars.buttons["日程"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "calendar-day-view").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendar-layout-1"].isSelected)
    }

    @MainActor
    func testAlarmStyleAndRingtoneSelectionPersistWithDeadlineOnlyTask() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["新建事项"].tap()
        let title = app.textFields["entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Submit assignment")
        app.buttons["明天"].tap()
        app.buttons["补充 DDL、平台、耗时或循环"].tap()
        let delivery = app.descendants(matching: .any).matching(identifier: "reminder-delivery").firstMatch
        for _ in 0..<7 { if delivery.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(delivery.isHittable)
        delivery.tap()
        app.buttons["闹钟提醒"].tap()
        let ringtone = app.descendants(matching: .any).matching(identifier: "reminder-ringtone").firstMatch
        XCTAssertTrue(ringtone.isHittable)
        ringtone.tap()
        XCTAssertTrue(app.buttons["ringtone-chime"].waitForExistence(timeout: 5))
        app.buttons["ringtone-chime"].tap()
        let sound = XCTAttachment(screenshot: app.screenshot()); sound.name = "铃声选择"; sound.lifetime = .keepAlways; add(sound)
        app.navigationBars.buttons.firstMatch.tap()
        let options = XCTAttachment(screenshot: app.screenshot()); options.name = "提醒方式"; options.lifetime = .keepAlways; add(options)
        app.buttons["save-entry"].tap()
        XCTAssertTrue(app.staticTexts["Submit assignment"].waitForExistence(timeout: 5))
        app.staticTexts["Submit assignment"].tap()
        for _ in 0..<7 { if delivery.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["闹钟提醒"].exists)
        for _ in 0..<3 { if ringtone.isHittable { break }; app.swipeUp() }
        ringtone.tap()
        XCTAssertTrue(app.buttons["ringtone-chime"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ringtone-chime"].isSelected)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["取消"].tap()
    }

    @MainActor
    func testCalendarAutoImportDeduplicatesAndPreservesCompletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--calendar-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["日历同步演示"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "日历同步演示").count, 1)
        app.buttons["完成：日历同步演示"].tap()
        XCTAssertTrue(app.buttons["重新打开：日历同步演示"].waitForExistence(timeout: 5))
        app.buttons["设置"].tap()
        app.descendants(matching: .any).matching(identifier: "calendar-sync-settings").firstMatch.tap()
        let sync = app.buttons["calendar-sync-now"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        sync.tap()
        let status = app.staticTexts["calendar-sync-status"]
        expectation(for: NSPredicate(format: "label == %@", "已同步，没有新的变更。"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["重新打开：日历同步演示"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "日历同步演示").count, 1)
    }

    @MainActor
    func testCreateHomeworkAndCompleteItsChecklist() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["新建事项"].tap()
        app.buttons["kind-homework"].tap()
        let title = app.textFields["entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Read chapter 3")
        app.buttons["补充 DDL、平台、耗时或循环"].tap()
        let step = app.textFields["new-step"]
        step.tap()
        step.typeText("Take notes")
        app.buttons["add-step"].tap()
        app.buttons["save-entry"].tap()
        XCTAssertTrue(app.buttons["完成步骤：Take notes"].waitForExistence(timeout: 5))
        app.buttons["完成步骤：Take notes"].tap()
        XCTAssertTrue(app.buttons["取消完成步骤：Take notes"].exists)
        app.buttons["完成：Read chapter 3"].tap()
        XCTAssertTrue(app.buttons["重新打开：Read chapter 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今日已完成"].exists)
        app.descendants(matching: .any).matching(identifier: "task-status-filter").firstMatch.tap()
        app.buttons["历史记录"].tap()
        XCTAssertFalse(app.buttons["重新打开：Read chapter 3"].exists)
    }

    @MainActor
    func testFocusTimerStartPauseAndResume() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        let title = "完成英语阅读作业"
        let start = app.buttons["开始计时：\(title)"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let pause = app.buttons["暂停计时：\(title)"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        let clock = app.staticTexts["focus-clock"].firstMatch
        XCTAssertTrue(clock.exists)
        let initial = clock.label
        expectation(for: NSPredicate(format: "label != %@", initial), evaluatedWith: clock)
        waitForExpectations(timeout: 5)
        pause.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let paused = clock.label
        let wait = expectation(description: "paused duration remains")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { wait.fulfill() }
        waitForExpectations(timeout: 3)
        XCTAssertEqual(clock.label, paused)
        start.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDemoScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["完成英语阅读作业"].waitForExistence(timeout: 5))
        let today = XCTAttachment(screenshot: app.screenshot())
        today.name = "今天"
        today.lifetime = .keepAlways
        add(today)
        app.tabBars.buttons["笔记"].tap()
        XCTAssertTrue(app.staticTexts["一个好用的学习方法"].waitForExistence(timeout: 5))
        let notes = XCTAttachment(screenshot: app.screenshot())
        notes.name = "笔记"
        notes.lifetime = .keepAlways
        add(notes)
    }
}
