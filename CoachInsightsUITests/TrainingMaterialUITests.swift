import XCTest

final class TrainingMaterialUITests: XCTestCase {
  @MainActor func testTeamPlanStartsTimerAndRecoversAfterRelaunch() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--reset-library"]
    app.launch()
    func enter(_ tool: String) {
      if app.buttons["sidebar_" + tool].isHittable {
        app.buttons["sidebar_" + tool].tap()
      } else {
        app.buttons["scene_team"].tap()
        app.buttons["tool_" + tool].tap()
      }
    }
    enter("teamPlan")
    app.buttons["newTraining"].tap()
    let title = app.textFields["trainingTitle"]
    title.tap()
    title.typeText("U12 defense")
    let stage = app.textFields["stageName"]
    if !stage.isHittable { app.swipeUp() }
    stage.tap()
    stage.typeText("Warmup")
    app.buttons["trainingSave"].tap()
    XCTAssertTrue(app.staticTexts["U12 defense"].firstMatch.waitForExistence(timeout: 6))
    app.terminate()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    enter("planTimer")
    app.buttons["startPlanTimer"].tap()
    XCTAssertTrue(app.staticTexts["planRemaining"].waitForExistence(timeout: 5))
    app.buttons["暂停"].tap()
    app.terminate()
    app.launch()
    enter("planTimer")
    XCTAssertTrue(app.buttons["继续"].waitForExistence(timeout: 5))
  }
}
