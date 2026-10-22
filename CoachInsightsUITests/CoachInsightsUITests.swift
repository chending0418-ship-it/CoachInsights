import XCTest
import UIKit

final class CoachInsightsUITests:XCTestCase {
    @MainActor func launch(_ extra:[String]=[])->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-library"]+extra;app.launch()
        XCTAssertTrue(app.buttons["createSession"].waitForExistence(timeout:10));return app
    }
    @MainActor func create(_ app:XCUIApplication,_ name:String) {
        app.buttons["createSession"].tap();let field=app.textFields["sessionName"]
        XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();field.typeText(name);app.buttons["confirmCreate"].tap()
        let record=app.staticTexts[name].firstMatch;XCTAssertTrue(record.waitForExistence(timeout:5));record.tap()
    }
    @MainActor func fixture(_ app:XCUIApplication) {
        if !app.buttons.matching(identifier:"importFixture").firstMatch.isHittable { app.buttons["videoOptions"].tap();app.buttons["添加素材"].tap() }
        let button=app.buttons.matching(identifier:"importFixture").firstMatch;XCTAssertTrue(button.waitForExistence(timeout:5));button.tap()
        XCTAssertTrue(app.staticTexts["frameReadout"].waitForExistence(timeout:20))
    }
    @MainActor func waitLabel(_ element:XCUIElement,_ text:String,timeout:Double=10) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@",text),object:element)],timeout:timeout),.completed,element.label)
    }
    @MainActor func shot(_ app:XCUIApplication,_ name:String) {
        let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
    @MainActor func openRecord(_ app:XCUIApplication,_ name:String) {
        let mode=app.segmentedControls["libraryBrowseMode"]
        if mode.exists { mode.buttons["分析记录"].tap() }
        let record=app.staticTexts[name].firstMatch
        if !record.isHittable { app.swipeUp() }
        XCTAssertTrue(record.waitForExistence(timeout:10));record.tap()
    }
    @MainActor func testLibraryLifecycleNavigationAndRotation() {
        let app=launch();create(app,"Simulator batting")
        app.buttons["moreActions"].tap();app.buttons["renameSession"].tap()
        let field=app.alerts.textFields.firstMatch;field.tap();field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:40));field.typeText("Saved analysis");app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["Saved analysis"].waitForExistence(timeout:5))
        app.buttons["双视频对比"].tap();XCTAssertTrue(app.buttons["cancelVideoPicker"].waitForExistence(timeout:5));app.buttons["cancelVideoPicker"].tap()
        XCTAssertTrue(app.buttons["moreActions"].waitForExistence(timeout:5))
        app.buttons["moreActions"].tap();app.buttons["导出分析"].tap();XCTAssertTrue(app.staticTexts["分享动作里的发现"].waitForExistence(timeout:5))
        app.navigationBars.buttons.element(boundBy:0).tap()
        fixture(app);XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["playPause"].isHittable);XCTAssertTrue(app.buttons["nextFrame"].isHittable);shot(app,"v101-landscape-player")
        XCUIDevice.shared.orientation = .portrait;app.buttons["closeVideo"].tap()
        shot(app,"v101-video-library")
        app.terminate();app.launchArguments=["--ui-testing"];app.launch();openRecord(app,"Saved analysis")
        app.buttons["moreActions"].tap();app.buttons["deleteSession"].tap();app.alerts.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["从一份分析开始"].waitForExistence(timeout:10))
    }
    @MainActor func testFullEditorWorkflowAndFreePose() {
        let app=launch();create(app,"Full workflow");fixture(app)
        let readout=app.staticTexts["frameReadout"]
        app.buttons["nextFrame"].tap();waitLabel(readout,"第 2 /")
        app.buttons["drawingTools"].tap();let line=app.buttons["tool_line"]
        XCTAssertTrue(line.waitForExistence(timeout:5));line.tap()
        let canvas=app.otherElements["analysisCanvas"]
        let a=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.4)),b=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.6))
        a.press(forDuration:0.1,thenDragTo:b)
        let count=app.staticTexts["annotationCount"];waitLabel(count,"1 个标注")
        app.buttons["undoAnnotation"].tap();waitLabel(count,"0 个标注");app.buttons["重做"].tap();waitLabel(count,"1 个标注")
        shot(app,"v101-drawing")
        app.buttons["drawingTools"].tap();app.buttons["addKeyframe"].tap()
        app.alerts.textFields.firstMatch.tap();app.alerts.textFields.firstMatch.typeText("Contact");app.alerts.buttons["保存"].tap();waitLabel(count,"1 个关键帧")
        app.buttons["poseTools"].tap();let limitations=app.staticTexts["poseLimitations"]
        XCTAssertTrue(limitations.waitForExistence(timeout:5));XCTAssertTrue(limitations.label.contains("辅助估算") && limitations.label.contains("高置信度也可能出错"))
        let run=app.buttons["runPose"];XCTAssertTrue(run.isHittable);run.tap()
        let status=app.descendants(matching:.any).matching(identifier:"poseStatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout:10));waitLabel(status,"分析完成",timeout:30)
        app.buttons["完成"].tap()
        let slider=app.sliders["frameSlider"];slider.adjust(toNormalizedSliderPosition:0.7);app.buttons["nextFrame"].tap()
        shot(app,"v101-scrub-after-analysis")
        app.buttons["quickScreenshot"].tap();let share=app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout:20));let close=app.buttons["header.closeButton"]
        if close.exists { close.tap() } else { app.swipeDown() }
        app.buttons["closeVideo"].tap();openRecord(app,"Full workflow");waitLabel(app.staticTexts["annotationCount"],"1 个标注")
        app.buttons["moreActions"].tap();app.buttons["导出分析"].tap()
        XCTAssertTrue(app.staticTexts["exportPoseLimitations"].waitForExistence(timeout:5));app.buttons["exportScreenshot"].tap();XCTAssertTrue(app.staticTexts["exportComplete"].waitForExistence(timeout:20))
        shot(app,"v101-export")
    }
    @MainActor func testComparisonPickerCancellationSyncAndRotation() {
        let app=launch();create(app,"Comparison");fixture(app)
        app.buttons["nextFrame"].tap();let original=app.staticTexts["frameReadout"].label
        app.buttons["openComparison"].tap();XCTAssertTrue(app.buttons["cancelVideoPicker"].waitForExistence(timeout:5));app.buttons["cancelVideoPicker"].tap()
        XCTAssertTrue(app.staticTexts["frameReadout"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["frameReadout"].label,original)
        fixture(app);waitLabel(app.staticTexts["frameReadout"],"240",timeout:15)
        app.buttons["openComparison"].tap();let video=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","chooseVideo_")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout:10));video.tap()
        let play=app.buttons["comparisonPlay"];XCTAssertTrue(play.waitForExistence(timeout:15));XCTAssertTrue(play.isHittable)
        app.sliders["leftSlider"].adjust(toNormalizedSliderPosition:0.2);app.buttons["leftAnchor"].tap()
        app.sliders["rightSlider"].adjust(toNormalizedSliderPosition:0.3);app.buttons["rightAnchor"].tap()
        play.tap();waitLabel(app.staticTexts["comparisonReadout"],"联动");play.tap()
        shot(app,"v101-comparison-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        app.segmentedControls["comparisonLayout"].buttons["左右"].tap();XCTAssertTrue(play.isHittable);shot(app,"v101-comparison-landscape")
        XCUIDevice.shared.orientation = .portrait
        app.navigationBars.buttons.element(boundBy:0).tap();XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout:5))
    }
    @MainActor func testIPadWindowViewportChanges() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad narrow-window scenario") }
        let app=launch(["--layout-probe"]);app.buttons["narrowViewport"].tap();create(app,"Resizable analysis");fixture(app)
        XCTAssertTrue(app.buttons["playPause"].isHittable);XCTAssertTrue(app.buttons["nextFrame"].isHittable);shot(app,"v101-ipad-360pt-player")
        app.buttons["drawingTools"].tap();XCTAssertTrue(app.buttons["playPause"].isHittable);shot(app,"v101-ipad-360pt-drawing")
        app.buttons["drawingTools"].tap();app.buttons["nextFrame"].tap()
        app.buttons["wideViewport"].tap()
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout:10));waitLabel(app.staticTexts["frameReadout"],"第 2 /");shot(app,"v101-ipad-wide-player")
        app.buttons["narrowViewport"].tap()
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout:10));waitLabel(app.staticTexts["frameReadout"],"第 2 /")
    }
    @MainActor func testSimulatorCaptureFlow() {
        let app=launch();app.buttons["rootCapture"].tap()
        XCTAssertTrue(app.buttons["simulateCapture"].waitForExistence(timeout:5));app.buttons["simulateCapture"].tap()
        let save=app.buttons["saveCapture"];XCTAssertTrue(save.waitForExistence(timeout:10));if !save.isHittable { app.swipeUp() };save.tap()
        let open=app.buttons["openCapturedAnalysis"];XCTAssertTrue(open.waitForExistence(timeout:15));if !open.isHittable { app.swipeUp() };open.tap()
        XCTAssertTrue(app.staticTexts["frameReadout"].waitForExistence(timeout:15));XCTAssertTrue(app.buttons["playPause"].isHittable)
    }
    @MainActor func testDebugProbeRunsInSimulator() {
        let app=launch();let open=app.buttons["openProbe"];XCTAssertTrue(open.waitForExistence(timeout:5));open.tap();app.buttons["runProbe"].tap()
        XCTAssertTrue(app.staticTexts["probeComplete"].waitForExistence(timeout:60));shot(app,"media-probe")
    }
    @MainActor func testRealFootagePoseOverlayFollowsScrubbing() throws {
        let app=launch(["--real-footage"]);create(app,"Real batting")
        if app.staticTexts["realFixtureUnavailable"].exists { throw XCTSkip("Optional local Regression.mov fixture is missing") }
        fixture(app);app.buttons["poseTools"].tap();app.buttons["runPose"].tap()
        let status=app.descendants(matching:.any).matching(identifier:"poseStatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout:10));waitLabel(status,"分析完成",timeout:60);app.buttons["完成"].tap()
        let slider=app.sliders["frameSlider"],canvas=app.otherElements["analysisCanvas"]
        let regex=try NSRegularExpression(pattern:"[0-9]+\\.[0-9]+")
        var visible=0
        for position in [0.2,0.4,0.6,0.8] {
            slider.adjust(toNormalizedSliderPosition:position)
            let value=(canvas.value as? String) ?? ""
            let values=regex.matches(in:value,range:NSRange(value.startIndex...,in:value)).compactMap { Range($0.range,in:value).flatMap{Double(value[$0])} }
            if values.count==2 { XCTAssertEqual(values[0],values[1],accuracy:0.001);visible+=1 }
        }
        XCTAssertGreaterThan(visible,0,"At least one inspected real frame must show its saved pose")
        shot(app,"v101-real-pose-scrub")
        let a=slider.coordinate(withNormalizedOffset:CGVector(dx:0.15,dy:0.5)),b=slider.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5))
        a.press(forDuration:0.1,thenDragTo:b)
        app.buttons["nextFrame"].tap();shot(app,"v101-real-pose-drag-settled")
        app.buttons["playPause"].tap();waitLabel(app.buttons["playPause"],"暂停")
        XCTAssertTrue(app.buttons["quickScreenshot"].isEnabled,"Screenshot must remain available during playback")
        app.buttons["quickScreenshot"].tap();XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:20))
        let close=app.buttons["header.closeButton"];if close.exists { close.tap() } else { app.swipeDown() }
        XCTAssertEqual(app.buttons["playPause"].label,"播放","Quick screenshot freezes the current source frame")
        app.buttons["playPause"].tap();waitLabel(app.buttons["playPause"],"暂停")
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout:10));waitLabel(app.buttons["playPause"],"播放")
        let readout=app.staticTexts["frameReadout"].label
        if let match=regex.firstMatch(in:readout,range:NSRange(readout.startIndex...,in:readout)),let range=Range(match.range,in:readout) {
            let wanted="视频 "+String(readout[range])+" 秒"
            let aligned=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value CONTAINS %@",wanted),object:canvas)
            XCTAssertEqual(XCTWaiter.wait(for:[aligned],timeout:10),.completed,(canvas.value as? String) ?? "")
        } else { XCTFail("Missing source time in readout") }
        app.buttons["nextFrame"].tap();shot(app,"v101-real-pose-after-background")
        slider.adjust(toNormalizedSliderPosition:0.2)
        let beforeHold=Int(app.staticTexts["frameReadout"].label.split(separator:" ")[1]) ?? 0
        app.buttons["nextFrame"].press(forDuration:0.9)
        let afterHold=Int(app.staticTexts["frameReadout"].label.split(separator:" ")[1]) ?? 0
        XCTAssertGreaterThanOrEqual(afterHold-beforeHold,2,"Holding must repeat frame stepping")
        let stopped=app.staticTexts["frameReadout"].label
        shot(app,"v101-frame-hold-released")
        XCTAssertEqual(app.staticTexts["frameReadout"].label,stopped,"Frame stepping must stop on release")
    }
    @MainActor func testOptionalImportFirstPhotosFlow() throws {
        let app=launch();app.buttons["rootPhotos"].tap()
        let cell=app.images.matching(identifier:"PXGGridLayout-Info").firstMatch
        guard cell.waitForExistence(timeout:10) else {
            throw XCTSkip("No local Photos video in this simulator")
        }
        cell.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        if app.buttons["添加"].exists { app.buttons["添加"].tap() } else if app.buttons["Add"].exists { app.buttons["Add"].tap() }
        let allow=app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","允许完全访问","Allow Full Access")).firstMatch
        if allow.waitForExistence(timeout:3) { allow.tap() }
        else {
            let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
            let button=system.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","允许完全访问","Allow Full Access")).firstMatch
            if button.waitForExistence(timeout:2) { button.tap() }
        }
        let confirm=app.buttons["confirmNewImport"];XCTAssertTrue(confirm.waitForExistence(timeout:15));confirm.tap()
        XCTAssertTrue(app.staticTexts["frameReadout"].waitForExistence(timeout:30));shot(app,"v101-import-first")
    }
}
