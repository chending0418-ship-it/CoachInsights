import XCTest
@testable import CoachInsights

@MainActor final class BoardCompatibilityTests: XCTestCase {
    func testLegacyBoardWithoutArrowMetadataDecodesWithoutChangingCoordinates() throws {
        let id = UUID(), strokeID = UUID(), playerID = UUID()
        let json = """
        {"id":"\(id)","title":"旧战术","updatedAt":100,"strokes":[{"id":"\(strokeID)","ink":"yellow","points":[{"x":0.12,"y":0.34},{"x":0.78,"y":0.65}]}],"players":[{"id":"\(playerID)","label":"投","position":{"x":0.46,"y":0.62},"isRunner":false}]}
        """
        let board = try JSONDecoder().decode(TacticsDocument.self, from: Data(json.utf8))
        XCTAssertEqual(board.id, id); XCTAssertEqual(board.strokes[0].id, strokeID)
        XCTAssertNil(board.strokes[0].isArrow); XCTAssertEqual(board.strokes[0].ink, .yellow)
        XCTAssertEqual(board.strokes[0].points, [FieldPoint(x: 0.12, y: 0.34), FieldPoint(x: 0.78, y: 0.65)])
        XCTAssertEqual(board.players[0].position, FieldPoint(x: 0.46, y: 0.62))
        let roundTrip = try JSONDecoder().decode(TacticsDocument.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(board, roundTrip)
    }

    func testRouteAndLegacyDrawingSurviveSaveReopenAndUndo() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var board = TacticsDocument(), history = BoardHistory()
        board.strokes.append(BoardStroke(points: [FieldPoint(x: 0.2, y: 0.3), FieldPoint(x: 0.3, y: 0.4)], ink: .white))
        let original = board
        history.checkpoint(board)
        board.strokes.append(BoardStroke(points: [FieldPoint(x: 0.38, y: 0.46), FieldPoint(x: 0.48, y: 0.63)], ink: .burgundy, isArrow: true))
        let store = QuickToolsStore(root: root); store.saveBoard(board)
        let reopened = try XCTUnwrap(QuickToolsStore(root: root).state.boards.first)
        XCTAssertEqual(reopened.strokes, board.strokes)
        XCTAssertTrue(reopened.strokes[1].isArrow == true)
        XCTAssertNil(reopened.strokes[0].isArrow)
        history.undo(&board); XCTAssertEqual(board, original)
        history.redo(&board); XCTAssertEqual(board.strokes, reopened.strokes)
    }
}
