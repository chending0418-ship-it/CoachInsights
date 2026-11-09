import XCTest
import UIKit

/// Manual website capture only: these cases require PublicGallerySeedTests.
/// The captured content is a CC0 public video with real manual App overlays.
final class PublicGalleryUITests: XCTestCase {
    @MainActor private func launchAndOpen(_ title: String) throws -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["recordsTab"].waitForExistence(timeout: 10)); app.buttons["recordsTab"].tap()
        let record = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "record_", title)).firstMatch
        try XCTSkipUnless(record.waitForExistence(timeout: 5), "Run the opt-in CC0 PublicGallerySeedTests before taking website screenshots")
        record.tap(); return app
    }
    @MainActor private func wait(_ predicate: String, on element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: timeout), .completed)
    }
    @MainActor private func shot(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testCapturePhoneLandscapeManualAnnotations() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_WEBSITE_PREVIEWS"] == "1", "Opt-in website capture only")
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone website screenshot")
        let app = try launchAndOpen("公开素材 · 手动动作观察")
        XCTAssertTrue(app.staticTexts["frameReadout"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        wait("label CONTAINS '退出全屏'", on: app.buttons["analysisFullscreen"])
        let canvas = app.otherElements["analysisCanvas"]
        XCTAssertGreaterThan(canvas.frame.width, canvas.frame.height)
        XCTAssertTrue(app.buttons["drawingTools"].isHittable)
        XCTAssertFalse(app.buttons["runPose"].exists)
        app.buttons["nextFrame"].tap(); app.buttons["previousFrame"].tap()
        wait("label CONTAINS '2.800'", on: app.staticTexts["frameReadout"])
        shot("website-phone-landscape-manual-analysis")
    }
    @MainActor func testCaptureIPadPortraitTwoPhases() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_WEBSITE_PREVIEWS"] == "1", "Opt-in website capture only")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad website screenshot")
        let app = try launchAndOpen("公开素材 · 两个动作阶段")
        XCTAssertTrue(app.buttons["comparisonPlay"].waitForExistence(timeout: 15))
        let a = app.descendants(matching: .any).matching(identifier: "comparisonSideA").firstMatch
        let b = app.descendants(matching: .any).matching(identifier: "comparisonSideB").firstMatch
        let layout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in b.frame.minY > a.frame.minY + 20 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [layout], timeout: 10), .completed)
        XCTAssertTrue(app.segmentedControls["comparisonLayout"].buttons["上下"].isSelected)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "studioSidebar").firstMatch.exists)
        app.buttons["rightAnchor"].tap()
        shot("website-ipad-portrait-comparison")
    }
}
