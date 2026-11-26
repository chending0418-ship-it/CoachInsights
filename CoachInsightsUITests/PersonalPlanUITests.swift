import XCTest
import UIKit

final class PersonalPlanUITests: XCTestCase {
    @MainActor func testCreatePreviewReopenEditShareAndDelete() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        app.buttons["scene_personal"].tap()
        let tool = app.buttons["tool_personalPlan"]
        XCTAssertTrue(tool.waitForExistence(timeout: 10))
        tool.tap()
        app.buttons["newPersonalPlan"].tap()

        let save = app.buttons["savePersonalPlan"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        let title = app.textFields["personalPlanTitle"]
        title.tap()
        title.typeText("Practice plan")
        XCTAssertFalse(save.isEnabled)
        let drills = app.descendants(matching: .any).matching(identifier: "personalPlanDrills").firstMatch
        if !drills.isHittable { app.swipeUp() }
        drills.tap()
        drills.typeText("Warm up\nThrow 10 balls")
        XCTAssertTrue(save.isEnabled)

        let modes = app.segmentedControls["personalPlanEditorMode"]
        if modes.exists { modes.buttons["预览"].tap() }
        XCTAssertEqual(app.staticTexts["personalPlanPreviewTitle"].label, "Practice plan")
        capture(app, named: "phase01-editor-preview")
        save.tap()
        XCTAssertTrue(app.staticTexts["Practice plan"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["recordsTab"].tap()
        app.segmentedControls["recordSceneFilter"].buttons["私教"].tap()
        let record = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "record_", "Practice plan")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        if app.buttons["打开记录"].isHittable { app.buttons["打开记录"].tap() }
        app.buttons["editPersonalPlan"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(" revised")
        app.buttons["cancelPersonalPlan"].tap()
        app.alerts.buttons["继续编辑"].tap()
        save.tap()
        XCTAssertEqual(app.staticTexts["personalPlanPreviewTitle"].label, "Practice plan revised")

        app.buttons["personalPlanShare"].tap()
        let count = app.staticTexts["shareCardPageCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "共 1 页")
        capture(app, named: "phase01-plan-image")
        app.buttons["shareCardShare"].tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        let close = app.buttons["header.closeButton"]
        if close.waitForExistence(timeout: 5) { close.tap() } else { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["shareCardNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["shareCardNotice"].label.contains("已取消分享"))

        app.buttons["shareCardSave"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3) {
            for title in ["允许添加照片", "Allow Adding Photos", "允许", "Allow", "好", "OK"] {
                if springboard.alerts.buttons[title].exists { springboard.alerts.buttons[title].tap(); break }
            }
        }
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "已保存"),
                                              object: app.staticTexts["shareCardNotice"])
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)

        app.navigationBars["图片预览"].buttons.element(boundBy: 0).tap()
        app.navigationBars["计划详情"].buttons.element(boundBy: 0).tap()
        let updated = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "record_", "Practice plan revised")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        updated.swipeLeft()
        app.buttons["删除"].tap()
        app.alerts.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["没有符合筛选条件的记录"].waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
