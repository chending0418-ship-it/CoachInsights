import XCTest
@testable import CoachInsights

final class GeometryTests: XCTestCase {
    func testCoordinatesRoundTripAcrossCropRotationMirroringAndExportSizes() throws {
        for viewport in [CGSize(width: 390, height: 220), CGSize(width: 1024, height: 700),
                         CGSize(width: 1920, height: 1080)] {
            for rotation in 0..<4 {
                for mirror in [false, true] {
                    let geometry = VideoGeometry(imageSize: CGSize(width: 3840, height: 2160),
                        viewportSize: viewport, crop: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
                        quarterTurns: rotation, mirrored: mirror, zoom: 2.3, pan: CGPoint(x: 25, y: -12))
                    for point in [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.45, y: 0.5), CGPoint(x: 0.8, y: 0.8)] {
                        let screen = geometry.viewPoint(from: point)
                        let recovered = try XCTUnwrap(geometry.normalizedPoint(from: screen))
                        XCTAssertEqual(recovered.x, point.x, accuracy: 1e-8)
                        XCTAssertEqual(recovered.y, point.y, accuracy: 1e-8)
                    }
                }
            }
        }
        let bars = VideoGeometry(imageSize: CGSize(width: 1920, height: 1080),
                                 viewportSize: CGSize(width: 400, height: 400))
        XCTAssertNil(bars.normalizedPoint(from: .zero))
        XCTAssertEqual(bars.normalizedPoint(from: CGPoint(x: 200, y: 200)), CGPoint(x: 0.5, y: 0.5))
    }
    func testAngleUsesPixelAspectAndRejectsDegeneratePoints() {
        let size = CGSize(width: 200, height: 100)
        let angle = VideoGeometry.angle(a: CGPoint(x: 0.25, y: 0), vertex: CGPoint(x: 0, y: 0),
                                        b: CGPoint(x: 0.25, y: 0.5), imageSize: size)
        XCTAssertEqual(angle!, 45, accuracy: 0.000_01)
        XCTAssertNil(VideoGeometry.angle(a: .zero, vertex: .zero, b: CGPoint(x: 1, y: 1), imageSize: size))
    }
    func testComparisonIntersectionOffsetsAndFrameBoundaries() {
        let clock = ComparisonClock(leftAnchor: 2, rightAnchor: 1, leftRange: 0...5, rightRange: 0.5...3)
        XCTAssertEqual(clock.commonRange, -0.5...2)
        let before = clock.times(at: -10)!
        XCTAssertEqual(before.0, 1.5); XCTAssertEqual(before.1, 0.5)
        let end = clock.times(at: 20)!
        XCTAssertEqual(end.0, 4); XCTAssertEqual(end.1, 3)
        XCTAssertNil(ComparisonClock(leftAnchor: 0, rightAnchor: 0,
                                      leftRange: 0...1, rightRange: 2...3).commonRange)
    }
    func testLRUEvictionCostOverwriteAndOversizedValues() {
        var cache = LRUCache<Int, String>(costLimit: 10)
        cache.insert("a", for: 1, cost: 4); cache.insert("b", for: 2, cost: 4)
        XCTAssertEqual(cache.value(for: 1), "a")
        cache.insert("c", for: 3, cost: 4)
        XCTAssertNil(cache.value(for: 2))
        cache.insert("huge", for: 1, cost: 11)
        XCTAssertNil(cache.value(for: 1))
        XCTAssertLessThanOrEqual(cache.totalCost, 10)
        cache.removeAll(); XCTAssertEqual(cache.totalCost, 0)
    }
    func testVFRPresentationHoldsPreviousFrameAndFrameRangesAreExclusive() throws {
        let times=[0.0,0.1,0.6,0.7]
        let frames=times.enumerated().map { i,t in FrameSample(presentationTime:MediaTime(seconds:t),duration:MediaTime(seconds:i<3 ? times[i+1]-t:0.1)) }
        let map=try MediaTimeMap(frames:frames,segments:[TimelineSegment(sourceID:"vfr",sourceStart:MediaTime(seconds:0),sourceDuration:MediaTime(seconds:0.8),presentationStart:MediaTime(seconds:0),presentationDuration:MediaTime(seconds:0.8))],duration:MediaTime(seconds:0.8))
        XCTAssertEqual(map.nearestFrame(to:MediaTime(seconds:0.4)),2)
        XCTAssertEqual(map.presentingFrame(at:MediaTime(seconds:0.4)),1)
        XCTAssertEqual(map.presentingFrame(at:MediaTime(seconds:0.59)),1)
        XCTAssertEqual(map.presentingFrame(at:MediaTime(seconds:0.6)),2)
        let range=ClipRange(start:MediaTime(seconds:0.1),end:MediaTime(seconds:0.6))
        XCTAssertEqual(map.presentingFrame(at:MediaTime(seconds:1),in:range),1)
        let annotation=Annotation(videoID:UUID(),kind:"line",points:[.init(x:0,y:0),.init(x:1,y:1)],range:range)
        XCTAssertTrue(AnalysisRenderer.visible(annotation,at:0.1,tolerance:0.00001))
        XCTAssertFalse(AnalysisRenderer.visible(annotation,at:0.6,tolerance:0.00001))
    }

}
