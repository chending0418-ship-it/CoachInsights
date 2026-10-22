#if !DEBUG
import XCTest
import AVFoundation
@testable import CoachInsights

/// Real-footage coverage for the optimized host, without Debug fixture helpers.
@MainActor final class ReleasePoseTests: XCTestCase {
    func testOfflinePoseWithStaticSDKInRelease() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Regression", withExtension: "mov"),
                                "Prepare the ignored Regression.mov fixture before this focused test")
        let metadata = try await MediaInspector().inspect(url: url)
        var settings = PoseSettings()
        settings.engine = MediaPipePoseEngine.identity
        let result = try await PoseAnalysis.analyze(
            provider: FrameProvider(asset: AVURLAsset(url: url), metadata: metadata, maximumDimension: 1280),
            metadata: metadata, videoID: UUID(), hash: "release-static-sdk-regression",
            settings: settings,
            range: .init(start: MediaTime(seconds: 0), end: metadata.timeline.duration)
        ) { _ in }
        XCTAssertEqual(result.frames.count, 78)
        XCTAssertGreaterThan(result.frames.filter { !$0.joints.isEmpty }.count, 0,
                             "The actual offline model must detect the person without embedded SDK wrappers")
    }
}
#endif
