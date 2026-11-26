import XCTest

@testable import CoachInsights

@MainActor final class TrainingMaterialsTests: XCTestCase {
  func testMaterialsShareReopenAndRemoveWithoutLosingRunningPlan() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = TrainingStore(root: directory)
    for kind in TrainingKind.allCases {
      var m = TrainingMaterial(kind: kind)
      XCTAssertFalse(m.valid)
      m.title = kind.tool.title
      m.audience = "U12"
      m.body = "训练观察"
      m.focus = "3 × 8"
      if kind == .team {
        m.stages = [TrainingStage(name: "热身", minutes: 1), TrainingStage(name: "传球", minutes: 2)]
      }
      try store.save(m, replacing: nil)
      let restored = TrainingStore(root: directory)
      let saved = try XCTUnwrap(restored.item(m.id))
      XCTAssertEqual(saved.card.title, m.title)
      XCTAssertTrue(saved.card.sections.contains { $0.body.contains("U12") })
      XCTAssertEqual(saved.record.tool, kind.tool)
      if kind == .team {
        let now = Date(timeIntervalSince1970: 10000)
        try store.begin(saved, now: now)
        var edited = saved
        edited.stages.reverse()
        try store.save(edited, replacing: saved)
        let later = now.addingTimeInterval(80)
        XCTAssertEqual(store.run?.index, 0)
        XCTAssertEqual(store.run?.remaining(at: later), 0)
        try store.changeRun { $0.extend(at: later) }
        try store.changeRun { $0.toggle(at: later) }
        try store.changeRun { $0.toggle(at: later.addingTimeInterval(2)) }
        XCTAssertEqual(store.run?.seconds, 58)
        try store.changeRun { $0.advance(at: later) }
        XCTAssertEqual(store.run?.plan.stages[1].name, "传球")
        XCTAssertEqual(store.run?.remaining(at: later), 120)
        try store.changeRun { $0.advance(at: later) }
        XCTAssertTrue(try XCTUnwrap(store.run).finished)
      }
      try store.remove(m.id)
      XCTAssertNil(TrainingStore(root: directory).item(m.id))
    }
    XCTAssertTrue(try XCTUnwrap(TrainingStore(root: directory).run).finished)
  }

  func testUnreadableArchiveIsPreserved() throws {
    let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = TrainingStore(root: dir)
    let invalid = Data("unknown".utf8)
    try invalid.write(to: store.file)
    store.reload()
    XCTAssertNotNil(store.issue)
    var note = TrainingMaterial(kind: .note)
    note.title = "标题"
    note.body = "观察"
    XCTAssertThrowsError(try store.save(note, replacing: nil))
    XCTAssertEqual(try Data(contentsOf: store.file), invalid)
  }
}
