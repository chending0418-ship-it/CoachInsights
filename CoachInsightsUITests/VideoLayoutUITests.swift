import XCTest
import UIKit

final class VideoLayoutUITests: XCTestCase {
    @MainActor private func launch(reset: Bool = true) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (reset ? ["--reset-library"] : [])
        app.launch(); XCTAssertTrue(app.buttons["scene_personal"].waitForExistence(timeout: 10)); return app
    }
    @MainActor private func create(_ app: XCUIApplication, name: String) {
        app.buttons["scene_personal"].tap(); app.buttons["tool_videoAnalysis"].tap()
        app.buttons["createSession"].tap()
        let field = app.textFields["sessionName"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(name); app.buttons["confirmCreate"].tap()
        let row = app.staticTexts[name].firstMatch; XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
    }
    @MainActor private func fixture(_ app: XCUIApplication) {
        let second = app.staticTexts["frameReadout"].exists
        if !app.buttons["importFixture"].firstMatch.isHittable {
            app.buttons["videoOptions"].tap(); app.buttons["添加素材"].tap()
        }
        XCTAssertTrue(app.buttons["importFixture"].firstMatch.waitForExistence(timeout: 5)); app.buttons["importFixture"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["frameReadout"].waitForExistence(timeout: 15))
        wait(second ? "label CONTAINS '/ 240 帧'" : "label CONTAINS '/ 60 帧'", on: app.staticTexts["frameReadout"], timeout: 15)
    }
    @MainActor private func wait(_ predicate: String, on element: XCUIElement, timeout: TimeInterval = 8) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: timeout), .completed)
    }
    @MainActor private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func side(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "comparisonSide" + name).firstMatch
    }
    @MainActor private func assertLayout(_ app: XCUIApplication, vertical: Bool) {
        let a = side(app, "A"), b = side(app, "B")
        XCTAssertTrue(a.waitForExistence(timeout: 5)); XCTAssertTrue(b.waitForExistence(timeout: 5))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            vertical ? b.frame.minY > a.frame.minY + 20 && abs(a.frame.minX - b.frame.minX) < 3
                : b.frame.minX > a.frame.minX + 20 && abs(a.frame.minY - b.frame.minY) < 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }

    @MainActor func testPhoneLandscapeCanvasKeepsFrameAnnotationAndControls() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Phone landscape focus")
        let app = launch(); create(app, name: "Landscape review"); fixture(app)
        app.buttons["nextFrame"].tap(); app.buttons["nextFrame"].tap()
        app.buttons["drawingTools"].tap(); app.buttons["tool_line"].tap()
        let canvas = app.otherElements["analysisCanvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65)))
        wait("label CONTAINS '1 个标注'", on: app.staticTexts["annotationCount"])
        app.buttons["drawingTools"].tap()
        let before = app.staticTexts["frameReadout"].label
        XCUIDevice.shared.orientation = .landscapeLeft
        wait("label CONTAINS '退出全屏'", on: app.buttons["analysisFullscreen"])
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
        XCTAssertGreaterThan(canvas.frame.width, canvas.frame.height)
        XCTAssertGreaterThan(canvas.frame.height, min(app.frame.width, app.frame.height) * 0.72)
        for id in ["playPause", "previousFrame", "nextFrame", "playbackRate", "drawingTools", "closeVideo"] { XCTAssertTrue(app.buttons[id].isHittable, id) }
        XCTAssertEqual(app.staticTexts["frameReadout"].label, before)
        shot("video-phone-landscape-focus")
        app.buttons["nextFrame"].tap(); app.buttons["previousFrame"].tap()
        XCUIDevice.shared.orientation = .portrait
        wait("label == '横屏全屏'", on: app.buttons["analysisFullscreen"])
        XCTAssertEqual(app.staticTexts["frameReadout"].label, before)
        wait("label CONTAINS '1 个标注'", on: app.staticTexts["annotationCount"])
        shot("video-phone-portrait-restored")
    }

    @MainActor func testExplicitFullscreenEntryExitAndCloseRemainAvailable() {
        let app = launch(); create(app, name: "Fullscreen return"); fixture(app)
        let before = app.staticTexts["frameReadout"].label
        app.buttons["analysisFullscreen"].tap()
        wait("label CONTAINS '退出全屏'", on: app.buttons["analysisFullscreen"])
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["closeVideo"].isHittable)
        XCTAssertTrue(app.buttons["playbackRate"].isHittable)
        shot("video-explicit-fullscreen")
        app.buttons["analysisFullscreen"].tap()
        XCUIDevice.shared.orientation = .portrait
        wait("label == '横屏全屏'", on: app.buttons["analysisFullscreen"])
        XCTAssertEqual(app.staticTexts["frameReadout"].label, before)
        app.buttons["closeVideo"].tap()
        XCTAssertTrue(app.buttons["createSession"].waitForExistence(timeout: 5))
    }

    @MainActor func testIPadPortraitComparisonAutomaticRotationAndManualRestore() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad comparison layout")
        var app = launch(); create(app, name: "Portrait comparison"); fixture(app); fixture(app)
        app.buttons["openComparison"].tap()
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chooseVideo_")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 10)); choice.tap()
        XCTAssertTrue(app.buttons["comparisonPlay"].waitForExistence(timeout: 10))
        let picker = app.segmentedControls["comparisonLayout"]
        XCTAssertTrue(picker.buttons["自动"].isSelected); assertLayout(app, vertical: true)
        app.sliders["leftSlider"].adjust(toNormalizedSliderPosition: 0.2)
        let frame = app.sliders["leftSlider"].value as? String
        shot("comparison-ipad-portrait-automatic")
        XCUIDevice.shared.orientation = .landscapeLeft
        assertLayout(app, vertical: false)
        XCTAssertEqual(app.sliders["leftSlider"].value as? String, frame)
        shot("comparison-ipad-landscape-automatic")
        picker.buttons["上下"].tap(); assertLayout(app, vertical: true)
        XCUIDevice.shared.orientation = .portrait
        assertLayout(app, vertical: true); XCTAssertTrue(picker.buttons["上下"].isSelected)
        picker.buttons["左右"].tap(); assertLayout(app, vertical: false)
        app.terminate(); app = launch(reset: false)
        app.buttons["recordsTab"].tap()
        let record = app.staticTexts["Portrait comparison"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        XCTAssertTrue(app.buttons["comparisonPlay"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls["comparisonLayout"].buttons["左右"].isSelected)
        assertLayout(app, vertical: false)
        app.segmentedControls["comparisonLayout"].buttons["自动"].tap()
        assertLayout(app, vertical: true)
    }
}
