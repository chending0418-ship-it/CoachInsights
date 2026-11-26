import SwiftUI

struct PersonalPlanListView: View {
    @EnvironmentObject private var store: PersonalPlanStore
    @State private var creating = false
    @State private var selection: UUID?

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 720
            HStack(spacing: 0) {
                list(wide: wide)
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
            Section {
                NotebookHeading(title: "个人训练计划", detail: "已保存 "+String(store.plans.count)+" 份计划")
                    .listRowBackground(Color.clear)
                Button("新建计划", systemImage: "plus") { creating = true }
                    .accessibilityIdentifier("newPersonalPlan")
                    .disabled(store.readIssue != nil)
            }
            Section("已保存计划") {
                if store.plans.isEmpty {
                    Text("保存后的计划会在这里和「记录」中显示。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.plans) { plan in
                    let row = NotebookToolRow(title: plan.title, detail: plan.date.formatted(date: .abbreviated, time: .omitted), icon: "list.clipboard")
                    if wide {
                        Button { selection = plan.id } label: { row }.buttonStyle(.plain)
                    } else {
                        NavigationLink { PersonalPlanDetailView(id: plan.id) } label: { row }
                    }
                }
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
                ScrollView { PersonalPlanSummary(content: plan.card).padding(24) }
                    .safeAreaInset(edge: .bottom) {
                        NavigationLink {
                            ShareCardPreview(content: plan.card)
                        } label: {
                            Label("预览与分享图片", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("personalPlanShare")
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("编辑") { editing = plan }
                                .accessibilityIdentifier("editPersonalPlan")
                        }
                        ToolbarItem(placement: .secondaryAction) {
                            Button("删除计划", systemImage: "trash", role: .destructive) {
                                confirmingDeletion = true
                            }
                            .accessibilityIdentifier("deletePersonalPlan")
                        }
                    }
            } else {
                ContentUnavailableView("计划已不存在", systemImage: "list.bullet.clipboard")
            }
        }
        .background(Theme.paper)
        .navigationTitle("计划详情")
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
        Form {
            Section {
                TextField("计划标题（必填）", text: $draft.title)
                    .accessibilityIdentifier("personalPlanTitle")
                DatePicker("训练日期", selection: $draft.date, displayedComponents: .date)
                TextField("球员姓名（选填）", text: $draft.athlete)
                    .accessibilityIdentifier("personalPlanAthlete")
                TextField("教练署名（选填）", text: $draft.author)
                    .accessibilityIdentifier("personalPlanAuthor")
            } header: {
                Text("单次训练")
            } footer: {
                Text("图片会包含填写的姓名与署名，分享前可在图片预览中核对。")
            }
            Section("训练目标") {
                TextField("这次训练希望达到什么？（选填）", text: $draft.goal, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityIdentifier("personalPlanGoal")
            }
            Section {
                TextField("填写训练项目（必填）", text: $draft.drills, axis: .vertical)
                    .lineLimit(4...10)
                    .accessibilityIdentifier("personalPlanDrills")
            } header: {
                Text("训练项目")
            } footer: {
                Text("可按顺序逐行填写，附上组数、次数或时长。")
            }
        }
        .notebookForm()
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
                    Text(section.body).textSelection(.enabled)
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
