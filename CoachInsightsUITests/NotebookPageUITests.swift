import XCTest

final class NotebookPageUITests: XCTestCase {
    @MainActor func testHelpPrivacyAndNotebookNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["使用帮助"].firstMatch.tap()
        let question = app.buttons["怎样记球、修正或回看一轮训练？"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        question.tap()
        let privacy = app.buttons["隐私与本机数据"]
        for _ in 0..<3 where !privacy.isHittable { app.swipeUp() }
        privacy.tap()
        XCTAssertTrue(app.navigationBars["隐私与本机数据"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "notebook-privacy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
