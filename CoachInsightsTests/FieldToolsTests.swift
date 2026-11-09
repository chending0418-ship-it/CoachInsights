import XCTest
import Vision
@testable import CoachInsights

@MainActor final class FieldToolsTests: XCTestCase {
    private func temporary() -> URL { URL.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testBattingCategoriesUndoAndRejectCrossToolEvents() {
        var round = FieldLog(kind: .batting)
        round.append(.batting(.ground)); round.append(.batting(.line)); round.append(.batting(.fly)); round.append(.batting(.miss))
        round.append(.pitch(PitchMark(zone: .center))); round.append(.game(.out))
        XCTAssertEqual(round.events.count, 4)
        XCTAssertEqual(BattingContact.allCases.map(round.count), [1, 1, 1, 1])
        round.events.removeLast(); XCTAssertEqual(round.count(.miss), 0)
        round.events.removeAll(); XCTAssertEqual(round.events.count, 0)
    }

    func testPitchCorrectionKeepsTotalAndOutsIndependent() {
        var round = FieldLog(kind: .bullpen)
        round.append(.pitch(PitchMark(zone: .center))); round.append(.bullpenOut)
        round.append(.pitch(PitchMark(zone: .high)))
        XCTAssertEqual(round.pitches.count, 2); XCTAssertEqual(round.strikeCount, 1); XCTAssertEqual(round.outCount, 1)
        round.correctPitch(at: 0, zone: .low, isStrike: false)
        XCTAssertEqual(round.pitches.count, 2); XCTAssertEqual(round.strikeCount, 0)
        round.correctPitch(at: 2, isStrike: true)
        round.correctPitch(at: 1, zone: .center, isStrike: true)
        round.correctPitch(at: 40, zone: .center)
        XCTAssertEqual(round.strikeCount, 1); XCTAssertEqual(round.outCount, 1)
        XCTAssertEqual(round.pitches.map(\.zone), [.low, .high])
        round.events.removeLast(); XCTAssertEqual(round.pitches.count, 1); XCTAssertEqual(round.outCount, 1)
    }

    func testGameStrikeoutWalkThirdOutAndUndoAcrossBoundary() {
        var round = FieldLog(kind: .game)
        round.append(.game(.ball)); round.append(.game(.strike)); round.append(.game(.strike)); round.append(.game(.strike))
        XCTAssertEqual(round.gameCount.strikes, 0); XCTAssertEqual(round.gameCount.balls, 0); XCTAssertEqual(round.gameCount.outs, 1)
        for _ in 0..<4 { round.append(.game(.ball)) }
        XCTAssertEqual(round.gameCount.outs, 1); XCTAssertEqual(round.gameCount.balls, 0)
        XCTAssertTrue(round.gameCount.notice?.contains("四坏") == true)
        round.append(.game(.out)); round.append(.game(.out))
        XCTAssertEqual(round.gameCount.outs, 0); XCTAssertEqual(round.gameCount.sides, 1)
        round.events.removeLast()
        XCTAssertEqual(round.gameCount.outs, 2); XCTAssertEqual(round.gameCount.sides, 0)
        round.append(.game(.ball)); round.append(.game(.clearBatter))
        XCTAssertEqual(round.gameCount.outs, 2); XCTAssertEqual(round.gameCount.balls, 0)
    }

    func testPitchMapCoordinatesAndLegacyMarksRemainConsistent() throws {
        for zone in PitchZone.allCases { XCTAssertEqual(PitchZone.at(zone.point), zone) }
        let point = FieldPoint(x: 0.53, y: 0.51)
        let mark = PitchMark(point: point)
        XCTAssertEqual(mark.zone, .center); XCTAssertTrue(mark.isStrike); XCTAssertEqual(mark.point, point)
        let legacy = try JSONDecoder().decode(PitchMark.self, from: Data(#"{"zone":"center","isStrike":true}"#.utf8))
        XCTAssertNil(legacy.location); XCTAssertEqual(legacy.point, PitchZone.center.point)
        var log = FieldLog(kind: .bullpen); log.append(.pitch(mark)); log.append(.bullpenOut)
        let low = FieldPoint(x: 0.55, y: 0.88)
        log.correctPitch(at: 0, location: low)
        XCTAssertEqual(log.pitches.count, 1); XCTAssertEqual(log.pitches[0].zone, .low)
        XCTAssertTrue(log.pitches[0].isStrike, "Relocating the same pitch preserves its independent judgement")
        XCTAssertEqual(log.pitches[0].point, low); log.undo()
        XCTAssertEqual(log.pitches[0], mark)
    }

    func testUndoStopsAtRetainedOperationBoundary() {
        var log = FieldLog(kind: .batting)
        for _ in 0..<105 { log.append(.batting(.ground)) }
        for _ in 0..<100 { log.undo() }
        XCTAssertEqual(log.events.count, 5); XCTAssertTrue(log.undoHistory.isEmpty)
        log.undo(); XCTAssertEqual(log.events.count, 5)
    }

    func testAllKindsPersistDraftAndHistoryReopenContinueEndAndDelete() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = FieldToolsStore(root: root)
        var ids: [UUID] = []
        for kind in FieldLogKind.allCases {
            var log = try XCTUnwrap(store.log(kind: kind, id: nil)); log.name = "本轮\(kind.rawValue)"
            switch kind { case .batting: log.append(.batting(.fly)); case .bullpen: log.append(.pitch(PitchMark(zone: .center))); case .game: log.append(.game(.ball)) }
            XCTAssertTrue(store.update(log)); XCTAssertTrue(store.save(log)); ids.append(log.id)
        }
        let reopened = FieldToolsStore(root: root)
        XCTAssertNil(reopened.issue); XCTAssertEqual(reopened.state.records.count, 3)
        for kind in FieldLogKind.allCases {
            let draft = try XCTUnwrap(reopened.log(kind: kind, id: nil))
            XCTAssertEqual(draft.events.count, 1)
            let record = try XCTUnwrap(reopened.log(kind: kind, id: draft.id))
            XCTAssertEqual(record.events, draft.events)
            XCTAssertTrue(reopened.save(record, ending: true))
            XCTAssertTrue(try XCTUnwrap(reopened.log(kind: kind, id: record.id)).ended)
            XCTAssertNotEqual(reopened.log(kind: kind, id: nil)?.id, record.id)
        }
        var game = try XCTUnwrap(reopened.log(kind: .game, id: ids[2])); game.ended = false
        game.append(.game(.out)); XCTAssertTrue(reopened.update(game))
        XCTAssertEqual(FieldToolsStore(root: root).log(kind: .game, id: ids[2])?.events.count, 2)
        XCTAssertTrue(reopened.remove(ids[0]))
        XCTAssertEqual(Set(FieldToolsStore(root: root).state.records.map(\.id)), Set(ids.dropFirst()))
        let records = reopened.state.records.map(PocketRecord.init(fieldLog:))
        XCTAssertEqual(records.filter(PocketRecordFilter(scene: .team).includes).map(\.id), [ids[2]])
        XCTAssertEqual(records.filter(PocketRecordFilter(scene: .quick).includes).map(\.id), [ids[1]])
    }

    func testDeletingSavedDraftDoesNotResurrectAndDoesNotTouchLegacyFiles() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("quick-tools-v1.json"), bytes = Data("legacy store unchanged".utf8)
        try bytes.write(to: legacy)
        let store = FieldToolsStore(root: root)
        var log = try XCTUnwrap(store.log(kind: .game, id: nil)); log.append(.game(.strike))
        XCTAssertTrue(store.update(log)); XCTAssertTrue(store.save(log)); XCTAssertTrue(store.remove(log.id))
        let reopened = FieldToolsStore(root: root)
        XCTAssertTrue(reopened.state.records.isEmpty)
        XCTAssertNotEqual(reopened.log(kind: .game, id: nil)?.id, log.id)
        XCTAssertTrue(reopened.log(kind: .game, id: nil)?.events.isEmpty == true)
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
    }

    func testUnreadableAndFutureStoresCannotBeOverwrittenAndCanRetry() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("field-tools-v1.json")
        var future = FieldToolsState(); future.version = 2
        for bytes in [Data("broken".utf8), try JSONEncoder().encode(future)] {
            try bytes.write(to: file)
            let store = FieldToolsStore(root: root)
            XCTAssertNotNil(store.issue)
            var log = FieldLog(kind: .batting); log.append(.batting(.ground))
            XCTAssertFalse(store.save(log)); XCTAssertFalse(store.remove(log.id))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            try JSONEncoder().encode(FieldToolsState()).write(to: file); store.reload()
            XCTAssertNil(store.issue)
            var draft = try XCTUnwrap(store.log(kind: .batting, id: nil)); draft.append(.batting(.line))
            XCTAssertTrue(store.update(draft))
        }
    }

    func testFailedWriteDoesNotPublishOrClaimSuccessfulSave() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root)
        let store = FieldToolsStore(root: root)
        var log = try XCTUnwrap(store.log(kind: .game, id: nil)); log.append(.game(.strike))
        XCTAssertFalse(store.update(log)); XCTAssertFalse(store.save(log))
        XCTAssertTrue(store.state.records.isEmpty); XCTAssertEqual(store.log(kind: .game, id: nil)?.events.count, 0)
        XCTAssertNotNil(store.issue)
    }

    func testCorrectionAndResetUndoSurviveReopening() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = FieldToolsStore(root: root)
        var log = try XCTUnwrap(store.log(kind: .bullpen, id: nil))
        log.append(.pitch(PitchMark(zone: .center)))
        log.correctPitch(at: 0, zone: .high, isStrike: false)
        log.clear(); XCTAssertTrue(store.update(log))
        let reopened = FieldToolsStore(root: root)
        log = try XCTUnwrap(reopened.log(kind: .bullpen, id: nil)); log.undo()
        XCTAssertEqual(log.pitches, [PitchMark(zone: .high)])
        log.undo(); XCTAssertEqual(log.pitches, [PitchMark(zone: .center)])
        XCTAssertEqual(log.pitches.count, 1)
        log.undo(); XCTAssertTrue(log.events.isEmpty)
    }

    func testShareCardPaginationRendersLastContentAndWritesEveryPage() throws {
        var content = ShareCardContent.example(long: true)
        content.sections.append(.init(heading: "", body: "FINAL TRAINING END"))
        let images = try ShareCardRenderer.render(content)
        XCTAssertGreaterThan(images.count, 1); XCTAssertLessThanOrEqual(images.count, 20)
        XCTAssertTrue(images.allSatisfy { $0.size == ShareCardRenderer.size })
        let request = VNRecognizeTextRequest(); request.recognitionLanguages = ["en-US"]; request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: try XCTUnwrap(images.last?.cgImage)).perform([request])
        let lastText = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
        XCTAssertTrue(lastText.contains("FINAL TRAINING END"), lastText)
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let urls = try ShareCardRenderer.files(for: images, directory: root)
        XCTAssertEqual(urls.count, images.count)
        XCTAssertTrue(try urls.allSatisfy { try Data(contentsOf: $0).count > 10000 })
        let attachment = XCTAttachment(image: try XCTUnwrap(images.last)); attachment.name = "share-card-last-page"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testShareCardRegenerationAndOversizedFailure() throws {
        var content = ShareCardContent.example()
        let first = try XCTUnwrap(ShareCardRenderer.render(content).first?.pngData())
        content.title = "修改后的标题"
        let changed = try XCTUnwrap(ShareCardRenderer.render(content).first?.pngData())
        XCTAssertNotEqual(first, changed)
        content.sections = [.init(heading: "超长", body: String(repeating: "Long content ", count: 10000))]
        XCTAssertThrowsError(try ShareCardRenderer.render(content))
    }
}
