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
        app.buttons["createSession"].tap()
        let field=app.textFields["sessionName"];field.tap();field.typeText("Resizable analysis")
        app.buttons["confirmCreate"].tap();app.staticTexts["Resizable analysis"].firstMatch.tap()
        let fixture=app.buttons["importFixture"];reveal(fixture,in:app);fixture.tap()
        let readout=app.staticTexts["frameReadout"];XCTAssertTrue(readout.waitForExistence(timeout:15))
        app.buttons["narrowViewport"].tap()
        app.staticTexts["Resizable analysis"].firstMatch.tap()
        XCTAssertTrue(readout.waitForExistence(timeout:10))
        let next=app.buttons["nextFrame"];reveal(next,in:app);next.tap()
        XCTAssertTrue(readout.label.contains("第 2 /"),readout.label)
        app.buttons["wideViewport"].tap()
        XCTAssertTrue(readout.waitForExistence(timeout:10))
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

extension CoachInsightsUITests {
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication,up:Bool=true) {
        for _ in 0..<10 {
            var scrollUp=up
            if element.exists {
                let frame=element.frame
                let top=app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY+4 : app.frame.minY+40
                let bottom=app.frame.maxY-34
                if element.isHittable,frame.minY>=top,frame.maxY<=bottom { return }
                if frame.minY<top { scrollUp=false } else if frame.maxY>bottom { scrollUp=true }
            }
            // The canvas owns pan/drawing gestures. Scroll in the surrounding margin.
            let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:scrollUp ? 0.72:0.3))
            let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:scrollUp ? 0.3:0.72))
            start.press(forDuration:0.01,thenDragTo:end)
        }
    }
    @MainActor func testCompleteAnalysisAnnotationReopenAndExport() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-library"];app.launch()
        app.buttons["createSession"].tap()
        let name=app.textFields["sessionName"];name.tap();name.typeText("Full workflow")
        app.buttons["confirmCreate"].tap();app.staticTexts["Full workflow"].firstMatch.tap()
        let fixture=app.buttons["importFixture"];reveal(fixture,in:app);fixture.tap()
        let readout=app.staticTexts["frameReadout"];XCTAssertTrue(readout.waitForExistence(timeout:15))
        reveal(readout,in:app,up:false)
        let next=app.buttons["nextFrame"];reveal(next,in:app);next.tap()
        XCTAssertTrue(readout.label.contains("第 2 /"),readout.label)
        let line=app.buttons["tool_line"];reveal(line,in:app);line.tap()
        let canvas=app.otherElements["analysisCanvas"].firstMatch
        reveal(canvas,in:app,up:false)
        XCTAssertTrue(canvas.isHittable)
        canvas.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.4)).press(forDuration:0.1,thenDragTo:canvas.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:0.7)))
        let count=app.staticTexts["annotationCount"];reveal(count,in:app)
        XCTAssertTrue(count.label.contains("1 个标注"),count.label)
        let undo=app.buttons["undoAnnotation"];undo.tap();XCTAssertTrue(count.label.contains("0 个标注"))
        app.buttons["重做"].tap();XCTAssertTrue(count.label.contains("1 个标注"))
        let keyframe=app.buttons["addKeyframe"];reveal(keyframe,in:app);keyframe.tap()
        app.alerts.textFields.firstMatch.tap();app.alerts.textFields.firstMatch.typeText("Contact")
        app.alerts.buttons["保存"].tap();XCTAssertTrue(count.label.contains("1 个关键帧"))
        XCUIDevice.shared.orientation = .landscapeLeft
        reveal(next,in:app,up:false);next.tap()
        XCTAssertTrue(readout.label.contains("第 3 /"),readout.label)
        XCUIDevice.shared.orientation = .portrait
        let poseTools=app.buttons["poseTools"];reveal(poseTools,in:app);poseTools.tap()
        let runPose=app.buttons["runPose"];reveal(runPose,in:app);runPose.tap()
        let status=app.descendants(matching:.any).matching(identifier:"poseStatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout:20))
        let complete=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@","分析完成"),object:status)
        XCTAssertEqual(XCTWaiter.wait(for:[complete],timeout:20),.completed,status.label)
        app.buttons["完成"].tap()
        app.terminate();app.launchArguments=["--ui-testing"];app.launch();app.staticTexts["Full workflow"].firstMatch.tap()
        XCTAssertTrue(readout.waitForExistence(timeout:10));reveal(count,in:app)
        XCTAssertTrue(count.label.contains("1 个标注"));XCTAssertTrue(count.label.contains("1 个关键帧"))
        let export=app.staticTexts["导出分析"].firstMatch;reveal(export,in:app);export.tap()
        let screenshot=app.buttons["exportScreenshot"];XCTAssertTrue(screenshot.waitForExistence(timeout:5));screenshot.tap()
        XCTAssertTrue(app.staticTexts["exportComplete"].waitForExistence(timeout:20))
        let share=app.buttons["shareExport"];reveal(share,in:app);XCTAssertTrue(share.isEnabled)
        share.tap();XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:5))
        let close=app.buttons["header.closeButton"];if close.exists { close.tap() } else { app.swipeDown() }
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.otherElements["ActivityListView"])
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:5),.completed)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="complete-export";attachment.lifetime = .keepAlways;add(attachment)
    }
    @MainActor func testSimulatorCaptureAndComparisonFlow() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-library"];app.launch()
        app.buttons["rootCapture"].tap()
        XCTAssertTrue(app.buttons["simulateCapture"].waitForExistence(timeout:5));app.buttons["simulateCapture"].tap()
        let save=app.buttons["saveCapture"];XCTAssertTrue(save.waitForExistence(timeout:10));reveal(save,in:app);save.tap()
        let open=app.buttons["openCapturedAnalysis"];XCTAssertTrue(open.waitForExistence(timeout:15));reveal(open,in:app);open.tap()
        let fixture=app.buttons["importFixture"];reveal(fixture,in:app);fixture.tap()
        let readout=app.staticTexts["frameReadout"];XCTAssertTrue(readout.waitForExistence(timeout:15))
        let compare=app.staticTexts["双视频对比"].firstMatch;reveal(compare,in:app);compare.tap()
        XCTAssertTrue(app.buttons["leftAnchor"].waitForExistence(timeout:10));reveal(app.buttons["leftAnchor"],in:app);app.buttons["leftAnchor"].tap()
        app.buttons["rightAnchor"].tap()
        let play=app.buttons["comparisonPlay"];reveal(play,in:app);play.tap()
        XCTAssertTrue(app.staticTexts["comparisonReadout"].waitForExistence(timeout:5));play.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.segmentedControls["comparisonLayout"].waitForExistence(timeout:5))
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="comparison-landscape";attachment.lifetime = .keepAlways;add(attachment)
        XCUIDevice.shared.orientation = .portrait
    }
}

extension CoachInsightsUITests {
    @MainActor func testOptionalSystemPhotosPickerImportsLocalVideo() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-library"];app.launch()
        app.buttons["createSession"].tap()
        let name=app.textFields["sessionName"];name.tap();name.typeText("Photos import")
        app.buttons["confirmCreate"].tap();app.staticTexts["Photos import"].firstMatch.tap()
        let photos=app.buttons["importPhotos"];reveal(photos,in:app);photos.tap()
        let cancel=app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","取消","Cancel")).firstMatch
        _=cancel.waitForExistence(timeout:10)
        let image=app.images.matching(identifier:"PXGGridLayout-Info").firstMatch
        let cell=app.collectionViews.cells.firstMatch
        let item=image.waitForExistence(timeout:5) ? image:cell
        guard item.waitForExistence(timeout:5) else {
            if cancel.exists { cancel.tap() }
            throw XCTSkip("No local Photos fixture; seed the dedicated simulator with simctl addmedia")
        }
        let pickerShot=XCTAttachment(screenshot:app.screenshot());pickerShot.name="system-photos-picker";pickerShot.lifetime = .keepAlways;add(pickerShot)
        item.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        if app.buttons["添加"].exists { app.buttons["添加"].tap() }
        else if app.buttons["Add"].exists { app.buttons["Add"].tap() }
        let fullAccess=app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","允许完全访问","Allow Full Access")).firstMatch
        if fullAccess.waitForExistence(timeout:5) { fullAccess.tap() }
        else {
            let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
            let allow=system.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","允许完全访问","Allow Full Access")).firstMatch
            if allow.waitForExistence(timeout:2) { allow.tap() }
        }
        let readout=app.staticTexts["frameReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout:30),app.debugDescription)
        XCTAssertTrue(readout.label.contains("帧"))
    }
}
