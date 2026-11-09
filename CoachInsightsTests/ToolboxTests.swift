import XCTest
@testable import CoachInsights

@MainActor final class ToolboxTests: XCTestCase {
    func testRecordProjectionRemainsReadableAfterDeletingItsSource() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository(root: root, inMemory: true)
        let session = try repository.create(name: "删除前的记录", sport: .batting)
        let record = PocketRecord(session: session)
        let id = session.id
        try await repository.delete(session)
        XCTAssertTrue(try repository.sessions().isEmpty)
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.name, "删除前的记录")
        XCTAssertEqual(record.tool, .videoAnalysis)
    }
    func testLegacySessionsRemainReadableAndFilterBySavedComparison() throws {
        let video = try AnalysisSession(name: "旧视频分析", sport: .batting)
        let bytes = video.snapshotData
        let first = UUID(), second = UUID()
        let range = ClipRange(start: MediaTime(seconds: 0), end: MediaTime(seconds: 1))
        var snapshot = SessionSnapshot()
        snapshot.videoIDs = [first, second]
        snapshot.comparison = ComparisonSetup(leftVideoID: first, rightVideoID: second,
            leftAnchor: range.start, rightAnchor: range.start, leftClip: range, rightClip: range)
        let comparison = try AnalysisSession(name: "旧动作对比", sport: .pitching, snapshot: snapshot)
        let records = [video, comparison].map(PocketRecord.init)

        let all = PocketRecordFilter()
        XCTAssertEqual(records.filter(all.includes).map(\.id), [video.id, comparison.id])
        let videos = PocketRecordFilter(scene: .personal, tool: .videoAnalysis)
        XCTAssertEqual(records.filter(videos.includes).map(\.id), [video.id])
        let comparisons = PocketRecordFilter(scene: .personal, tool: .motionComparison)
        XCTAssertEqual(records.filter(comparisons.includes).map(\.id), [comparison.id])
        XCTAssertEqual(video.snapshotData, bytes, "Browsing the new records entry must not rewrite existing snapshots")
    }

    func testMovedToolsKeepAvailabilityAndExistingBoardRecordsFollowTeamScene() {
        XCTAssertEqual(PocketScene.team.tools, [.gameCounter, .tacticsBoard, .teamPlan, .planTimer])
        XCTAssertEqual(Set(PocketScene.quick.tools), Set([.stopwatch, .countdown, .battingLog, .bullpenLog, .distance]))
        XCTAssertTrue(PocketTool.tacticsBoard.isAvailable)
        XCTAssertTrue(PocketTool.battingLog.isAvailable)
        XCTAssertTrue(PocketTool.bullpenLog.isAvailable)
        let record = PocketRecord(board: TacticsDocument())
        XCTAssertTrue(PocketRecordFilter(scene: .team, tool: .tacticsBoard).includes(record))
        XCTAssertFalse(PocketRecordFilter(scene: .quick).includes(record))
        var filter = PocketRecordFilter(scene: .team, tool: .tacticsBoard)
        filter.selectScene(.quick)
        XCTAssertNil(filter.tool)
    }

    func testSceneChangeCannotLeaveAnIncompatibleToolFilter() throws {
        var filter = PocketRecordFilter(scene: .personal, tool: .videoAnalysis)
        filter.selectScene(.team)
        XCTAssertNil(filter.tool)
        let record = PocketRecord(session: try AnalysisSession(name: "原有记录", sport: .batting))
        XCTAssertFalse(filter.includes(record))
        filter.selectScene(nil)
        XCTAssertTrue(filter.includes(record))
    }
}
