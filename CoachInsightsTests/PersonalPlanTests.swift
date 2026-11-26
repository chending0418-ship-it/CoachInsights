import XCTest
@testable import CoachInsights

@MainActor final class PersonalPlanTests: XCTestCase {
    func testSaveReopenEditAndRemoveKeepsRecordIdentity() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PersonalPlanStore(root: root)
        var draft = PersonalPlan()
        draft.title = "  打击练习  "
        draft.drills = "  热身\n挥棒两组  "
        try store.save(draft, replacing: nil)

        let reopened = PersonalPlanStore(root: root)
        let saved = try XCTUnwrap(reopened.plan(draft.id))
        XCTAssertEqual(saved.title, "打击练习")
        XCTAssertEqual(saved.drills, "热身\n挥棒两组")
        XCTAssertEqual(saved.record.createdAt, draft.createdAt)
        XCTAssertTrue(PocketRecordFilter(scene: .personal, tool: .personalPlan).includes(saved.record))

        draft.title = "打击进阶"
        try reopened.save(draft, replacing: saved)
        XCTAssertEqual(PersonalPlanStore(root: root).plan(draft.id)?.title, draft.title)
        XCTAssertThrowsError(try reopened.save(draft, replacing: saved))
        try reopened.remove(draft.id)
        XCTAssertThrowsError(try reopened.save(draft, replacing: saved))
        XCTAssertTrue(PersonalPlanStore(root: root).plans.isEmpty)
    }

    func testUnreadableArchiveStaysIntactAndCanBeRetried() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("personal-plans-v1.json")
        let futureVersion = Data(#"{"version":2,"plans":[]}"#.utf8)
        try futureVersion.write(to: file)
        let store = PersonalPlanStore(root: root)
        XCTAssertNotNil(store.readIssue)

        var draft = PersonalPlan()
        draft.title = "训练"
        draft.drills = "跑垒"
        XCTAssertThrowsError(try store.save(draft, replacing: nil))
        XCTAssertEqual(try Data(contentsOf: file), futureVersion)
        XCTAssertTrue(store.plans.isEmpty)

        try FileManager.default.removeItem(at: file)
        store.reload()
        XCTAssertNil(store.readIssue)
        try store.save(draft, replacing: nil)
        XCTAssertEqual(store.plans, [draft])
    }

    func testFailedWriteDoesNotPublishAndCanBeRetried() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PersonalPlanStore(root: root)
        var draft = PersonalPlan()
        draft.title = "传球"
        draft.drills = "  \n "
        XCTAssertThrowsError(try store.save(draft, replacing: nil))
        draft.drills = "两组短传"

        try Data().write(to: root)
        XCTAssertThrowsError(try store.save(draft, replacing: nil))
        XCTAssertTrue(store.plans.isEmpty)
        try FileManager.default.removeItem(at: root)
        try store.save(draft, replacing: nil)
        XCTAssertEqual(store.plans, [draft])
    }

    func testRealCardUsesUpdatedFieldsAndPaginatesLongContent() throws {
        var draft = PersonalPlan()
        draft.title = "守备练习"
        draft.athlete = "球员 A"
        draft.goal = "稳定脚步"
        draft.author = "教练 B"
        draft.drills = (1...65).map { "\($0). 练习正面接滚地球，再完成传球。" }.joined(separator: "\n")
        let card = draft.card
        XCTAssertEqual(card.title, draft.title)
        XCTAssertEqual(card.date, draft.date)
        XCTAssertEqual(card.author, draft.author)
        XCTAssertEqual(card.sections.map(\.body), [draft.athlete, draft.goal, draft.drills])
        XCTAssertFalse(card.isExample)
        XCTAssertGreaterThan(try ShareCardRenderer.render(card).count, 1)
        draft.drills = "热身后传球"
        XCTAssertEqual(try ShareCardRenderer.render(draft.card).count, 1)
    }
}
