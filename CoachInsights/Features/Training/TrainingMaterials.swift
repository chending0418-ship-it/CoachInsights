import SwiftUI

enum TrainingKind: String, Codable, CaseIterable {
  case note, homework, team
  var tool: PocketTool {
    switch self {
    case .note: .coachNotes
    case .homework: .homeworkCard
    case .team: .teamPlan
    }
  }
  var audienceLabel: String { self == .team ? "训练组别" : self == .note ? "观察对象" : "练习者" }
  var bodyLabel: String { self == .team ? "本次重点" : self == .note ? "场上观察" : "练习方法" }
}

struct TrainingStage: Codable, Identifiable, Equatable {
  var id = UUID()
  var name = ""
  var minutes = 5
  var instructions = ""
}

struct TrainingMaterial: Identifiable, Codable, Equatable {
  var id = UUID()
  let kind: TrainingKind
  var date = Date()
  var updatedAt = Date()
  var title = "", audience = "", body = "", focus = "", followUp = "", author = ""
  var stages: [TrainingStage] = []

  init(kind: TrainingKind) {
    self.kind = kind
    if kind == .team { stages = [TrainingStage()] }
  }

  var valid: Bool {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    if kind == .team {
      return !stages.isEmpty
        && stages.allSatisfy {
          !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...240).contains($0.minutes)
        }
    }
    return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (kind != .homework || !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }
  var summary: String {
    if kind == .team { return "\(stages.count) 个环节 · \(stages.reduce(0) { $0 + $1.minutes }) 分钟" }
    return [audience, kind == .homework ? focus : body].filter { !$0.isEmpty }.joined(
      separator: " · ")
  }
  var record: PocketRecord {
    PocketRecord(
      id: id, name: title, sport: nil, createdAt: updatedAt, tool: kind.tool,
      summary: String(summary.prefix(120)))
  }
  var card: ShareCardContent {
    var sections = [
      ShareCardContent.Section(heading: kind.audienceLabel, body: audience),
      .init(heading: kind.bodyLabel, body: body),
    ]
    switch kind {
    case .note:
      sections += [.init(heading: "教学重点", body: focus), .init(heading: "下次跟进", body: followUp)]
    case .homework:
      sections += [.init(heading: "次数或时长", body: focus), .init(heading: "注意事项", body: followUp)]
    case .team:
      for (i, stage) in stages.enumerated() {
        sections.append(
          .init(
            heading: "\(i+1). \(stage.name)",
            body: ["\(stage.minutes) 分钟", stage.instructions].filter { !$0.isEmpty }.joined(
              separator: "\n")))
      }
    }
    return ShareCardContent(
      title: title, sections: sections.filter { !$0.body.isEmpty }, date: date, author: author)
  }
}

struct TrainingRun: Codable, Equatable {
  let plan: TrainingMaterial
  var index = 0
  var seconds: Int
  var deadline: Date?
  var finished = false
  init(plan: TrainingMaterial) {
    self.plan = plan
    seconds = (plan.stages.first?.minutes ?? 0) * 60
  }
  func remaining(at now: Date) -> Int {
    max(0, deadline.map { Int(ceil($0.timeIntervalSince(now))) } ?? seconds)
  }
  mutating func toggle(at now: Date) {
    let left = remaining(at: now)
    guard !finished, left > 0 else { return }
    seconds = left
    deadline = deadline == nil ? now.addingTimeInterval(Double(left)) : nil
  }
  mutating func extend(at now: Date) {
    guard !finished else { return }
    let running = deadline != nil && remaining(at: now) > 0
    seconds = remaining(at: now) + 60
    deadline = running ? now.addingTimeInterval(Double(seconds)) : nil
  }
  mutating func advance(at now: Date) {
    guard !finished else { return }
    guard index + 1 < plan.stages.count else {
      finished = true
      deadline = nil
      seconds = 0
      return
    }
    let wasPaused = deadline == nil
    index += 1
    seconds = plan.stages[index].minutes * 60
    deadline = wasPaused ? nil : now.addingTimeInterval(Double(seconds))
  }
}

@MainActor final class TrainingStore: ObservableObject {
  enum Failure: LocalizedError {
    case incomplete, changed
    var errorDescription: String? {
      switch self {
      case .incomplete: return "请填写标题和训练内容，并检查各环节时长。"
      case .changed: return "这份资料已被修改或删除，请重新打开最新记录。"
      }
    }
  }
  private struct Archive: Codable {
    var version = 1
    var items: [TrainingMaterial] = []
    var run: TrainingRun?
  }
  @Published private var archive = Archive()
  @Published private(set) var issue: String?
  let file: URL
  var items: [TrainingMaterial] { archive.items }
  var run: TrainingRun? { archive.run }

  init(root: URL? = nil) {
    var dir = root ?? URL.applicationSupportDirectory.appendingPathComponent("CoachInsights")
    #if DEBUG
      let args = ProcessInfo.processInfo.arguments
      if root == nil && args.contains("--ui-testing") {
        dir = URL.applicationSupportDirectory.appendingPathComponent("UITestingMaterials")
        if args.contains("--reset-library") { try? FileManager.default.removeItem(at: dir) }
      }
    #endif
    file = dir.appendingPathComponent("training-materials-v1.json")
    reload()
  }
  func reload() {
    do {
      let data = try Data(contentsOf: file)
      let next = try JSONDecoder().decode(Archive.self, from: data)
      guard next.version == 1, next.items.allSatisfy(\.valid),
        next.run.map({
          $0.plan.kind == .team && $0.plan.valid && $0.plan.stages.indices.contains($0.index)
        }) ?? true
      else { throw CocoaError(.fileReadCorruptFile) }
      archive = next
      issue = nil
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      archive = Archive()
      issue = nil
    } catch { issue = "训练资料无法读取。原文件已保留，请重试。" }
  }
  func item(_ id: UUID) -> TrainingMaterial? { items.first { $0.id == id } }
  func save(_ draft: TrainingMaterial, replacing original: TrainingMaterial?) throws {
    guard draft.valid else { throw Failure.incomplete }
    guard item(draft.id) == original else { throw Failure.changed }
    var copy = draft
    copy.updatedAt = Date()
    try commit {
      $0.items.removeAll { $0.id == copy.id }
      $0.items.insert(copy, at: 0)
    }
  }
  func remove(_ id: UUID) throws { try commit { $0.items.removeAll { $0.id == id } } }
  func begin(_ plan: TrainingMaterial, now: Date = Date()) throws {
    guard plan.kind == .team, plan.valid else { throw Failure.incomplete }
    var run = TrainingRun(plan: plan)
    run.toggle(at: now)
    try commit { $0.run = run }
  }
  func changeRun(_ update: (inout TrainingRun) -> Void) throws {
    guard var run else { return }
    update(&run)
    try commit { $0.run = run }
  }
  private func commit(_ change: (inout Archive) -> Void) throws {
    guard issue == nil else { throw CocoaError(.fileReadCorruptFile) }
    var next = archive
    change(&next)
    var dir = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var attrs = URLResourceValues()
    attrs.isExcludedFromBackup = true
    try dir.setResourceValues(attrs)
    try JSONEncoder().encode(next).write(to: file, options: .atomic)
    archive = next
  }
}
