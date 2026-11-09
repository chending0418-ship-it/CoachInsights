import XCTest
@testable import CoachInsights

@MainActor final class MediaLayoutTests: XCTestCase {
    private var root: URL!
    private var workspaces: [ComparisonWorkspace] = []

    override func setUpWithError() throws {
        root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        for workspace in workspaces { await workspace.shutdown() }
        workspaces = []
        if let root { try? FileManager.default.removeItem(at: root) }
    }
    private func pair() async throws -> (LibraryRepository, AnalysisSession, ComparisonWorkspace) {
        let repository = try LibraryRepository(root: root.appendingPathComponent("Library"))
        let session = try repository.create(name: "Layout regression", sport: .batting)
        // Different frame timings create genuinely different immutable assets.
        // Identical synthetic movies are correctly deduplicated by the repository.
        for (name, fps) in [("left", 30), ("right", 60)] {
            let url = root.appendingPathComponent(name + ".mov")
            try await FixtureFactory.video(at: url, times: (0..<fps).map { Double($0) / Double(fps) }, duration: 1)
            _ = try await repository.importVideo(url, into: session)
        }
        var snapshot = try session.snapshot()
        XCTAssertEqual(snapshot.videoIDs.count, 2, "Comparison fixture must contain two distinct assets")
        _ = try XCTUnwrap(snapshot.videoIDs.dropFirst().first)
        snapshot.annotations = [Annotation(videoID: snapshot.videoIDs[0], kind: "line", points: [.init(x: 0.2, y: 0.3), .init(x: 0.8, y: 0.6)], range: .init(start: MediaTime(seconds: 0), end: MediaTime(seconds: 1)))]
        try repository.save(session, snapshot: snapshot)
        let workspace = ComparisonWorkspace(session: session, repository: repository)
        workspaces.append(workspace); await workspace.load()
        _ = try XCTUnwrap(workspace.setup, "Comparison fixture failed to load: " + (workspace.issue ?? "no second asset"))
        try await wait { workspace.left.frameReady && workspace.right.frameReady }
        return (repository, session, workspace)
    }
    private func wait(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Frame did not become ready")
    }

    func testAutomaticComparisonLayoutUsesWindowShapeIncludingPortraitIPad() {
        XCTAssertEqual(ComparisonWorkspace.automaticLayout(width: 744, height: 1060), "vertical")
        XCTAssertEqual(ComparisonWorkspace.automaticLayout(width: 1024, height: 1300), "vertical")
        XCTAssertEqual(ComparisonWorkspace.automaticLayout(width: 1133, height: 680), "horizontal")
        XCTAssertEqual(ComparisonWorkspace.automaticLayout(width: 360, height: 700), "vertical")
        XCTAssertEqual(ComparisonWorkspace.automaticLayout(width: 800, height: 340), "horizontal")
    }

    func testAutomaticRotationPreservesFramePositionsAnnotationsAndSync() async throws {
        let (_, session, workspace) = try await pair()
        XCTAssertTrue(workspace.followsWindow)
        workspace.adaptLayout(width: 744, height: 1060)
        XCTAssertEqual(workspace.setup?.layout, "vertical")
        workspace.independentSeek(0.4, isLeft: true)
        workspace.independentSeek(0.6, isLeft: false)
        // Match the sliders' end-editing callbacks before requiring frameReady.
        workspace.left.endScrubbing(); workspace.right.endScrubbing()
        try await wait { workspace.left.frameReady && workspace.right.frameReady }
        let indices = [workspace.left.frameIndex, workspace.right.frameIndex]
        let time = workspace.time, setup = try XCTUnwrap(workspace.setup)
        let annotations = workspace.left.snapshot.annotations
        workspace.adaptLayout(width: 1133, height: 680)
        XCTAssertEqual(workspace.setup?.layout, "horizontal")
        XCTAssertEqual([workspace.left.frameIndex, workspace.right.frameIndex], indices)
        XCTAssertEqual(workspace.time, time)
        XCTAssertTrue(workspace.independent)
        XCTAssertEqual(workspace.setup?.leftAnchor, setup.leftAnchor)
        XCTAssertEqual(workspace.setup?.rightAnchor, setup.rightAnchor)
        XCTAssertEqual(workspace.left.snapshot.annotations, annotations)
        XCTAssertEqual(try session.snapshot().annotations, annotations)
        workspace.adaptLayout(width: 744, height: 1060)
        XCTAssertEqual(workspace.setup?.layout, "vertical")
        XCTAssertEqual([workspace.left.frameIndex, workspace.right.frameIndex], indices)
    }

    func testManualAndPreviouslySavedLayoutsArePreservedOnRotationAndReopen() async throws {
        let (repository, session, workspace) = try await pair()
        workspace.adaptLayout(width: 744, height: 1060)
        workspace.selectLayout("horizontal", width: 744, height: 1060)
        XCTAssertFalse(workspace.followsWindow)
        workspace.adaptLayout(width: 744, height: 1060)
        XCTAssertEqual(workspace.setup?.layout, "horizontal")
        let reopened = ComparisonWorkspace(session: session, repository: repository)
        workspaces.append(reopened); await reopened.load()
        XCTAssertFalse(reopened.followsWindow)
        reopened.adaptLayout(width: 744, height: 1060)
        XCTAssertEqual(reopened.setup?.layout, "horizontal")
        reopened.selectLayout("vertical", width: 1133, height: 680)
        reopened.adaptLayout(width: 1133, height: 680)
        XCTAssertEqual(reopened.setup?.layout, "vertical")
        let fixed = ComparisonWorkspace(session: session, repository: repository)
        workspaces.append(fixed); await fixed.load()
        fixed.adaptLayout(width: 1133, height: 680)
        XCTAssertEqual(fixed.setup?.layout, "vertical")
        fixed.selectLayout("automatic", width: 1133, height: 680)
        XCTAssertTrue(fixed.followsWindow); XCTAssertEqual(fixed.setup?.layout, "horizontal")
        fixed.adaptLayout(width: 744, height: 1060)
        XCTAssertEqual(fixed.setup?.layout, "vertical")
        fixed.selectLayout("invalid", width: 1133, height: 680)
        XCTAssertEqual(fixed.setup?.layout, "vertical")
    }
}
