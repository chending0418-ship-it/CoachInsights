import XCTest
import UIKit

final class QuickToolsUITests: XCTestCase {
    @MainActor private func launch(reset: Bool = true, scene: String = "quick") -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (reset ? ["--reset-library"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["scene_quick"].waitForExistence(timeout: 10))
        app.buttons["scene_" + scene].tap()
        return app
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        // Screen capture avoids XCTest cropping the application using its old
        // portrait bounds after a scene-requested landscape transition.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func wait(_ predicate: String, on element: XCUIElement, timeout: Double = 8) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: timeout), .completed)
    }
    @MainActor private func allowSystemPrompt() {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = system.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            for title in ["允许添加照片", "Allow Adding Photos", "允许", "Allow", "好", "OK"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return }
            }
        }
    }
    @MainActor private func boardButton(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let button = app.buttons[id]
        if !button.isHittable { app.scrollViews["boardTools"].swipeLeft() }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        return button
    }

    @MainActor func testStopwatchLapsBackgroundPauseAndReopen() {
        var app = launch()
        app.buttons["tool_stopwatch"].tap()
        XCTAssertTrue(app.staticTexts["stopwatchTime"].waitForExistence(timeout: 5))
        app.buttons["stopwatchToggle"].tap()
        app.buttons["stopwatchLapReset"].tap()
        app.buttons["stopwatchLapReset"].tap()
        XCTAssertTrue(app.staticTexts["分段 2"].exists)
        let before = app.staticTexts["stopwatchTime"].label
        XCUIDevice.shared.press(.home); app.activate()
        wait("hittable == true", on: app.buttons["stopwatchToggle"])
        app.buttons["stopwatchToggle"].tap()
        wait("label == '启动'", on: app.buttons["stopwatchToggle"])
        let paused = app.staticTexts["stopwatchTime"].label
        XCTAssertNotEqual(before, paused)
        shot(app, "quick-stopwatch-portrait")
        app.terminate()
        app = launch(reset: false); app.buttons["tool_stopwatch"].tap()
        XCTAssertEqual(app.staticTexts["stopwatchTime"].label, paused)
        XCTAssertTrue(app.staticTexts["分段 2"].exists)
        XCTAssertTrue(app.buttons["stopwatchToggle"].isHittable)
        app.buttons["stopwatchLapReset"].tap()
        XCTAssertTrue(app.staticTexts["stopwatchTime"].label.contains("00:00.00"))
    }

    @MainActor func testCountdownPauseResumeCancelAndFinish() {
        let app = launch()
        app.buttons["tool_countdown"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        shot(app, "quick-countdown-setup")
        app.buttons["30 秒"].tap(); app.buttons["countdownToggle"].tap(); allowSystemPrompt()
        XCTAssertTrue(app.staticTexts["countdownTime"].waitForExistence(timeout: 5))
        shot(app, "quick-countdown-running")
        app.buttons["countdownToggle"].tap()
        let paused = app.staticTexts["countdownTime"].label
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(app.staticTexts["countdownTime"].label, paused)
        app.buttons["countdownToggle"].tap()
        app.buttons["countdownCancel"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "0")
        app.pickerWheels.element(boundBy: 2).adjust(toPickerWheelValue: "3")
        app.buttons["countdownToggle"].tap()
        wait("label CONTAINS '00:00'", on: app.staticTexts["countdownTime"])
        XCTAssertTrue(app.staticTexts["时间到"].waitForExistence(timeout: 5))
        app.buttons["countdownCancel"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testWhiteboardLandscapeDrawingPlayersPhotoAndRecords() {
        let app = launch(scene: "team")
        app.buttons["tool_tacticsBoard"].tap()
        XCTAssertTrue(app.buttons["boardBack"].waitForExistence(timeout: 5))
        let field = app.otherElements["tacticsField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.firstMatch.exists, "白板只保留自己的工具栏，不重复占用系统导航栏空间")
        // First verify the app itself requested landscape while the device is
        // still portrait. Then align the simulated device for XCTest's event
        // and screenshot coordinate system.
        wait("value CONTAINS '横屏'", on: field)
        XCUIDevice.shared.orientation = .landscapeLeft
        var previousFrame = CGRect.null
        var stableSamples = 0
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.buttons["boardDraw"].frame
            stableSamples = frame == previousFrame ? stableSamples + 1 : 0
            previousFrame = frame
            return app.frame.width > app.frame.height && stableSamples >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed)
        app.buttons["boardDraw"].tap()
        XCTAssertTrue(app.buttons["boardDraw"].isSelected)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.6))
            .press(forDuration: 0.1, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.25)))
        XCTAssertTrue(boardButton(app, "boardUndo").isEnabled)
        boardButton(app, "boardUndo").tap(); XCTAssertTrue(boardButton(app, "boardRedo").isEnabled)
        boardButton(app, "boardRedo").tap()
        boardButton(app, "boardRunners").tap(); app.buttons["1 垒跑者"].tap()
        let runner = app.buttons["boardPlayer_跑1"]
        XCTAssertTrue(runner.waitForExistence(timeout: 5))
        let original = runner.frame
        runner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.57, dy: 0.5)))
        XCTAssertNotEqual(runner.frame.origin, original.origin)
        let pitcher = app.buttons["boardPlayer_投"]
        XCTAssertTrue(pitcher.exists)
        shot(app, "quick-tactics-landscape")
        app.buttons["boardSaveImage"].tap(); allowSystemPrompt()
        wait("label CONTAINS '已保存到相册'", on: app.staticTexts["boardNotice"], timeout: 12)
        app.buttons["boardBack"].tap()
        XCTAssertTrue(app.buttons["tool_tacticsBoard"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["recordsTab"].tap()
        app.segmentedControls["recordSceneFilter"].buttons["团训"].tap()
        let record = app.staticTexts["战术白板"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        XCTAssertTrue(app.buttons["boardPlayer_跑1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["boardBack"].exists)
        app.buttons["boardBack"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["recordSceneFilter"].waitForExistence(timeout: 5))
        record.swipeLeft(); app.buttons["删除"].firstMatch.tap(); app.alerts.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["没有符合筛选条件的记录"].waitForExistence(timeout: 5))
    }

    @MainActor func testDistanceSimulatorShowsActualAvailability() {
        let app = launch()
        app.buttons["tool_distance"].tap()
        XCTAssertTrue(app.staticTexts["此设备不支持 AR 测距"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["distancePlace"].exists)
        shot(app, "quick-distance-simulator")
    }
}
