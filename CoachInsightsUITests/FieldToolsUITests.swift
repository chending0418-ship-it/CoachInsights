import XCTest
import UIKit

final class FieldToolsUITests: XCTestCase {
    @MainActor private func launch(reset: Bool = true) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + (reset ? ["--reset-library"] : [])
        app.launch(); XCTAssertTrue(app.buttons["scene_quick"].waitForExistence(timeout: 10)); return app
    }
    @MainActor private func open(_ app: XCUIApplication, scene: String, tool: String) {
        app.buttons["scene_" + scene].tap(); app.buttons["tool_" + tool].tap()
        XCTAssertTrue(app.textFields["fieldName"].waitForExistence(timeout: 5))
    }
    @MainActor private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.buttons[id]
        for _ in 0..<5 { if element.isHittable { break }; app.swipeUp() }
        for _ in 0..<8 { if element.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(element.isHittable, id); element.tap()
    }
    @MainActor private func tapFirstPitch(_ app: XCUIApplication) {
        let pitch = app.buttons["pitchEvent_0"]
        let footer = app.buttons["fieldOptions"]
        // XCUI can mark an offscreen row hittable when it lies under the fixed footer.
        for _ in 0..<4 {
            if pitch.isHittable && pitch.frame.midY < footer.frame.minY - 8 { break }
            app.swipeUp()
        }
        XCTAssertLessThan(pitch.frame.midY, footer.frame.minY)
        pitch.tap()
    }

    @MainActor private func mapTap(_ app: XCUIApplication, x: CGFloat, y: CGFloat, correcting: Bool = false) {
        let scope = correcting ? app.scrollViews["pitchCorrectionSheet"] : app
        let map = scope.descendants(matching: .any).matching(identifier: "pitchMap").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }
    @MainActor private func label(_ app: XCUIApplication, _ id: String) -> String {
        app.descendants(matching: .any).matching(identifier: id).firstMatch.label
    }
    @MainActor private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func toRecords(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["recordsTab"].tap()
    }
    @MainActor private func name(_ app: XCUIApplication, _ value: String) {
        let field = app.textFields["fieldName"]; field.tap(); field.typeText(value + "\n")
        XCTAssertEqual(field.value as? String, value)
    }

    @MainActor func testBattingUndoResetRestoreHistoryContinueDelete() {
        var app = launch(); open(app, scene: "quick", tool: "battingLog"); name(app, "Batting round")
        for id in ["batting_ground", "batting_line", "batting_fly", "batting_miss", "fieldSave", "fieldOptions"] { XCTAssertTrue(app.buttons[id].isHittable, id) }
        tap(app, "batting_ground"); tap(app, "batting_line"); tap(app, "batting_fly"); tap(app, "batting_miss")
        XCTAssertTrue(label(app, "battingTotal").contains("4"))
        tap(app, "fieldUndo"); tap(app, "fieldOptions"); app.buttons["fieldReset"].tap(); app.buttons["清零本轮"].tap()
        tap(app, "fieldUndo")
        XCTAssertTrue(label(app, "battingTotal").contains("3"))
        tap(app, "fieldSave"); shot("phase00-batting")
        app.terminate(); app = launch(reset: false); open(app, scene: "quick", tool: "battingLog")
        XCTAssertTrue(label(app, "battingTotal").contains("3"))
        tap(app, "fieldOptions"); app.buttons["fieldEnd"].tap(); app.buttons["保存并结束本轮"].tap()
        toRecords(app)
        app.segmentedControls["recordSceneFilter"].buttons["随手工具"].tap()
        let record = app.staticTexts["Batting round"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        tap(app, "fieldResume"); tap(app, "batting_ground"); tap(app, "fieldSave")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        record.swipeLeft(); app.buttons["删除"].firstMatch.tap(); app.alerts.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["没有符合筛选条件的记录"].waitForExistence(timeout: 5))
    }

    @MainActor func testBullpenGridCorrectionUndoReopenAndHistory() {
        var app = launch(); open(app, scene: "quick", tool: "bullpenLog"); name(app, "Bullpen round")
        XCTAssertTrue(app.buttons["bullpenOut"].isHittable)
        XCTAssertTrue(app.staticTexts["fieldProcess"].isHittable)
        mapTap(app, x: 0.5, y: 0.49); mapTap(app, x: 0.5, y: 0.12)
        mapTap(app, x: 0.38, y: 0.32); mapTap(app, x: 0.65, y: 0.67); mapTap(app, x: 0.84, y: 0.42)
        tap(app, "bullpenOut")
        XCTAssertTrue(label(app, "bullpenTotal").contains("5"))
        XCTAssertFalse(app.buttons["pitchEvent_0"].isHittable)
        shot("pitch-compact-collapsed")
        app.staticTexts["fieldProcess"].tap()
        tapFirstPitch(app)
        let correction = app.scrollViews["pitchCorrectionSheet"]
        XCTAssertTrue(correction.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["pitchCorrectionSave"])], timeout: 5), .completed)
        mapTap(app, x: 0.5, y: 0.85, correcting: true)
        let judgement = correction.switches["pitchStrikeToggle"]
        for _ in 0..<3 { if judgement.isHittable { break }; correction.swipeUp() }
        XCTAssertTrue(judgement.isHittable)
        judgement.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        shot("phase00-pitch-correction")
        app.buttons["pitchCorrectionSave"].tap()
        XCTAssertTrue(app.buttons["pitchEvent_0"].label.contains("偏低") && app.buttons["pitchEvent_0"].label.contains("坏球"))
        tap(app, "fieldUndo")
        XCTAssertTrue(app.buttons["pitchEvent_0"].label.contains("正中") && app.buttons["pitchEvent_0"].label.contains("好球"))
        tap(app, "fieldSave")
        app.swipeDown(); app.swipeDown(); shot("phase00-bullpen")
        app.terminate(); app = launch(reset: false); open(app, scene: "quick", tool: "bullpenLog")
        XCTAssertTrue(label(app, "bullpenTotal").contains("5"))
        toRecords(app); app.staticTexts["Bullpen round"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["fieldProcess"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pitchEvent_0"].isHittable)
        app.staticTexts["fieldProcess"].tap()
        tapFirstPitch(app)
    }

    @MainActor func testGameBoundariesUndoAndSavedHistory() {
        var app = launch(); open(app, scene: "team", tool: "gameCounter"); name(app, "Game round")
        for id in ["game_awayRun", "game_homeRun", "game_ball", "game_strike", "game_out", "gameNextBatter", "fieldOptions"] {
            XCTAssertTrue(app.buttons[id].isHittable, id)
        }
        XCTAssertTrue(app.staticTexts["fieldProcess"].isHittable)
        tap(app, "game_awayRun"); tap(app, "game_homeRun"); tap(app, "game_homeRun")
        tap(app, "fieldUndo")
        XCTAssertEqual(app.buttons["game_awayRun"].value as? String, "1")
        XCTAssertEqual(app.buttons["game_homeRun"].value as? String, "1")
        XCTAssertTrue(app.buttons["gameEditCount"].isHittable)
        app.buttons["gameEditCount"].tap()
        let homeScore = app.textFields["editHomeScore"]
        XCTAssertTrue(homeScore.waitForExistence(timeout: 5))
        homeScore.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        homeScore.typeText(XCUIKeyboardKey.delete.rawValue + "4")
        XCTAssertEqual(homeScore.value as? String, "4")
        app.buttons["saveGameCount"].tap()
        XCTAssertEqual(app.buttons["game_homeRun"].value as? String, "4")
        tap(app, "fieldUndo")
        XCTAssertEqual(app.buttons["game_homeRun"].value as? String, "1")
        for _ in 0..<4 { tap(app, "game_ball") }
        XCTAssertTrue(app.staticTexts["gameBoundary"].label.contains("四坏"))
        for _ in 0..<3 { tap(app, "game_strike") }
        XCTAssertTrue(app.staticTexts["gameBoundary"].label.contains("三振"))
        tap(app, "game_out"); tap(app, "game_out")
        XCTAssertTrue(app.staticTexts["gameBoundary"].label.contains("换边"))
        XCTAssertTrue(app.staticTexts["gameSides"].label.contains("1"))
        tap(app, "fieldUndo"); XCTAssertTrue(app.staticTexts["gameSides"].label.contains("0"))
        tap(app, "fieldSave"); shot("phase00-game")
        app.terminate(); app = launch(reset: false)
        app.buttons["recordsTab"].tap(); app.segmentedControls["recordSceneFilter"].buttons["团训"].tap()
        let record = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "record_", "Game round")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        XCTAssertTrue(app.textFields["fieldName"].waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons["game_out"].value as? String, "2")
        XCTAssertEqual(app.buttons["game_awayRun"].value as? String, "1")
        XCTAssertEqual(app.buttons["game_homeRun"].value as? String, "1")
    }

    @MainActor func testShareCardLongContentPhotoAndCancel() {
        let app = launch(); app.buttons["shareCardExample"].tap()
        XCTAssertTrue(app.staticTexts["shareCardPageCount"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["shareCardPageCount"].label, "共 1 页")
        app.switches["shareCardLongExample"].coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let pagesChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "共 1 页"), object: app.staticTexts["shareCardPageCount"])
        XCTAssertEqual(XCTWaiter.wait(for: [pagesChanged], timeout: 8), .completed)
        XCTAssertNotEqual(app.staticTexts["shareCardPageCount"].label, "共 1 页")
        shot("phase00-card-preview")
        app.buttons["shareCardShare"].tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        let close = app.buttons["header.closeButton"]
        if close.waitForExistence(timeout: 5) { close.tap() } else { app.swipeDown() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: share)], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["shareCardSave"].waitForExistence(timeout: 5))
        app.buttons["shareCardSave"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if system.alerts.firstMatch.waitForExistence(timeout: 3) {
            for title in ["允许添加照片", "Allow Adding Photos", "允许", "Allow", "好", "OK"] {
                if system.alerts.buttons[title].exists { system.alerts.buttons[title].tap(); break }
            }
        }
        let saved = app.staticTexts["shareCardNotice"]
        for _ in 0..<8 { if saved.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); XCTAssertTrue(saved.label.contains("已保存"))
    }

    @MainActor func testLandscapeAndNarrowWindowNavigation() {
        let app = launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "studioSidebar").firstMatch.waitForExistence(timeout: 5))
            let sidebar = app.collectionViews["studioSidebar"]
            for _ in 0..<5 { if app.buttons["sidebar_bullpenLog"].isHittable { break }; sidebar.swipeUp() }
            app.buttons["sidebar_bullpenLog"].tap()
            XCTAssertTrue(app.textFields["fieldName"].waitForExistence(timeout: 5))
            mapTap(app, x: 0.5, y: 0.49); mapTap(app, x: 0.38, y: 0.33); mapTap(app, x: 0.85, y: 0.42)
            for _ in 0..<5 { if app.buttons["studioSidebarToggle"].isHittable { break }; sidebar.swipeDown() }
            app.buttons["studioSidebarToggle"].tap()
            XCTAssertFalse(sidebar.exists)
            XCTAssertTrue(label(app, "bullpenTotal").contains("3"))
            app.buttons["studioSidebarToggle"].tap()
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5)); shot("phase00-ipad-pitch-studio")
        } else {
            app.buttons["scene_quick"].tap(); app.buttons["tool_battingLog"].tap()
            XCTAssertTrue(app.textFields["fieldName"].waitForExistence(timeout: 5)); shot("phase00-iphone-landscape")
        }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.textFields["fieldName"].waitForExistence(timeout: 5))
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(label(app, "bullpenTotal").contains("3"))
        } else {
            tap(app, "batting_ground"); XCTAssertTrue(label(app, "battingTotal").contains("1"))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons[UIDevice.current.userInterfaceIdiom == .pad ? "tool_bullpenLog" : "tool_battingLog"].waitForExistence(timeout: 5))
    }
}
