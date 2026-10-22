import AVFoundation
import XCTest
@testable import CoachInsights

final class MediaTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func fixture(fps: Int = 30, times: [Double]? = nil,
                         transform: CGAffineTransform = .identity) async throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".mov")
        try await FixtureFactory.video(at: url, times: times ?? (0..<fps).map { Double($0) / Double(fps) },
                                       duration: 1, transform: transform)
        return url
    }
    func testFrameRatesVFRAndOrientation() async throws {
        for fps in [30, 60, 120, 240] {
            let url = try await fixture(fps: fps)
            let value = try await MediaInspector().inspect(url: url)
            XCTAssertEqual(value.timeline.frames.count, fps)
            for (index, frame) in value.timeline.frames.enumerated() {
                XCTAssertEqual(frame.presentationTime.seconds, Double(index) / Double(fps), accuracy: 0.000_01)
                XCTAssertEqual(value.timeline.steppedIndex(from: index, by: 1),
                               min(fps - 1, index + 1))
            }
        }
        let times = [0.0, 0.025, 0.065, 0.13, 0.14, 0.32, 0.8, 0.91]
        let url = try await fixture(times: times,
            transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0))
        let value = try await MediaInspector().inspect(url: url)
        XCTAssertEqual(value.displayWidth, 180, accuracy: 0.01)
        XCTAssertEqual(value.displayHeight, 320, accuracy: 0.01)
        XCTAssertEqual(value.timeline.frames.count, times.count)
        for (frame, time) in zip(value.timeline.frames, times) {
            XCTAssertEqual(frame.presentationTime.seconds, time, accuracy: 0.000_01)
        }
        XCTAssertEqual(value.timeline.nearestFrame(to: MediaTime(seconds: 0.3)), 5)
        var index = 1
        for _ in 0..<4 { index = value.timeline.steppedIndex(from: index, by: 1) }
        for _ in 0..<4 { index = value.timeline.steppedIndex(from: index, by: -1) }
        XCTAssertEqual(index, 1)
    }
    func testSlowMotionPreservesSourceFramesAndMapping() async throws {
        let url = try await fixture(fps: 120)
        let original = AVURLAsset(url: url)
        let source = try await original.loadTracks(withMediaType: .video)[0]
        let composition = AVMutableComposition()
        let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: MediaTime(seconds: 1).cmTime),
                                  of: source, at: .zero)
        track.scaleTimeRange(CMTimeRange(start: MediaTime(seconds: 0.25).cmTime,
                                        duration: MediaTime(seconds: 0.5).cmTime),
                             toDuration: MediaTime(seconds: 2).cmTime)
        let metadata = try await MediaInspector().inspect(asset: composition)
        XCTAssertEqual(metadata.timeline.frames.count, 120)
        XCTAssertEqual(metadata.timeline.duration.seconds, 2.5, accuracy: 0.000_01)
        let mapped = metadata.timeline.sourcePosition(at: MediaTime(seconds: 1.25))!
        XCTAssertEqual(mapped.seconds, 0.5, accuracy: 0.000_01)
        let inverse = metadata.timeline.presentationTimes(sourceID: mapped.sourceID, sourceTime: MediaTime(seconds: 0.5))
        XCTAssertTrue(inverse.contains { abs($0.seconds - 1.25) < 0.000_01 })
        let selected = try await PhotoVideoSource().select(original: original, current: composition)
        XCTAssertTrue(selected.preservesPhotoTiming)
        // A rendered low-fps current version must never silently replace the 120-frame source.
        let rendered = AVURLAsset(url: try await fixture(fps: 30))
        let fallback = try await PhotoVideoSource().select(original: original, current: rendered)
        XCTAssertFalse(fallback.preservesPhotoTiming)
        XCTAssertNotNil(fallback.notice)
        let fallbackMetadata = try await MediaInspector().inspect(asset: fallback.analysisAsset)
        XCTAssertEqual(fallbackMetadata.timeline.frames.count, 120)
    }
    func testExactFramesCachesAndCorruptThumbnailRecovery() async throws {
        let url = try await fixture()
        let asset = AVURLAsset(url: url)
        let metadata = try await MediaInspector().inspect(asset: asset)
        let provider = FrameProvider(asset: asset, metadata: metadata, maximumDimension: 320, costLimit: 500_000)
        for index in [0, 1, 17, 29, 17, 0] {
            let frame = try await provider.frame(at: index)
            XCTAssertEqual(frame.index, index)
            XCTAssertEqual(frame.actualTime.seconds, frame.requestedTime.seconds, accuracy: 0.000_01)
        }
        let bytes = await provider.cachedByteCount
        XCTAssertLessThanOrEqual(bytes, 500_000)
        await provider.prefetch(around: Int.min, radius: 0)
        await provider.prefetch(around: Int.max, radius: -1)
        await MainActor.run { NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil) }
        try await Task.sleep(for: .milliseconds(50))
        let released = await provider.cachedByteCount
        XCTAssertEqual(released, 0)
        await provider.clear()
        let empty = await provider.cachedByteCount
        XCTAssertEqual(empty, 0)
        let cache = directory.appendingPathComponent("thumbs")
        let store = try ThumbnailStore(directory: cache, byteLimit: 10_000)
        let hash = String(repeating: "a", count: 64)
        let corrupt = cache.appendingPathComponent("v1-\(hash)-0.jpg")
        try Data("broken".utf8).write(to: corrupt)
        let thumbnail = try await store.image(contentHash: hash, frame: 0, provider: provider)
        XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height), 240)
        XCTAssertNotNil(UIImage(contentsOfFile: corrupt.path))
        try await store.clear()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
        try FileManager.default.removeItem(at:cache)
        _=try await store.image(contentHash:hash,frame:0,provider:provider)
        XCTAssertNotNil(UIImage(contentsOfFile:corrupt.path),"A purged cache directory must be recreated without reopening the editor")
    }
    @MainActor func testLatestRequestCannotBeOverwrittenAndExactSeek() async throws {
        let runner = LatestTaskRunner<Int>()
        var values: [Int] = []
        runner.submit(operation: {
            // Deliberately ignores cancellation like a decoder finishing already queued work.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { continuation.resume(returning: 1) }
            }
        }, result: { if case .success(let value) = $0 { values.append(value) } })
        await Task.yield()
        runner.submit(operation: { 2 }, result: { if case .success(let value) = $0 { values.append(value) } })
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(values, [2])
        let url = try await fixture()
        let asset = AVURLAsset(url: url)
        let metadata = try await MediaInspector().inspect(asset: asset)
        let playback = PlaybackCoordinator(asset: asset, timeline: metadata.timeline)
        for index in [0, 17, 29, 0] {
            let success = await playback.seek(frame: index)
            XCTAssertTrue(success)
            XCTAssertEqual(playback.player.currentTime().seconds,
                           metadata.timeline.frames[index].presentationTime.seconds, accuracy: 0.000_01)
        }
    }
    @MainActor func testSimulatorMediaProbe() async throws {
        let url = try await fixture(fps: 60)
        let (report, _) = try await MediaProbe.run(url: url)
        XCTAssertEqual(report.frames, 60)
        XCTAssertLessThan(report.exactFrameErrorsMS.max() ?? 999, 0.1)
        XCTAssertLessThan(report.dualMaximumDriftMS, 1000.0 / 60)
        XCTAssertGreaterThan(report.dualElapsedSeconds, 0.1)
        XCTAssertGreaterThan(report.residentMemoryBytes, 0)
        XCTAssertLessThan(report.residentMemoryBytes, 1024 * 1024 * 1024)
        XCTAssertLessThan(report.cacheBytes, 64 * 1024 * 1024 + 1)
        XCTAssertLessThan(report.frameLatencyMS.max() ?? 9999, 2500)
        assertVisionCapability(report)
    }
    @MainActor func testLocalRegressionVideoWhenAvailable() async throws {
        guard let url = Bundle(for: Self.self).url(forResource: "Regression", withExtension: "mov") else {
            throw XCTSkip("Private regression video is optional; synthetic fixtures always run.")
        }
        let (report, _) = try await MediaProbe.run(url: url)
        XCTAssertEqual(report.frames, 78)
        XCTAssertEqual(report.displayWidth, 3840)
        XCTAssertLessThan(report.exactFrameErrorsMS.max() ?? 999, 0.1)
        XCTAssertLessThan(report.dualMaximumDriftMS, 34)
        XCTAssertGreaterThan(report.dualElapsedSeconds, 0.1)
        XCTAssertLessThan(report.residentMemoryBytes, 1024 * 1024 * 1024)
        assertVisionCapability(report)
        if report.visionStatus == "available" { XCTAssertTrue(report.visionVisibleJoints.contains { $0 > 0 }) }
        let data = try JSONEncoder().encode(report)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "private-regression-probe"; attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func assertVisionCapability(_ report: ProbeReport) {
        if report.visionStatus == "runtimeUnavailable" {
            XCTAssertTrue(report.visionFailure?.contains("com.apple.Vision 9:") == true)
            XCTAssertTrue(report.visionMS.isEmpty)
            XCTAssertTrue(report.visionVisibleJoints.isEmpty)
        } else {
            XCTAssertEqual(report.visionStatus, "available")
            XCTAssertEqual(report.visionMS.count, 5)
        }
    }
}
