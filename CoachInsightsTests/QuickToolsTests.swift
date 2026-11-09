import XCTest
import SwiftUI
@testable import CoachInsights

@MainActor final class QuickToolsTests: XCTestCase {
    func testStopwatchPauseResumeLapsAndSuspension() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var watch = PocketStopwatch()
        watch.start(at: start); watch.start(at: start.addingTimeInterval(1))
        watch.lap(at: start.addingTimeInterval(2.5))
        watch.pause(at: start.addingTimeInterval(4))
        XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(100)), 4, accuracy: 0.001)
        watch.start(at: start.addingTimeInterval(100))
        watch.lap(at: start.addingTimeInterval(103))
        XCTAssertEqual(watch.laps.map(\.duration), [2.5, 4.5])
        let restored = try JSONDecoder().decode(PocketStopwatch.self, from: JSONEncoder().encode(watch))
        XCTAssertEqual(restored.elapsed(at: start.addingTimeInterval(200)), 104, accuracy: 0.001)
        watch.reset(); XCTAssertFalse(watch.isRunning); XCTAssertTrue(watch.laps.isEmpty)
        XCTAssertEqual(PocketTimeFormat.stopwatch(63.53), "01:03.53")
    }

    func testCountdownDeadlinePauseResumeAndFinish() throws {
        let start = Date(timeIntervalSince1970: 2000)
        var timer = PocketCountdown(duration: 90)
        timer.start(at: start); let originalRun = timer.runID
        timer.pause(at: start.addingTimeInterval(20))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(100)), 70)
        timer.start(at: start.addingTimeInterval(100))
        XCTAssertNotEqual(timer.runID, originalRun)
        let restored = try JSONDecoder().decode(PocketCountdown.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(restored.remaining(at: start.addingTimeInterval(160)), 10)
        XCTAssertTrue(restored.isFinished(at: start.addingTimeInterval(171)))
        timer.finish(at: start.addingTimeInterval(171))
        XCTAssertFalse(timer.isRunning); XCTAssertEqual(timer.pausedRemaining, 0)
        timer.cancel(); XCTAssertTrue(timer.isConfigured); XCTAssertEqual(timer.duration, 90)
        XCTAssertEqual(PocketTimeFormat.countdown(3599.1), "1:00:00")
        XCTAssertEqual(PocketTimeFormat.countdown(-1), "00:00")
    }

    func testZeroCountdownCannotStartOrGoNegative() {
        var timer = PocketCountdown(duration: 0)
        timer.start(at: .now); XCTAssertNil(timer.deadline)
        timer.duration = 1; timer.start(at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(timer.remaining(at: Date(timeIntervalSince1970: 100)), 0)
    }

    func testBoardHistoryCoversDrawingAndPlayerMovement() {
        var board = TacticsDocument(), history = BoardHistory()
        let original = board
        XCTAssertEqual(Set(board.players.map(\.label)).count, 9)
        history.checkpoint(board)
        board.strokes.append(BoardStroke(points: [FieldPoint(x: 0.1, y: 0.1), FieldPoint(x: 0.8, y: 0.7)], ink: .yellow))
        let drawn = board
        history.checkpoint(board)
        board.players[0].position = FieldPoint(x: -1, y: 2)
        XCTAssertEqual(board.players[0].position, FieldPoint(x: 0, y: 1))
        history.undo(&board); XCTAssertEqual(board, drawn)
        history.undo(&board); XCTAssertEqual(board, original)
        history.redo(&board); XCTAssertEqual(board, drawn)
        history.checkpoint(board); XCTAssertTrue(history.redoStack.isEmpty)
    }

    func testQuickToolsPersistReopenFilterAndDeleteWithoutAffectingOtherRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = QuickToolsStore(root: root)
        store.updateStopwatch { $0.start(at: Date(timeIntervalSince1970: 5000)) }
        store.state.countdown = PocketCountdown(duration: 120)
        store.state.countdown.start(at: Date(timeIntervalSince1970: 5000))
        let board = TacticsDocument(), distance = DistanceRecord(meters: 18.44)
        store.saveBoard(board); store.saveDistance(distance); store.saveDistance(distance)
        let reopened = QuickToolsStore(root: root)
        XCTAssertNil(reopened.issue)
        XCTAssertTrue(reopened.state.stopwatch.isRunning)
        XCTAssertEqual(reopened.state.countdown.deadline, Date(timeIntervalSince1970: 5120))
        XCTAssertEqual(reopened.state.boards.map(\.id), [board.id])
        XCTAssertEqual(reopened.state.distances, [distance])
        let records = [PocketRecord(board: board), PocketRecord(distance: distance)]
        XCTAssertEqual(records.filter(PocketRecordFilter(scene: .team, tool: .tacticsBoard).includes).map(\.id), [board.id])
        reopened.removeRecord(board.id)
        let afterDeletion = QuickToolsStore(root: root)
        XCTAssertTrue(afterDeletion.state.boards.isEmpty)
        XCTAssertEqual(afterDeletion.state.distances, [distance])
    }

    func testUnreadableQuickStoreIsPreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("quick-tools-v1.json"), original = Data("broken store".utf8)
        try original.write(to: file)
        let store = QuickToolsStore(root: root)
        XCTAssertNotNil(store.issue)
        store.saveBoard(TacticsDocument()); store.retrySave()
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testDistanceUsesThreeDimensionalMetersAndRejectsInvalidEndpoints() {
        XCTAssertEqual(PocketDistanceMath.meters(from: .zero, to: SIMD3(3, 4, 12))!, 13, accuracy: 0.0001)
        XCTAssertNil(PocketDistanceMath.meters(from: .zero, to: .zero))
        XCTAssertNil(PocketDistanceMath.meters(from: .zero, to: SIMD3(.nan, 0, 1)))
    }

    func testWhiteboardImageRendersWithDrawingAndPlayers() throws {
        var document = TacticsDocument()
        document.players.append(FieldPlayer.runner(base: 1))
        document.strokes.append(BoardStroke(points: [FieldPoint(x: 0.5, y: 0.6), FieldPoint(x: 0.2, y: 0.2)], ink: .yellow))
        let renderer = ImageRenderer(content: BoardArtwork(document: document).frame(width: 1600, height: 1000))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size, CGSize(width: 1600, height: 1000))
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 10000)
    }
}
