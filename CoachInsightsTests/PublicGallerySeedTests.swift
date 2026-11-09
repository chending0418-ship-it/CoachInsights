import XCTest
@testable import CoachInsights

/// Opt-in capture preparation. Public CC0 files are supplied only in the
/// simulator's Documents/PublicGallery folder; no private footage is read.
@MainActor final class PublicGallerySeedTests: XCTestCase {
    func testSeedPublicVideoGalleryWhenFilesAreProvided() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_WEBSITE_PREVIEWS"] == "1", "Opt-in website capture only")
        let directory = URL.documentsDirectory.appendingPathComponent("PublicGallery")
        let first = directory.appendingPathComponent("公开投球_动作观察.mov")
        let second = directory.appendingPathComponent("公开投球_同步示例.mov")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: first.path) && FileManager.default.fileExists(atPath: second.path),
                          "Opt-in website capture requires CC0 public video fixtures in Documents/PublicGallery")
        let repository = try LibraryRepository(root: URL.applicationSupportDirectory.appendingPathComponent("UITesting"))
        let titles = ["公开素材 · 手动动作观察", "公开素材 · 两个动作阶段"]
        for session in try repository.sessions() where titles.contains(session.name) { try await repository.delete(session) }
        let analysis = try repository.create(name: titles[0], sport: .pitching)
        let a = try await repository.importVideo(first, into: analysis)
        var snapshot = try analysis.snapshot()
        let range = try XCTUnwrap(snapshot.clips[a.id.uuidString])
        snapshot.playheads[a.id.uuidString] = MediaTime(seconds: 2.8)
        snapshot.playbackRates[a.id.uuidString] = 0.25
        var view = ViewSettings(); view.zoom = 1.6
        snapshot.views[a.id.uuidString] = view
        snapshot.poseSettings.visible = false
        snapshot.annotations = [
            Annotation(videoID: a.id, kind: "line", points: [.init(x: 0.35, y: 0.69), .init(x: 0.58, y: 0.69)], color: "#F9C74F", lineWidth: 3, range: range),
            Annotation(videoID: a.id, kind: "arrow", points: [.init(x: 0.58, y: 0.36), .init(x: 0.46, y: 0.47)], color: "#F9C74F", lineWidth: 3, range: range)
        ]
        snapshot.keyframes = [Keyframe(videoID: a.id, time: MediaTime(seconds: 2.8), name: "手动关键帧")]
        try repository.save(analysis, snapshot: snapshot)
        let comparison = try repository.create(name: titles[1], sport: .pitching)
        try repository.attach(a.id, into: comparison)
        let b = try await repository.importVideo(second, into: comparison)
        var pair = try comparison.snapshot()
        let leftClip = try XCTUnwrap(pair.clips[a.id.uuidString]), rightClip = try XCTUnwrap(pair.clips[b.id.uuidString])
        pair.annotations = []; pair.keyframes = []; pair.poseResults = []; pair.poseSettings.visible = false
        pair.comparison = ComparisonSetup(leftVideoID: a.id, rightVideoID: b.id, leftAnchor: MediaTime(seconds: 2.8),
            rightAnchor: MediaTime(seconds: 2.25), leftClip: leftClip, rightClip: rightClip,
            layout: "vertical", rate: 0.25, leftView: view, rightView: view)
        pair.playheads[a.id.uuidString] = MediaTime(seconds: 2.8); pair.playheads[b.id.uuidString] = MediaTime(seconds: 2.25)
        try repository.save(comparison, snapshot: pair)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(pair.poseResults.count, 0)
        XCTAssertEqual(try analysis.snapshot().annotations.count, 2)
    }
}
