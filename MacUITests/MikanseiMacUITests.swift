import XCTest

final class MikanseiMacUITests: XCTestCase {
    @MainActor
    func testDesktopCreateEditCompleteAndSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.terminate(); app.launch(); app.activate()
        XCTAssertTrue(app.staticTexts["整理今日作业"].firstMatch.waitForExistence(timeout: 10))
        let initial = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); initial.name = "Mac初始界面"; initial.lifetime = .keepAlways; add(initial)
        app.typeKey("n", modifierFlags: .command)
        let title = app.textFields["entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // Digits avoid XCTest synthesizing Chinese-input-method word boundaries in a Latin title.
        app.activate(); title.click(); app.activate(); title.typeText("20261013")
        XCTAssertEqual(title.value as? String, "20261013")
        app.activate()
        app.typeKey("s", modifierFlags: .command)
        let row = app.staticTexts["20261013"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.click()
        XCTAssertTrue(app.buttons["完成事项"].waitForExistence(timeout: 5))
        app.buttons["完成事项"].click()
        XCTAssertTrue(app.buttons["重新打开"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "value == %@", "20261013")).count, 2, "清单中一行，详情中一个标题")
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); screenshot.name = "Mac三栏清单"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.activate(); app.buttons["设置"].click()
        XCTAssertTrue(app.buttons["选择 iCloud Drive 同步文件夹"].waitForExistence(timeout: 10))
    }
}
