import XCTest
import UIKit

final class FieldToolsUITests: XCTestCase {
    @MainActor private func launch(reset: Bool = true) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + (reset ? ["--reset-library"] : [])
        app.launch()
        if UIDevice.current.userInterfaceIdiom == .phone && app.frame.width > app.frame.height {
            XCUIDevice.shared.orientation = .landscapeRight
            XCUIDevice.shared.orientation = .portrait
        }
        XCTAssertTrue(app.buttons["scene_quick"].waitForExistence(timeout: 10)); return app
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
        let footer = app.frame.maxY
        // XCUI can mark an offscreen row hittable when it lies under the fixed footer.
        for _ in 0..<4 {
            if pitch.isHittable && pitch.frame.midY < footer - 8 { break }
            app.swipeUp()
        }
        XCTAssertLessThan(pitch.frame.midY, footer)
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
        app.buttons["notebookBack"].tap()
        app.buttons["notebookBack"].tap()
        app.buttons["recordsTab"].tap()
    }
    @MainActor private func name(_ app: XCUIApplication, _ value: String) {
        let field = app.textFields["fieldName"]; field.tap(); field.typeText(value + "\n")
        XCTAssertEqual(field.value as? String, value)
    }

    @MainActor func testBattingUndoResetRestoreHistoryContinueDelete() {
        var app = launch(); open(app, scene: "quick", tool: "battingLog"); name(app, "Batting round")
        tap(app, "batting_ground"); tap(app, "batting_line"); tap(app, "batting_fly"); tap(app, "batting_miss")
        XCTAssertTrue(label(app, "battingTotal").contains("4"))
        tap(app, "fieldUndo"); tap(app, "fieldOptions"); app.buttons["清零本轮"].tap(); app.buttons["清零本轮"].tap()
        tap(app, "fieldUndo")
        XCTAssertTrue(label(app, "battingTotal").contains("3"))
        tap(app, "fieldSave"); shot("phase00-batting")
        app.terminate(); app = launch(reset: false); open(app, scene: "quick", tool: "battingLog")
        XCTAssertTrue(label(app, "battingTotal").contains("3"))
        tap(app, "fieldEnd"); app.buttons["保存并结束本轮"].tap()
        toRecords(app)
        app.segmentedControls["recordSceneFilter"].buttons["随手工具"].tap()
        let record = app.staticTexts["Batting round"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        if app.buttons["打开记录"].isHittable { app.buttons["打开记录"].tap() }
        tap(app, "fieldResume"); tap(app, "batting_ground"); tap(app, "fieldSave")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        if app.buttons["deleteInspectedRecord"].isHittable {
            app.buttons["deleteInspectedRecord"].tap()
        } else {
            record.swipeLeft()
            app.buttons["删除"].firstMatch.tap()
        }
        app.alerts.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["没有符合筛选条件的记录"].waitForExistence(timeout: 5))
    }

    @MainActor func testScorebookAndRoundHistory() {
        let app = launch()
        open(app, scene: "quick", tool: "battingLog")
        tap(app, "batting_ground")
        tap(app, "batting_line")
        XCTAssertTrue(label(app, "battingTotal").contains("2"))
        tap(app, "fieldSave")
        let history = app.buttons["历史轮次"]
        for _ in 0..<3 where !history.isHittable { app.swipeUp() }
        history.tap()
        XCTAssertTrue(app.navigationBars["历史轮次"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.textFields["fieldName"].waitForExistence(timeout: 5))
    }

    @MainActor func testDualViewpointAndReplay() {
        let app = launch()
        app.buttons["bullpenShortcut"].tap()
        let picker = app.segmentedControls["pitchViewpoint"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["捕手后方"].tap()
        mapTap(app, x: 0.4, y: 0.35)
        picker.buttons["投手后方"].tap()
        mapTap(app, x: 0.02, y: 0.5)
        XCTAssertTrue(app.staticTexts["50%"].exists)
        tap(app, "pitchReplay")
        XCTAssertTrue(app.staticTexts["逐球回看"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "右上")).firstMatch.exists)
        app.buttons["下一球"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "偏左")).firstMatch.exists)
        app.segmentedControls["replayViewpoint"].buttons["捕手后方"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "偏右")).firstMatch.exists)
        app.buttons["replayPitch_1"].tap()
        XCTAssertFalse(app.buttons["上一球"].isEnabled)
        app.buttons["播放"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: app.buttons["下一球"])], timeout: 5), .completed)
        app.buttons["notebookBack"].tap()
        XCTAssertTrue(app.staticTexts["50%"].exists)
    }

    @MainActor func testBullpenGridCorrectionUndoReopenAndHistory() {
        var app = launch(); open(app, scene: "quick", tool: "bullpenLog"); name(app, "Bullpen round")
        XCTAssertTrue(app.buttons["bullpenOut"].isHittable)
        let wide = app.frame.width >= 700
        XCTAssertTrue(wide || app.staticTexts["fieldProcess"].isHittable)
        mapTap(app, x: 0.5, y: 0.49); mapTap(app, x: 0.5, y: 0.12)
        mapTap(app, x: 0.38, y: 0.32); mapTap(app, x: 0.65, y: 0.67); mapTap(app, x: 0.84, y: 0.42)
        tap(app, "bullpenOut")
        XCTAssertEqual(label(app, "bullpenTotal"), "5 球")
        if wide {
            XCTAssertTrue(app.buttons["pitchEvent_0"].isHittable)
        } else {
            XCTAssertFalse(app.buttons["pitchEvent_0"].isHittable)
            shot("pitch-compact-collapsed")
            app.staticTexts["fieldProcess"].tap()
        }
        tapFirstPitch(app)
        let correction = app.scrollViews["pitchCorrectionSheet"]
        XCTAssertTrue(correction.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["pitchCorrectionSave"])], timeout: 5), .completed)
        mapTap(app, x: 0.5, y: 0.85, correcting: true)
        let judgement = correction.segmentedControls["pitchStrikeToggle"].buttons["坏球"]
        for _ in 0..<3 { if judgement.isHittable { break }; correction.swipeUp() }
        XCTAssertTrue(judgement.isHittable)
        judgement.tap()
        shot("phase00-pitch-correction")
        app.buttons["pitchCorrectionSave"].tap()
        XCTAssertTrue(app.buttons["pitchEvent_0"].label.contains("偏低") && app.buttons["pitchEvent_0"].label.contains("坏球"))
        tap(app, "fieldUndo")
        XCTAssertTrue(app.buttons["pitchEvent_0"].label.contains("正中") && app.buttons["pitchEvent_0"].label.contains("好球"))
        tap(app, "fieldSave")
        app.swipeDown(); app.swipeDown(); shot("phase00-bullpen")
        app.terminate(); app = launch(reset: false); open(app, scene: "quick", tool: "bullpenLog")
        XCTAssertEqual(label(app, "bullpenTotal"), "5 球")
        toRecords(app); app.staticTexts["Bullpen round"].firstMatch.tap()
        if app.buttons["打开记录"].isHittable { app.buttons["打开记录"].tap() }
        if !wide {
            XCTAssertTrue(app.staticTexts["fieldProcess"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["pitchEvent_0"].isHittable)
            app.staticTexts["fieldProcess"].tap()
        }
        tapFirstPitch(app)
    }

    @MainActor func testGameBoundariesUndoAndSavedHistory() {
        var app = launch(); open(app, scene: "team", tool: "gameCounter"); name(app, "Game round")
        for id in ["game_awayRun", "game_homeRun", "game_ball", "game_strike", "game_out", "gameNextBatter", "fieldOptions"] {
            XCTAssertTrue(app.buttons[id].isHittable, id)
        }
        XCTAssertTrue(app.staticTexts["fieldProcess"].isHittable || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "本轮过程")).firstMatch.isHittable)
        XCTAssertFalse(app.buttons["game_removeAwayRun"].isEnabled)
        tap(app, "game_awayRun")
        tap(app, "game_removeAwayRun")
        XCTAssertEqual(app.buttons["game_awayRun"].value as? String, "0")
        XCTAssertFalse(app.buttons["game_removeAwayRun"].isEnabled)
        tap(app, "fieldUndo")
        tap(app, "game_homeRun"); tap(app, "game_homeRun")
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
        if app.buttons["打开记录"].isHittable { app.buttons["打开记录"].tap() }
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
        let sidebar = app.descendants(matching: .any).matching(identifier: "studioSidebar").firstMatch
        let studio = sidebar.waitForExistence(timeout: 2)
        if studio {
            app.buttons["sidebarScene_quick"].tap()
            app.buttons["tool_bullpenLog"].tap()
            XCTAssertTrue(app.textFields["fieldName"].waitForExistence(timeout: 5))
            mapTap(app, x: 0.5, y: 0.49); mapTap(app, x: 0.38, y: 0.33); mapTap(app, x: 0.85, y: 0.42)
            for _ in 0..<5 { if app.buttons["studioSidebarToggle"].isHittable { break }; sidebar.swipeDown() }
            app.buttons["studioSidebarToggle"].tap()
            XCTAssertFalse(sidebar.exists)
            XCTAssertTrue(label(app, "bullpenTotal").contains("3"))
            app.buttons["studioSidebarToggle"].tap()
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5)); shot("phase00-ipad-pitch-studio")
        } else {
            let scene = app.buttons["scene_quick"]
            let bottomTab = app.buttons["toolboxTab"]
            for _ in 0..<4 {
                if scene.isHittable && scene.frame.midY < bottomTab.frame.minY { break }
                app.swipeUp()
            }
            scene.tap()
            tap(app, "tool_battingLog")
            XCTAssertTrue(app.textFields["fieldName"].waitForExistence(timeout: 5)); shot("phase00-iphone-landscape")
        }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.textFields["fieldName"].waitForExistence(timeout: 5))
        if studio {
            XCTAssertTrue(label(app, "bullpenTotal").contains("3"))
        } else {
            tap(app, "batting_ground"); XCTAssertTrue(label(app, "battingTotal").contains("1"))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons[studio ? "tool_bullpenLog" : "tool_battingLog"].waitForExistence(timeout: 5))
    }
}
