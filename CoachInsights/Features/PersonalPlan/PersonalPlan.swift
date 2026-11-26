import SwiftUI

struct PersonalPlan: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var date: Date
    var title = ""
    var athlete = ""
    var goal = ""
    var drills = ""
    var author = ""

    init(now: Date = Date()) {
        id = UUID()
        createdAt = now
        date = Calendar.current.startOfDay(for: now)
    }

    var cleaned: Self {
        var plan = self
        plan.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.athlete = athlete.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.drills = drills.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return plan
    }

    var canSave: Bool {
        let plan = cleaned
        return !plan.title.isEmpty && !plan.drills.isEmpty
    }

    var card: ShareCardContent {
        let plan = cleaned
        let sections = [
            ShareCardContent.Section(heading: "球员", body: plan.athlete),
            ShareCardContent.Section(heading: "训练目标", body: plan.goal),
            ShareCardContent.Section(heading: "训练项目", body: plan.drills)
        ].filter { !$0.body.isEmpty }
        return ShareCardContent(title: plan.title, sections: sections, date: plan.date, author: plan.author)
    }

    var record: PocketRecord {
        PocketRecord(id: id, name: title, sport: nil, createdAt: createdAt,
                     tool: .personalPlan, summary: athlete.isEmpty ? nil : athlete)
    }
}

@MainActor final class PersonalPlanStore: ObservableObject {
    private struct Archive: Codable {
        var version = 1
        var plans: [PersonalPlan] = []
    }

    enum Failure: LocalizedError {
        case unreadable, changed, incomplete

        var errorDescription: String? {
            switch self {
            case .unreadable: return "请先重试读取个人训练计划，原文件已保留。"
            case .changed: return "计划已在其他页面修改或删除。请重新打开最新记录。"
            case .incomplete: return "请填写计划标题与训练项目。"
            }
        }
    }

    @Published private(set) var plans: [PersonalPlan] = []
    @Published private(set) var readIssue: String?
    private let file: URL

    init(root: URL? = nil) {
        var directory = root ?? URL.applicationSupportDirectory.appendingPathComponent("CoachInsights")
        #if DEBUG
        if root == nil && ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            directory = URL.applicationSupportDirectory.appendingPathComponent("UITestingPersonalPlans")
            if ProcessInfo.processInfo.arguments.contains("--reset-library") {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        #endif
        file = directory.appendingPathComponent("personal-plans-v1.json")
        reload()
    }

    func reload() {
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
            guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            plans = archive.plans
            readIssue = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            plans = []
            readIssue = nil
        } catch {
            readIssue = "无法读取个人训练计划。原文件已保留。"
        }
    }

    func plan(_ id: UUID) -> PersonalPlan? {
        plans.first { $0.id == id }
    }

    func save(_ draft: PersonalPlan, replacing original: PersonalPlan?) throws {
        guard draft.canSave else { throw Failure.incomplete }
        guard plan(draft.id) == original else { throw Failure.changed }
        var next = plans
        if let index = next.firstIndex(where: { $0.id == draft.id }) {
            next[index] = draft.cleaned
        } else {
            next.insert(draft.cleaned, at: 0)
        }
        try commit(next)
    }

    func remove(_ id: UUID) throws {
        guard plan(id) != nil else { return }
        try commit(plans.filter { $0.id != id })
    }

    private func commit(_ next: [PersonalPlan]) throws {
        guard readIssue == nil else { throw Failure.unreadable }
        var directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(Archive(plans: next)).write(to: file, options: .atomic)
        plans = next
    }
}
