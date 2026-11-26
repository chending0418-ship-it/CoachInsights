import SwiftUI

struct TrainingList: View {
  let kind: TrainingKind
  @EnvironmentObject private var store: TrainingStore
  @State private var creating = false
  private var noun: String {
    switch kind { case .team: "计划"; case .note: "笔记"; case .homework: "练习卡" }
  }
  private var documents: [NotebookDocument] {
    store.items.filter { $0.kind == kind }.map { item in
      let duration = "\(item.stages.reduce(0) { $0 + $1.minutes }) 分钟 · \(item.stages.count) 个环节"
      let lead = kind == .homework ? item.focus : item.body.components(separatedBy: .newlines).first ?? ""
      return NotebookDocument(id: item.id, title: item.title, audience: item.audience, date: item.date,
                              lead: lead.isEmpty ? item.summary : lead,
                              footer: kind == .team ? duration : "查看" + noun,
                              rowDetail: kind == .team ? duration : item.audience)
    }
  }
  var body: some View {
    DocumentLibrary(title: kind.tool.title, noun: noun, icon: kind == .team ? "person.2" : kind.tool.symbol,
                    documents: documents, issue: store.issue, createID: "newTraining", retry: store.reload,
                    create: { creating = true }) { id, embedded in TrainingDetail(id: id, embedded: embedded) }
      .navigationDestination(isPresented: $creating) { TrainingEditor(draft: TrainingMaterial(kind: kind), original: nil) }
  }
}

struct TrainingDetail: View {
  let id: UUID
  var embedded = false
  @EnvironmentObject private var store: TrainingStore
  @Environment(\.dismiss) private var dismiss
  @State private var editing: TrainingMaterial?
  @State private var deleting = false
  @State private var problem: String?
  var body: some View {
    Group {
      if let item = store.item(id) {
        if embedded {
          VStack(alignment: .leading, spacing: 10) { actions(item); TrainingSummary(item: item) }
        } else {
          DocumentReader(sections: TrainingSummary(item: item).sections) {
            TrainingSummary(item: item)
          } actions: { actions(item) }
          .notebookPageTitle(item.kind == .team ? "计划详情" : item.kind == .note ? "笔记详情" : "练习卡详情")
        }
      } else {
        ContentUnavailableView("记录已删除", systemImage: "folder")
      }
    }.background(Theme.paper)
      .notebookDestination(item: $editing) { TrainingEditor(draft: $0, original: $0) }
      .confirmationDialog("删除这份本机资料？", isPresented: $deleting, titleVisibility: .visible) {
        Button("删除", role: .destructive) {
          do {
            try store.remove(id)
            if !embedded { dismiss() }
          } catch { problem = error.localizedDescription }
        }
      }
      .alert(
        "未能删除", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
      ) {
        Button("好") {}
      } message: {
        Text(problem ?? "")
      }
  }
  @ViewBuilder private func actions(_ item: TrainingMaterial) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { buttons(item) }
      VStack(alignment: .leading, spacing: 8) { buttons(item) }
    }
  }
  @ViewBuilder private func buttons(_ item: TrainingMaterial) -> some View {
    if item.kind == .team {
      NavigationLink { PlanRunView(preferred: item.id) } label: { Label("按计划计时", systemImage: "timer") }
        .buttonStyle(DocumentButtonStyle(primary: true))
    }
    if item.kind != .team || !embedded {
    NavigationLink { ShareCardPreview(content: item.card) } label: {
      if item.kind == .team { Image(systemName: "square.and.arrow.up").accessibilityLabel("图片分享") }
      else { Label("图片分享", systemImage: "square.and.arrow.up") }
    }.buttonStyle(DocumentButtonStyle(primary: item.kind != .team))
    }
    Button { editing = item } label: { Label("编辑", systemImage: "pencil") }.buttonStyle(DocumentButtonStyle())
    if embedded {
      NavigationLink { TrainingDetail(id: id) } label: { Label("打开", systemImage: "arrow.up.right") }
        .buttonStyle(DocumentButtonStyle())
    } else {
      Button(role: .destructive) { deleting = true } label: { Image(systemName: "trash").accessibilityLabel("删除") }
        .buttonStyle(DocumentButtonStyle())
    }
  }

}

private struct TrainingEditor: View {
  @State private var showingPreview = false
  @State private var draft: TrainingMaterial
  private let initial: TrainingMaterial
  let original: TrainingMaterial?
  @State private var discard = false

  init(draft: TrainingMaterial, original: TrainingMaterial?) {
    _draft = State(initialValue: draft)
    self.original = original
    self.initial = draft
  }
  @EnvironmentObject private var store: TrainingStore
  @Environment(\.dismiss) private var dismiss
  @State private var problem: String?
  var body: some View {
    Group {
      DocumentEditorLayout(title: (original == nil ? "新建" : "编辑") + (draft.kind == .team ? "计划" : draft.kind == .note ? "笔记" : "练习卡"),
                           context: draft.kind.tool.title, navigationTitle: draft.kind == .team ? "编排训练环节" : draft.kind == .note ? "填写教练笔记" : "填写课后练习卡", canSave: draft.valid, saveID: "trainingSave", cancelID: "cancelTraining",
                           cancel: { if draft == initial { dismiss() } else { discard = true } }, save: {
        do { try store.save(draft, replacing: original); dismiss() }
        catch { problem = error.localizedDescription }
      }, showingPreview: $showingPreview) { fields } preview: { summary }
        .confirmationDialog("放弃未保存的修改？", isPresented: $discard, titleVisibility: .visible) {
          Button("放弃修改", role: .destructive) { dismiss() }
          Button("继续编辑", role: .cancel) { }
        }
        .alert(
          "未能保存", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
        ) {
          Button("好") {}
        } message: {
          Text(problem ?? "")
        }
    }
  }
  private var summary: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {

        Text("实时预览").font(.headline)
        TrainingSummary(item: draft)
      }.padding()
    }.frame(maxWidth: .infinity)
  }
  private var fields: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        NotebookInput(title: (draft.kind == .team ? "计划标题" : draft.kind == .note ? "笔记标题" : "练习名称") + " · 必填") { TextField("标题", text: $draft.title).accessibilityIdentifier("trainingTitle") }
        NotebookInput(title: draft.kind.audienceLabel) { TextField(draft.kind.audienceLabel, text: $draft.audience) }
        NotebookInput(title: draft.kind.bodyLabel) {
        TextField(draft.kind.bodyLabel, text: $draft.body, axis: .vertical).lineLimit(3...12)
          .accessibilityIdentifier("trainingBody")
      }
      if draft.kind == .team {
          VStack(alignment: .leading, spacing: 12) {
            Text("训练环节").font(.headline)
          ForEach($draft.stages) { $stage in
            VStack(alignment: .leading, spacing: 7) {
                let i = draft.stages.firstIndex { $0.id == stage.id } ?? 0
                HStack {
                  Text(String(format: "%02d", i + 1)).monospacedDigit().foregroundStyle(Theme.burgundy);
                  TextField("环节名称", text: $stage.name).accessibilityIdentifier("stageName")
                }
              Stepper("\(stage.minutes) 分钟", value: $stage.minutes, in: 1...240)
              TextField("安排与提示", text: $stage.instructions, axis: .vertical)
              HStack {
                Button("上移") { draft.stages.swapAt(i, i - 1) }.disabled(i == 0)
                Button("下移") { draft.stages.swapAt(i, i + 1) }.disabled(i + 1 >= draft.stages.count)
                Spacer()
                Button("移除", role: .destructive) { draft.stages.removeAll { $0.id == stage.id } }
              }.buttonStyle(.borderless)
              }.notebookPanel()
          }
          Button("添加环节", systemImage: "plus") { draft.stages.append(TrainingStage()) }
        }
      } else {
          NotebookInput(title: draft.kind == .note ? "教学重点" : "次数或时长 · 必填") {
          TextField(draft.kind == .note ? "教学重点" : "次数或时长", text: $draft.focus, axis: .vertical)
            .accessibilityIdentifier("trainingFocus")
        }
          NotebookInput(title: draft.kind == .note ? "下次跟进" : "注意事项") {
          TextField(draft.kind == .note ? "下次跟进" : "注意事项", text: $draft.followUp, axis: .vertical)
        }
      }
        NotebookColumns(minimumWidth: 300, leadingFraction: 0.48, spacing: 10) {
          NotebookInput(title: "训练日期") { DatePicker("训练日期", selection: $draft.date, displayedComponents: .date).labelsHidden() }
          NotebookInput(title: "教练署名") { TextField("教练署名", text: $draft.author) }
        }
        HStack {
                Button("取消编辑") { if draft == initial { dismiss() } else { discard = true } }
                    .buttonStyle(DocumentButtonStyle())
                Button { showingPreview = true } label: { Label("预览内容", systemImage: "eye") }
                    .buttonStyle(DocumentButtonStyle())
            }
          }.padding(20)
    }.scrollDismissesKeyboard(.interactively)
  }
}

struct TrainingSummary: View {
  let item: TrainingMaterial
  var sections: [String] {
    var headings: [String] = []
    if item.kind == .homework { headings.append("练习量") }
    if !item.body.isEmpty { headings.append(item.kind.bodyLabel) }
    if item.kind == .team { headings.append("训练环节") }
    if item.kind == .note && !item.focus.isEmpty { headings.append("教学重点") }
    if !item.followUp.isEmpty { headings.append(item.kind == .note ? "下次跟进" : "注意事项") }
    return headings
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(item.kind == .team ? "团训计划" : item.kind.tool.title, systemImage: item.kind.tool.symbol)
        .font(.caption.bold()).foregroundStyle(Theme.burgundy)
      Text(item.title.isEmpty ? "标题" : item.title).font(.title.bold())
      HStack {
        Text(item.date, style: .date); Text(item.audience)
      }.font(.subheadline).foregroundStyle(.secondary)
      if item.kind == .homework {
        HStack { Text("练习量"); Spacer(); Text(item.focus).bold() }
          .padding(12).background(Notebook.fieldGreen.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
          .foregroundStyle(Notebook.fieldGreen).id("练习量")
      }
      if !item.body.isEmpty {
        Divider(); Text(item.kind.bodyLabel).font(.headline).foregroundStyle(Theme.burgundy).id(item.kind.bodyLabel)
        if item.kind == .homework { NumberedInstructions(text: item.body) } else { Text(item.body) }
      }
      if item.kind == .team {
        Divider(); LabeledContent("训练环节", value: "\(item.stages.reduce(0) { $0 + $1.minutes }) 分钟").font(.headline).foregroundStyle(Theme.burgundy).id("训练环节")
        StageAgenda(stages: item.stages)
      }
      if item.kind == .note && !item.focus.isEmpty { Divider(); Text("教学重点").font(.headline).foregroundStyle(Theme.burgundy).id("教学重点"); Text(item.focus) }
      if !item.followUp.isEmpty { Divider(); Text(item.kind == .note ? "下次跟进" : "注意事项").font(.headline).foregroundStyle(Theme.burgundy).id(item.kind == .note ? "下次跟进" : "注意事项"); Text(item.followUp) }
      if !item.author.isEmpty { Divider(); HStack { Text("教练署名").foregroundStyle(.secondary); Text(item.author).bold() }.font(.subheadline) }
    }.frame(maxWidth: .infinity, alignment: .leading).notebookPanel()
  }
}

private struct StageAgenda: View {
  let stages: [TrainingStage]
  var current: Int? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
        let start = stages.prefix(index).reduce(0) { $0 + $1.minutes }
        HStack(alignment: .top, spacing: 10) {
          Text(String(index + 1)).font(.caption.bold()).monospacedDigit()
            .frame(width: 22, height: 22)
            .foregroundStyle(current == index ? Color.white : Notebook.fieldGreen)
            .background(current == index ? Theme.burgundy : Notebook.paper, in: Circle())
            .overlay { Circle().strokeBorder(current == index ? Theme.burgundy : Notebook.rule) }
          VStack(alignment: .leading, spacing: 4) {
            Text(stage.name).font(.subheadline.bold())
            if !stage.instructions.isEmpty { Text(stage.instructions).font(.caption).foregroundStyle(.secondary) }
          }
          Spacer(minLength: 4)
          Text("\(start)–\(start + stage.minutes)′").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
          .background(alignment: .topLeading) {
            if index < stages.count - 1 { Rectangle().fill(Notebook.rule).frame(width: 1).padding(.leading, 10).padding(.top, 22) }
          }
      }
    }
  }
}

struct PlanRunView: View {
  var preferred: UUID?
  @EnvironmentObject private var store: TrainingStore
  @State private var selected: UUID?
  @State private var replace = false
  @State private var ending = false
  @State private var problem: String?
  private var plans: [TrainingMaterial] { store.items.filter { $0.kind == .team } }
  private var plan: TrainingMaterial? { plans.first { $0.id == selected } ?? plans.first }
  private func act(_ action: () throws -> Void) {
    do { try action() } catch { problem = error.localizedDescription }
  }
  private func start() { if let plan { act { try store.begin(plan) } } }
  private var startButton: some View {
    Button(store.run?.finished == false ? "重新开始所选计划" : "开始计时") {
      if store.run?.finished == false { replace = true } else { start() }
    }.buttonStyle(NotebookActionStyle(prominent: true)).accessibilityIdentifier("startPlanTimer")
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let issue = store.issue {
          Text(issue)
          Button("重试读取") { store.reload() }
        }
        if let displayed = store.run.flatMap({ $0.finished ? nil : $0.plan }) ?? plan {
          NotebookHeading(title: displayed.title, detail: [displayed.audience, displayed.summary].filter { !$0.isEmpty }.joined(separator: " · "))
          Divider()
        }
        NotebookColumns {
          VStack(alignment: .leading) {
            if store.run == nil, let plan, let stage = plan.stages.first {
              Text("准备开始").font(.caption).foregroundStyle(Notebook.fieldGreen)
              Text(stage.name).font(.title.bold())
              Text(String(format: "%02d:00", stage.minutes)).font(.system(size: 56, weight: .semibold)).monospacedDigit()
              Text(stage.instructions)
              ProgressView(value: 0).tint(Notebook.fieldGreen)
              startButton
            }
            if let run = store.run {
          TimelineView(.periodic(from: .now, by: 1)) { clock in
            let left = run.remaining(at: clock.date)
            let stage = run.plan.stages[run.index]
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Label(run.finished ? "训练已结束" : run.deadline == nil ? "已暂停" : "计时中", systemImage: "timer")
                  .foregroundStyle(Theme.burgundy)
                Spacer(); Text("\(run.index + 1) / \(run.plan.stages.count)").monospacedDigit()
              }.font(.subheadline.weight(.semibold))
              ProgressView(value: Double(run.finished ? run.plan.stages.count : run.index), total: Double(run.plan.stages.count))
                .tint(Notebook.fieldGreen).accessibilityLabel("已完成环节")

              Text(
                run.finished ? "训练已结束" : stage.name
              ).font(.title2.bold())
              if !run.finished {
                Text(String(format: "%02d:%02d", left / 60, left % 60)).font(
                  .system(size: 62, weight: .semibold, design: .monospaced)
                ).monospacedDigit().accessibilityIdentifier("planRemaining")
                    ProgressView(value: 1 - min(1, Double(left) / Double(max(1, stage.minutes * 60))))
                      .tint(Theme.burgundy).accessibilityLabel("当前环节进度")
                if left == 0 { Text("本段时间到，请确认下一步。").foregroundStyle(Theme.burgundy) }
                if !stage.instructions.isEmpty { Text(stage.instructions) }
                HStack {
                  Button(run.deadline == nil ? "继续" : "暂停") {
                    act { try store.changeRun { $0.toggle(at: .now) } }
                  }.buttonStyle(NotebookActionStyle(prominent: true)).disabled(left == 0)
                  Button("延长 1 分钟") { act { try store.changeRun { $0.extend(at: .now) } } }.buttonStyle(NotebookActionStyle())
                }.buttonStyle(.bordered)
                if run.index + 1 < run.plan.stages.count {
                  Text("下一段 · " + run.plan.stages[run.index + 1].name).font(.caption)
                  Button("下一段") { act { try store.changeRun { $0.advance(at: .now) } } }
                    .buttonStyle(.borderedProminent)
                }
                Button("结束训练", role: .destructive) { ending = true }
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        }
          } .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Notebook.inset.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Notebook.rule) }
          VStack(alignment: .leading, spacing: 12) {
        if let plan {
          Picker("选择团训计划", selection: Binding(get: { plan.id }, set: { selected = $0 })) {
            ForEach(plans) { Text($0.title).tag($0.id) }
          }
              let ordered = store.run.flatMap { $0.finished ? nil : $0.plan } ?? plan
              NotebookHeading(title: "环节顺序", detail: ordered.summary)
              StageAgenda(stages: ordered.stages, current: store.run?.index)
              if store.run != nil { startButton }
        } else {
          Text("先编排训练环节，再按顺序计时。").foregroundStyle(.secondary)
          NavigationLink("前往团训计划") { TrainingList(kind: .team) }
        }
          }
        }
      }.padding().frame(maxWidth: 1100)
    }.frame(maxWidth: .infinity).background(Theme.paper).navigationTitle("按计划计时")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear { if selected == nil { selected = preferred ?? store.run?.plan.id } }
      .confirmationDialog("替换当前计时并重新开始？", isPresented: $replace, titleVisibility: .visible) {
        Button("重新开始", role: .destructive) { start() }
      }
      .confirmationDialog("结束这次训练？", isPresented: $ending, titleVisibility: .visible) {
        Button("结束训练", role: .destructive) {
          act {
            try store.changeRun {
              $0.finished = true
              $0.deadline = nil
              $0.seconds = 0
            }
          }
        }
      }
      .alert(
        "未能保存计时", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
      ) {
        Button("好") {}
      } message: {
        Text(problem ?? "")
      }
  }
}
