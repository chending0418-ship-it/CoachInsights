import SwiftUI

struct TrainingList: View {
  let kind: TrainingKind
  @EnvironmentObject private var store: TrainingStore
  @State private var creating = false
  @State private var selected: UUID?
  private var rows: [TrainingMaterial] { store.items.filter { $0.kind == kind } }
  private var current: TrainingMaterial? { rows.first { $0.id == selected } ?? rows.first }

  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 0) {
        listing(wide: geometry.size.width >= 680)
        if geometry.size.width >= 680, let item = current {
          Divider()
          TrainingDetail(id: item.id, embedded: true).id(item.id).frame(maxWidth: .infinity)
        }
      }
    }.background(Theme.paper).navigationTitle(kind.tool.title)
      .fullScreenCover(isPresented: $creating) {
        TrainingEditor(draft: TrainingMaterial(kind: kind), original: nil)
      }
  }

  private func listing(wide: Bool) -> some View {
    List {
      if let issue = store.issue {
        Text(issue)
        Button("重试读取") { store.reload() }
      }
      HStack(alignment: .top) {
        NotebookHeading(title: kind.tool.title, detail: "本机保存 · "+String(rows.count)+" 份")
        Button { creating = true } label: { Label("新建", systemImage: "plus") }
          .buttonStyle(.borderedProminent).disabled(store.issue != nil).accessibilityIdentifier("newTraining")
      }.listRowBackground(Color.clear).listRowSeparator(.hidden)
      if let first = rows.first {
        if !wide {
          Section("最近保存") {
            NavigationLink { TrainingDetail(id: first.id) } label: {
              LatestTrainingCard(title: first.title, audience: first.audience.isEmpty ? kind.tool.title : first.audience,
                                 date: first.date, summary: first.body, action: "查看"+kind.tool.title, icon: kind.tool.symbol)
            }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
          }
        }
        let remaining = wide ? rows : Array(rows.dropFirst())
        if !remaining.isEmpty {
          Section(wide ? "已保存" : "其他"+kind.tool.title) {
            ForEach(remaining) { item in
              if wide {
                Button { selected = item.id } label: { row(item) }.buttonStyle(.plain)
                  .listRowBackground(current?.id == item.id ? Notebook.inset : Notebook.paper)
              } else {
                NavigationLink { TrainingDetail(id: item.id) } label: { row(item) }
              }
            }
          }
        }
      } else {
        ContentUnavailableView("还没有"+kind.tool.title, systemImage: kind.tool.symbol, description: Text("点「新建」开始填写。"))
          .listRowBackground(Color.clear)
      }
    }.notebookForm()
  }

  private func row(_ item: TrainingMaterial) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(item.title).font(.headline)
      Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
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
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            TrainingSummary(content: item.card)
            if item.kind == .team {
              NavigationLink {
                PlanRunView(preferred: item.id)
              } label: {
                Label("按计划计时", systemImage: "timer")
              }
              .buttonStyle(.borderedProminent)
            }
            HStack {
              NavigationLink {
                ShareCardPreview(content: item.card)
              } label: {
                Label("图片分享", systemImage: "square.and.arrow.up")
              }
              Spacer()
              Button("编辑") { editing = item }
              Button(role: .destructive) {
                deleting = true
              } label: {
                Image(systemName: "trash")
              }.accessibilityLabel("删除")
            }.buttonStyle(.bordered)
          }.padding().frame(maxWidth: 680)
        }.frame(maxWidth: .infinity)
      } else {
        ContentUnavailableView("记录已删除", systemImage: "folder")
      }
    }.background(Theme.paper)
      .fullScreenCover(item: $editing) { TrainingEditor(draft: $0, original: $0) }
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
}

private struct TrainingEditor: View {
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
  @State private var preview = false
  @State private var problem: String?
  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        if geometry.size.width >= 700 {
          HStack(spacing: 0) {
            fields
            Divider()
            summary.frame(maxWidth: .infinity)
          }
        } else {
          VStack(spacing: 0) {
            Picker("编辑视图", selection: $preview) {
              Text("填写").tag(false)
              Text("预览").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
            if preview { summary } else { fields }
          }
        }
      }.background(Theme.paper)
        .navigationTitle(draft.kind.tool.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("取消") { if draft == initial { dismiss() } else { discard = true } } }
          ToolbarItem(placement: .primaryAction) {
            Button("保存") {
              do {
                try store.save(draft, replacing: original)
                dismiss()
              } catch { problem = error.localizedDescription }
            }.disabled(!draft.valid).accessibilityIdentifier("trainingSave")
          }
        }
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

        TrainingSummary(content: draft.card)
      }.padding()
    }.frame(maxWidth: .infinity)
  }
  private var fields: some View {
    Form {
      Section {
        TextField("标题", text: $draft.title).accessibilityIdentifier("trainingTitle")
        TextField(draft.kind.audienceLabel, text: $draft.audience)
        DatePicker("日期", selection: $draft.date, displayedComponents: .date)
      }
      Section(draft.kind.bodyLabel) {
        TextField(draft.kind.bodyLabel, text: $draft.body, axis: .vertical).lineLimit(3...12)
          .accessibilityIdentifier("trainingBody")
      }
      if draft.kind == .team {
        Section("训练环节") {
          ForEach($draft.stages) { $stage in
            VStack(alignment: .leading, spacing: 7) {
              TextField("环节名称", text: $stage.name).accessibilityIdentifier("stageName")
              Stepper("\(stage.minutes) 分钟", value: $stage.minutes, in: 1...240)
              TextField("安排与提示", text: $stage.instructions, axis: .vertical)
              let i = draft.stages.firstIndex { $0.id == stage.id } ?? 0
              HStack {
                Button("上移") { draft.stages.swapAt(i, i - 1) }.disabled(i == 0)
                Button("下移") { draft.stages.swapAt(i, i + 1) }.disabled(i + 1 >= draft.stages.count)
                Spacer()
                Button("移除", role: .destructive) { draft.stages.removeAll { $0.id == stage.id } }
              }.buttonStyle(.borderless)
            }
          }
          Button("添加环节", systemImage: "plus") { draft.stages.append(TrainingStage()) }
        }
      } else {
        Section(draft.kind == .note ? "教学重点" : "次数或时长") {
          TextField(draft.kind == .note ? "教学重点" : "次数或时长", text: $draft.focus, axis: .vertical)
            .accessibilityIdentifier("trainingFocus")
        }
        Section(draft.kind == .note ? "下次跟进" : "注意事项") {
          TextField(draft.kind == .note ? "下次跟进" : "注意事项", text: $draft.followUp, axis: .vertical)
        }
      }
      TextField("教练署名", text: $draft.author)
    }.notebookForm()
  }
}

struct TrainingSummary: View {
  let content: ShareCardContent
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(content.title.isEmpty ? "标题" : content.title).font(.title.bold())
      Text(content.date, style: .date).font(.caption).foregroundStyle(.secondary)
      ForEach(content.sections.indices, id: \.self) { i in
        Divider()
        Text(content.sections[i].heading).font(.headline).foregroundStyle(Theme.burgundy)
        Text(content.sections[i].body).textSelection(.enabled)
      }
      if !content.author.isEmpty { Label(content.author, systemImage: "signature").font(.subheadline).foregroundStyle(.secondary) }
    }.frame(maxWidth: .infinity, alignment: .leading).notebookPanel()
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
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let issue = store.issue {
          Text(issue)
          Button("重试读取") { store.reload() }
        }
        if let run = store.run {
          TimelineView(.periodic(from: .now, by: 1)) { clock in
            let left = run.remaining(at: clock.date)
            let stage = run.plan.stages[run.index]
            VStack(alignment: .leading, spacing: 12) {
              Text(run.plan.title).font(.headline)
              ProgressView(value: Double(run.finished ? run.plan.stages.count : run.index), total: Double(run.plan.stages.count))
                .tint(Notebook.fieldGreen).accessibilityLabel("已完成环节")

              Text(
                run.finished
                  ? "训练已结束" : "第 \(run.index + 1) / \(run.plan.stages.count) 段 · " + stage.name
              ).font(.title2.bold())
              if !run.finished {
                Text(String(format: "%02d:%02d", left / 60, left % 60)).font(
                  .system(size: 62, weight: .semibold, design: .rounded)
                ).monospacedDigit().accessibilityIdentifier("planRemaining")
                if left == 0 { Text("本段时间到，请确认下一步。").foregroundStyle(Theme.burgundy) }
                if !stage.instructions.isEmpty { Text(stage.instructions) }
                HStack {
                  Button(run.deadline == nil ? "继续" : "暂停") {
                    act { try store.changeRun { $0.toggle(at: .now) } }
                  }.disabled(left == 0)
                  Button("延长 1 分钟") { act { try store.changeRun { $0.extend(at: .now) } } }
                }.buttonStyle(.bordered)
                if run.index + 1 < run.plan.stages.count {
                  Text("下一段 · " + run.plan.stages[run.index + 1].name).font(.caption)
                  Button("下一段") { act { try store.changeRun { $0.advance(at: .now) } } }
                    .buttonStyle(.borderedProminent)
                }
                Button("结束训练", role: .destructive) { ending = true }
              }
            }.frame(maxWidth: .infinity, alignment: .leading).padding().background(
              .white, in: RoundedRectangle(cornerRadius: 12))
          }
        }
        if let plan {
          Picker("选择团训计划", selection: Binding(get: { plan.id }, set: { selected = $0 })) {
            ForEach(plans) { Text($0.title).tag($0.id) }
          }
          NotebookHeading(title: "环节顺序", detail: plan.summary)
          ForEach(Array(plan.stages.enumerated()), id: \.element.id) { index, stage in
            HStack {
              Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit()).foregroundStyle(Theme.burgundy)
              Text(stage.name)
              Spacer()
              Text("\(stage.minutes) 分钟").foregroundStyle(.secondary)
            }
          }
          Button(store.run?.finished == false ? "重新开始所选计划" : "开始计时") {
            if store.run?.finished == false { replace = true } else { start() }
          }.buttonStyle(.borderedProminent).accessibilityIdentifier("startPlanTimer")
        } else {
          Text("先编排训练环节，再按顺序计时。").foregroundStyle(.secondary)
          NavigationLink("前往团训计划") { TrainingList(kind: .team) }
        }
      }.padding().frame(maxWidth: 620)
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
