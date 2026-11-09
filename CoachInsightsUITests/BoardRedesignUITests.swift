import XCTest

final class BoardRedesignUITests: XCTestCase {
    @MainActor private func waitForLandscape(_ app: XCUIApplication) {
        var previous = CGRect.null
        var stableSamples = 0
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.buttons["boardDraw"].frame
            stableSamples = frame == previous ? stableSamples + 1 : 0
            previous = frame
            return app.frame.width > app.frame.height && stableSamples >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed)
    }
    @MainActor func testSimpleBoardDrawingRoutesPlayersAndReopen() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-library"]; app.launch()
        XCTAssertTrue(app.buttons["scene_team"].waitForExistence(timeout: 10)); app.buttons["scene_team"].tap()
        app.buttons["tool_tacticsBoard"].tap()
        XCTAssertTrue(app.buttons["boardBack"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape(app)
        let field = app.otherElements["tacticsField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
        XCTAssertTrue(app.buttons["boardSelect"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["boardBack"].frame.width, 44)
        app.buttons["boardDraw"].tap()
        XCTAssertTrue(app.buttons["boardDraw"].isSelected)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35)).press(forDuration: 0.1,
            thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.5)))
        app.buttons["boardRoute"].tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.46)).press(forDuration: 0.1,
            thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.62)))
        app.buttons["boardUndo"].tap(); XCTAssertTrue(app.buttons["boardRedo"].isEnabled); app.buttons["boardRedo"].tap()
        app.buttons["boardRunners"].tap(); app.buttons["1 垒跑者"].tap()
        let runner = app.buttons["boardPlayer_跑1"]
        XCTAssertTrue(runner.waitForExistence(timeout: 5))
        let before = runner.frame.origin
        let center = runner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: -35, dy: 15)))
        XCTAssertNotEqual(before, runner.frame.origin, "短距离拖动也应移动球员")
        let afterShortMove = runner.frame.origin
        runner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.57, dy: 0.5)))
        XCTAssertNotEqual(afterShortMove, runner.frame.origin)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "simple-whiteboard-landscape"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["boardBack"].tap()
        XCTAssertTrue(app.buttons["tool_tacticsBoard"].waitForExistence(timeout: 5))
        app.buttons["tool_tacticsBoard"].tap()
        XCTAssertTrue(app.buttons["boardPlayer_跑1"].waitForExistence(timeout: 5))
        waitForLandscape(app)
        app.buttons["boardClear"].tap(); app.buttons["清空白板"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["boardPlayer_投"])
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
        app.buttons["boardUndo"].tap(); XCTAssertTrue(app.buttons["boardPlayer_投"].exists)
        app.buttons["boardBack"].tap()
        XCUIDevice.shared.orientation = .portrait
    }
}
