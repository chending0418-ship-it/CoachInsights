import SwiftUI

struct PersonalPlanListView: View {
    @EnvironmentObject private var store: PersonalPlanStore
    @State private var creating = false
    @State private var selection: UUID?

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 720
            HStack(spacing: 0) {
                list(wide: wide).frame(width: wide && !store.plans.isEmpty ? max(265, geometry.size.width * 0.34) : geometry.size.width)
                if wide, let plan = selection.flatMap({ store.plan($0) }) ?? store.plans.first {
                    Divider()
                    PersonalPlanDetailView(id: plan.id, embedded: true).id(plan.id)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(PocketTool.personalPlan.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $creating) { PersonalPlanEditor() }
    }

    private func list(wide: Bool) -> some View {
        List {
            if let issue = store.readIssue {
                Section {
                    Text(issue).foregroundStyle(.red)
                    Button("重试读取") { store.reload() }
                }
            }
            HStack(alignment: .top) {
                NotebookHeading(title: "个人训练计划", detail: "本机保存 · "+String(store.plans.count)+" 份计划")
                Button("新建", systemImage: "plus") { creating = true }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("newPersonalPlan").disabled(store.readIssue != nil)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if let first = store.plans.first {
                if !wide {
                    Section("最近保存") {
                        NavigationLink { PersonalPlanDetailView(id: first.id) } label: {
                            LatestTrainingCard(title: first.title, audience: first.athlete.isEmpty ? "个人训练" : first.athlete,
                                               date: first.date, summary: first.goal, action: "查看计划", icon: "list.clipboard")
                        }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                }
                let remaining = wide ? store.plans : Array(store.plans.dropFirst())
                if !remaining.isEmpty {
                    Section(wide ? "已保存计划" : "其他计划") {
                        ForEach(remaining) { plan in
                            let row = NotebookToolRow(title: plan.title, detail: plan.date.formatted(date: .abbreviated, time: .omitted), icon: "list.clipboard")
                            if wide {
                                Button { selection = plan.id } label: { row }.buttonStyle(.plain)
                                    .listRowBackground(plan.id == (selection ?? first.id) ? Notebook.inset : Notebook.paper)
                            } else {
                                NavigationLink { PersonalPlanDetailView(id: plan.id) } label: { row }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("还没有个人训练计划", systemImage: "list.clipboard", description: Text("点「新建」开始填写。"))
                    .listRowBackground(Color.clear)
            }
        }
        .notebookForm()
    }
}

struct PersonalPlanDetailView: View {
    @EnvironmentObject private var store: PersonalPlanStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PersonalPlan?
    @State private var confirmingDeletion = false
    @State private var issue: String?
    let id: UUID
    var embedded = false

    var body: some View {
        Group {
            if let plan = store.plan(id) {
                ScrollView {
                    NotebookColumns {
                        PersonalPlanSummary(content: plan.card)
                        VStack(alignment: .leading, spacing: 16) {
                            NavigationLink { ShareCardPreview(content: plan.card) } label: {
                                Label("预览与分享图片", systemImage: "square.and.arrow.up")
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("personalPlanShare")
                            Button("编辑") { editing = plan }.accessibilityIdentifier("editPersonalPlan")
                            Button("删除计划", systemImage: "trash", role: .destructive) { confirmingDeletion = true }
                                .accessibilityIdentifier("deletePersonalPlan")
                        }.notebookPanel()
                    }.padding(20)
                }
            } else {
                ContentUnavailableView("计划已不存在", systemImage: "list.bullet.clipboard")
            }
        }
        .background(Theme.paper)
        .navigationTitle(embedded ? "个人训练计划" : "计划详情")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $editing) { PersonalPlanEditor(original: $0) }
        .alert("删除这份计划？", isPresented: $confirmingDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                do { try store.remove(id); if !embedded { dismiss() } }
                catch { issue = error.localizedDescription }
            }
        } message: {
            Text("删除本机计划。已保存或分享的图片会保留。")
        }
        .alert("删除失败", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(issue ?? "") }
    }
}

private struct PersonalPlanEditor: View {
    @EnvironmentObject private var store: PersonalPlanStore
    @Environment(\.dismiss) private var dismiss
    private let original: PersonalPlan?
    @State private var initial: PersonalPlan
    @State private var draft: PersonalPlan
    @State private var previewing = false
    @State private var confirmingDiscard = false
    @State private var issue: String?

    init(original: PersonalPlan? = nil) {
        let initial = original ?? PersonalPlan()
        self.original = original
        _initial = State(initialValue: initial)
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width >= 700 {
                    HStack(spacing: 0) {
                        fields.frame(maxWidth: 520)
                        Divider()
                        preview
                    }
                } else {
                    VStack(spacing: 0) {
                        Picker("计划编辑视图", selection: $previewing) {
                            Text("填写").tag(false)
                            Text("预览").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("personalPlanEditorMode")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        if previewing { preview } else { fields }
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle(original == nil ? "新建个人训练计划" : "编辑个人训练计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if draft == initial { dismiss() } else { confirmingDiscard = true }
                    }
                    .accessibilityIdentifier("cancelPersonalPlan")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try store.save(draft, replacing: original); dismiss() }
                        catch { issue = error.localizedDescription }
                    }
                    .disabled(!draft.canSave)
                    .accessibilityIdentifier("savePersonalPlan")
                }
            }
            .alert("放弃未保存的修改？", isPresented: $confirmingDiscard) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃修改", role: .destructive) { dismiss() }
            }
            .alert("保存失败", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text(issue ?? "")
            }
        }
    }

    private var fields: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NotebookInput(title: "计划标题 · 必填") { TextField("计划标题", text: $draft.title).accessibilityIdentifier("personalPlanTitle") }
                NotebookInput(title: "球员姓名") { TextField("球员姓名", text: $draft.athlete).accessibilityIdentifier("personalPlanAthlete") }
                NotebookInput(title: "训练目标") { TextField("这次训练希望达到什么？", text: $draft.goal, axis: .vertical).lineLimit(2...6).accessibilityIdentifier("personalPlanGoal") }
                NotebookInput(title: "训练项目 · 必填") { TextField("逐行填写项目、组数或时长", text: $draft.drills, axis: .vertical).lineLimit(3...10).accessibilityIdentifier("personalPlanDrills") }
                DatePicker("训练日期", selection: $draft.date, displayedComponents: .date)
                NotebookInput(title: "教练署名") { TextField("署名", text: $draft.author).accessibilityIdentifier("personalPlanAuthor") }
            }.padding(20)
        }.scrollDismissesKeyboard(.interactively)
    }

    private var preview: some View {
        ScrollView { PersonalPlanSummary(content: draft.card).padding(24) }
            .accessibilityIdentifier("personalPlanTextPreview")
    }
}

private struct PersonalPlanSummary: View {
    let content: ShareCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(content.date, style: .date).font(.subheadline).foregroundStyle(.secondary)
            Text(content.title.isEmpty ? "个人训练计划" : content.title)
                .font(.title.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("personalPlanPreviewTitle")
            ForEach(content.sections, id: \.heading) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text(section.heading).font(.headline).foregroundStyle(Theme.burgundy)
                    if section.heading == "训练项目" { NumberedInstructions(text: section.body) } else { Text(section.body).textSelection(.enabled) }
                }
            }
            if !content.author.isEmpty {
                Text(content.author).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .notebookPanel()
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
