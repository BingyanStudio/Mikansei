import XCTest

final class MikanseiUITests: XCTestCase {
    @MainActor
    func testFolderSyncSettingsAndVersionAreVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["设置"].tap()
        let folder = app.buttons["选择 iCloud Drive 同步文件夹"]
        for _ in 0..<5 { if folder.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(folder.isHittable)
        XCTAssertTrue(app.staticTexts["尚未选择同步文件夹"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "iPhone跨设备同步设置"; screenshot.lifetime = .keepAlways; add(screenshot)
        let version = app.descendants(matching: .any).matching(identifier: "app-version").firstMatch
        for _ in 0..<12 { if version.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(version.exists)
        XCTAssertEqual(version.value as? String, "0.3.1 (5)")
    }
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
        XCTAssertFalse(app.staticTexts["日历同步演示"].exists)
        app.buttons["设置"].tap()
        app.descendants(matching: .any).matching(identifier: "calendar-sync-settings").firstMatch.tap()
        let source = app.switches["calendar-source-calendar-demo"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "0")
        XCTAssertEqual(app.switches["calendar-source-calendar-demo-holidays"].value as? String, "0")
        source.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["完成"].tap()
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

    /// Starting a timer must update that card in place: one live clock, no leftover "开始做" card.
    @MainActor
    func testFocusStartUpdatesCardInPlace() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        let title = "买一盏阅读灯"
        let start = app.buttons["开始计时：\(title)"]
        for _ in 0..<8 { if start.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        let pause = app.buttons["暂停计时：\(title)"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertFalse(start.exists, "开始后不应残留显示「开始做」的旧卡片")
        XCTAssertEqual(app.staticTexts.matching(identifier: "focus-clock").count, 1)
        let clock = app.staticTexts["focus-clock"].firstMatch
        let initial = clock.label
        expectation(for: NSPredicate(format: "label != %@", initial), evaluatedWith: clock)
        waitForExpectations(timeout: 5)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "正在做"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testCalendarLongPressOpensScheduleWithDurationAndAlarmDefaults() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--calendar-view-demo"]
        app.launch()
        app.tabBars.buttons["日程"].tap()
        app.buttons["schedule-view-2"].tap()
        app.buttons["calendar-layout-0"].tap()
        let today = app.buttons["calendar-date-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.press(forDuration: 0.7)
        XCTAssertTrue(app.navigationBars["新建日程"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["kind-schedule"].isSelected)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "schedule-start").firstMatch.exists)
        XCTAssertTrue(app.textFields["schedule-duration"].exists)
        XCTAssertFalse(app.switches["has-due-date"].exists)
        app.buttons["取消"].tap()
        app.buttons["calendar-layout-1"].tap()
        let hour = app.buttons["calendar-hour-8"]
        XCTAssertTrue(hour.waitForExistence(timeout: 5))
        hour.press(forDuration: 0.7)
        XCTAssertTrue(app.navigationBars["新建日程"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testScheduleDurationRoutineDatesAndReminderCanBeEdited() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["新建事项"].tap()
        app.buttons["kind-schedule"].tap()
        let title = app.textFields["entry-title"]
        title.tap(); title.typeText("Routine practice")
        app.buttons["收起键盘"].tap()
        let duration = app.textFields["schedule-duration"]
        duration.tap(); duration.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "45")
        app.buttons["收起键盘"].tap()
        let routine = app.switches["routine-enabled"]
        for _ in 0..<8 { if routine.isHittable { break }; app.swipeUp() }
        routine.tap()
        let rule = app.descendants(matching: .any).matching(identifier: "routine-rule").firstMatch
        rule.tap(); app.buttons["日历选日"].tap()
        let picker = app.descendants(matching: .any).matching(identifier: "routine-date-picker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let dates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine-date-"))
        let selectedDay = dates.element(boundBy: 41) // Adjacent next month: always a future date.
        for _ in 0..<4 { if selectedDay.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(selectedDay.isHittable)
        selectedDay.tap()
        XCTAssertTrue(selectedDay.isSelected)
        let delivery = app.descendants(matching: .any).matching(identifier: "reminder-delivery").firstMatch
        for _ in 0..<8 { if delivery.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["闹钟提醒"].exists)
        app.buttons["save-entry"].tap()
        XCTAssertTrue(app.staticTexts["Routine practice"].waitForExistence(timeout: 5))
        app.staticTexts["Routine practice"].tap()
        XCTAssertTrue(app.textFields["schedule-duration"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["schedule-duration"].value as? String, "45")
    }

    @MainActor
    func testRapidCompletionAndReopenDoesNotLoseState() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        for title in ["完成英语阅读作业", "给自己留半小时运动", "准备明天的学习资料", "买一盏阅读灯"] {
            let complete = app.buttons["完成：" + title]
            for _ in 0..<8 { if complete.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(complete.isHittable)
            complete.tap()
        }
        let reopened = app.buttons["重新打开：买一盏阅读灯"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        reopened.tap()
        XCTAssertTrue(app.buttons["完成：买一盏阅读灯"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["操作未完成"].exists)
    }

    @MainActor
    func testDeadlineLiveActivityStartsUpdatesAndStops() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--deadline-activity-demo"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["完成：紧急作业"].waitForExistence(timeout: 10), "需先确认合成事项已加载")
        app.buttons["设置"].tap()
        let toggle = app.switches["deadline-live-activity-enabled"]
        for _ in 0..<7 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        let status = app.descendants(matching: .any).matching(identifier: "deadline-live-activity-status").firstMatch
        for _ in 0..<7 { if status.exists && status.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(status.exists)
        let refresh = app.buttons["deadline-live-activity-refresh"]
        for _ in 0..<3 { if refresh.isHittable { break }; app.swipeUp() }
        refresh.tap()
        let starts = NSPredicate(format: "label == %@", "正在显示 · 4 件未完成")
        expectation(for: starts, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCUIDevice.shared.press(.home)
        let island = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        island.name = "DDL实时活动-灵动岛"; island.lifetime = .keepAlways; add(island)
        app.activate()
        app.buttons["完成"].tap()
        app.tabBars.buttons["待办"].tap()
        let first = app.buttons["完成：紧急作业"]
        for _ in 0..<4 { if first.exists && first.isHittable { break }; app.swipeUp() }
        first.tap()
        app.buttons["设置"].tap()
        for _ in 0..<7 { if status.exists && status.isHittable { break }; app.swipeUp() }
        expectation(for: NSPredicate(format: "label == %@", "正在显示 · 3 件未完成"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        let settings = XCTAttachment(screenshot: app.screenshot())
        settings.name = "DDL实时活动-完成后更新"; settings.lifetime = .keepAlways; add(settings)
        for _ in 0..<4 { if toggle.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "1")
        // SwiftUI exposes the whole labeled row as Switch; tap the visible trailing control.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        expectation(for: NSPredicate(format: "label == %@", "未开启"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCUIDevice.shared.press(.home)
        let ended = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        ended.name = "DDL实时活动-关闭后"; ended.lifetime = .keepAlways; add(ended)
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
