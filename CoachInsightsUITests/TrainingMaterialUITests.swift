import XCTest

final class TrainingMaterialUITests: XCTestCase {
  @MainActor private func enter(_ app: XCUIApplication, scene: String, tool: String) {
    let shortcut = app.buttons["sidebar_" + tool]
    if shortcut.exists && shortcut.isHittable { shortcut.tap(); return }
    let sceneButton = app.buttons["scene_" + scene]
    let destination = app.buttons["tool_" + tool]
    XCTAssertTrue(sceneButton.waitForExistence(timeout: 8))
    for _ in 0..<2 {
      if !sceneButton.isHittable { app.swipeUp() }
      sceneButton.tap()
      if destination.waitForExistence(timeout: 4) { break }
      if !sceneButton.exists { app.swipeUp(); break }
    }
    XCTAssertTrue(destination.waitForExistence(timeout: 5))
    destination.tap()
  }

  @MainActor func testNotesAndHomeworkOpenTheirSavedShareCard() {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    for (index, tool) in ["coachNotes", "homeworkCard"].enumerated() {
      app.launchArguments = index == 0 ? ["--ui-testing", "--reset-library"] : ["--ui-testing"]
      app.launch()
      enter(app, scene: "personal", tool: tool)
      app.buttons["newTraining"].tap()
      let title = app.textFields["trainingTitle"]
      title.tap(); title.typeText(tool)
      func fill(_ id: String, _ text: String) {
        let field = app.descendants(matching: .any).matching(identifier: id).firstMatch
        for _ in 0..<3 { if field.isHittable { break }; app.swipeUp() }
        field.tap(); field.typeText(text)
      }
      fill("trainingBody", "Infield practice")
      if index == 1 { fill("trainingFocus", "3 x 8") }
      app.buttons["trainingSave"].tap()
      if !app.buttons["trainingShare"].isHittable { app.staticTexts[tool].firstMatch.tap() }
      app.buttons["trainingShare"].tap()
      XCTAssertTrue(app.staticTexts["shareCardPageCount"].waitForExistence(timeout: 8))
      app.terminate()
    }
  }

  @MainActor func testTeamPlanStartsTimerAndRecoversAfterRelaunch() {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--reset-library"]
    app.launch()
    enter(app, scene: "team", tool: "teamPlan")
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
    enter(app, scene: "team", tool: "planTimer")
    app.buttons["startPlanTimer"].tap()
    XCTAssertTrue(app.staticTexts["planRemaining"].waitForExistence(timeout: 5))
    app.buttons["暂停"].tap()
    app.terminate()
    app.launch()
    enter(app, scene: "team", tool: "planTimer")
    XCTAssertTrue(app.buttons["继续"].waitForExistence(timeout: 5))
  }
}
