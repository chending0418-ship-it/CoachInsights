import XCTest
import UIKit

final class CoachInsightsUITests: XCTestCase {
    @MainActor func testIPadWindowViewportChanges() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad viewport resizing scenario") }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library", "--layout-probe"]
        app.launch()
        XCTAssertTrue(app.buttons["narrowViewport"].waitForExistence(timeout: 5))
        app.buttons["narrowViewport"].tap()
        XCTAssertTrue(app.buttons["createSession"].waitForExistence(timeout: 5))
        app.buttons["createSession"].tap()
        XCTAssertTrue(app.textFields["sessionName"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        let narrow = XCTAttachment(screenshot: app.screenshot())
        narrow.name = "ipad-360pt-viewport"; narrow.lifetime = .keepAlways; add(narrow)
        app.buttons["wideViewport"].tap()
        XCTAssertTrue(app.buttons["createSession"].waitForExistence(timeout: 3))
        app.buttons["createSession"].tap()
        XCTAssertTrue(app.textFields["sessionName"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
    }
    @MainActor func testLibraryLifecycleNavigationAndRotation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library"]
        app.launch()
        XCTAssertTrue(app.buttons["createSession"].waitForExistence(timeout: 10))
        app.buttons["createSession"].tap()
        let field = app.textFields["sessionName"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap(); field.typeText("Simulator batting")
        app.buttons["confirmCreate"].tap()
        let record = app.staticTexts["Simulator batting"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        let rename = app.buttons["renameSession"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        let alert = app.alerts.firstMatch
        let renameField = alert.textFields.firstMatch
        renameField.tap()
        renameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        renameField.typeText("Saved analysis")
        alert.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["Saved analysis"].waitForExistence(timeout: 3))
        app.staticTexts["双视频对比"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["将两次动作放在一起"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["导出分析"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["分享动作里的发现"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["renameSession"].waitForExistence(timeout: 3))
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "landscape-analysis"; landscape.lifetime = .keepAlways; add(landscape)
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let saved = app.staticTexts["Saved analysis"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        let portrait = XCTAttachment(screenshot: app.screenshot())
        portrait.name = "portrait-library"; portrait.lifetime = .keepAlways; add(portrait)
        saved.tap()
        app.buttons["deleteSession"].tap()
        app.alerts.firstMatch.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["从一份分析开始"].waitForExistence(timeout: 5))
    }
    @MainActor func testDebugProbeRunsInSimulator() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library"]
        app.launch()
        let open = app.buttons["openProbe"]
        if !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        XCTAssertTrue(app.buttons["runProbe"].waitForExistence(timeout: 5))
        app.buttons["runProbe"].tap()
        XCTAssertTrue(app.staticTexts["probeComplete"].waitForExistence(timeout: 60),
                      app.staticTexts["probeError"].label)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "media-probe"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
