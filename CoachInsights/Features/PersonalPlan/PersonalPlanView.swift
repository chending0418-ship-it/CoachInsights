import SwiftUI

struct PersonalPlanListView: View {
    @EnvironmentObject private var store: PersonalPlanStore
    @State private var creating = false
    var body: some View {
        let documents = store.plans.map { plan in
            NotebookDocument(id: plan.id, title: plan.title, audience: plan.athlete, date: plan.date,
                             lead: plan.goal, footer: "查看计划", rowDetail: plan.athlete)
        }
        DocumentLibrary(title: "个人训练计划", noun: "计划", icon: "list.clipboard", documents: documents,
                        issue: store.readIssue, createID: "newPersonalPlan", retry: store.reload,
                        create: { creating = true }) { id, embedded in PersonalPlanDetailView(id: id, embedded: embedded) }
            .navigationDestination(isPresented: $creating) { PersonalPlanEditor() }
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
                if embedded {
                    VStack(alignment: .leading, spacing: 10) { actions(plan); PersonalPlanSummary(content: plan.card) }
                } else {
                    DocumentReader(sections: plan.card.sections.filter { $0.heading != "球员" }.map(\.heading)) { PersonalPlanSummary(content: plan.card) } actions: { actions(plan) }
                        .notebookPageTitle("计划详情")
                }
            } else {
                ContentUnavailableView("计划已不存在", systemImage: "list.bullet.clipboard")
            }
        }
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .notebookDestination(item: $editing) { PersonalPlanEditor(original: $0) }
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
    private func actions(_ plan: PersonalPlan) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons(plan) }
            VStack(alignment: .leading, spacing: 8) { buttons(plan) }
        }
    }
    @ViewBuilder private func buttons(_ plan: PersonalPlan) -> some View {
        NavigationLink { ShareCardPreview(content: plan.card) } label: { Label("预览与分享图片", systemImage: "square.and.arrow.up") }
            .buttonStyle(DocumentButtonStyle(primary: true)).accessibilityIdentifier("personalPlanShare")
        Button { editing = plan } label: { Label("编辑", systemImage: "pencil") }
            .buttonStyle(DocumentButtonStyle()).accessibilityIdentifier("editPersonalPlan")
        if embedded {
            NavigationLink { PersonalPlanDetailView(id: id) } label: { Label("打开", systemImage: "arrow.up.right") }
                .buttonStyle(DocumentButtonStyle())
        } else {
            Button(role: .destructive) { confirmingDeletion = true } label: { Image(systemName: "trash").accessibilityLabel("删除计划") }
                .buttonStyle(DocumentButtonStyle()).accessibilityIdentifier("deletePersonalPlan")
        }
    }

}

private struct PersonalPlanEditor: View {
    @State private var showingPreview = false
    @EnvironmentObject private var store: PersonalPlanStore
    @Environment(\.dismiss) private var dismiss
    private let original: PersonalPlan?
    @State private var initial: PersonalPlan
    @State private var draft: PersonalPlan
    @State private var confirmingDiscard = false
    @State private var issue: String?

    init(original: PersonalPlan? = nil) {
        let initial = original ?? PersonalPlan()
        self.original = original
        _initial = State(initialValue: initial)
        _draft = State(initialValue: initial)
    }

    var body: some View {
        Group {
            DocumentEditorLayout(title: original == nil ? "新建计划" : "编辑计划", context: "单次训练", navigationTitle: "填写个人计划",
                                 canSave: draft.canSave, saveID: "savePersonalPlan", cancelID: "cancelPersonalPlan",
                                 cancel: { if draft == initial { dismiss() } else { confirmingDiscard = true } }, save: {
                do { try store.save(draft, replacing: original); dismiss() }
                catch { issue = error.localizedDescription }
            }, showingPreview: $showingPreview) { fields } preview: { preview }
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
                NotebookColumns(minimumWidth: 300, leadingFraction: 0.48, spacing: 10) {
                  NotebookInput(title: "训练日期") { DatePicker("训练日期", selection: $draft.date, displayedComponents: .date).labelsHidden() }
                  NotebookInput(title: "教练署名") { TextField("署名", text: $draft.author).accessibilityIdentifier("personalPlanAuthor") }
                }
              HStack {
                Button("取消编辑") { if draft == initial { dismiss() } else { confirmingDiscard = true } }
                    .buttonStyle(DocumentButtonStyle())
                Button { showingPreview = true } label: { Label("预览内容", systemImage: "eye") }
                    .buttonStyle(DocumentButtonStyle())
            }
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
            Label("个人训练计划", systemImage: "list.bullet.clipboard").font(.caption.bold()).foregroundStyle(Theme.burgundy)
            Text(content.title.isEmpty ? "个人训练计划" : content.title)
                .font(.title.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("personalPlanPreviewTitle")
            HStack {
                Text(content.date, style: .date)
                if let athlete = content.sections.first(where: { $0.heading == "球员" }) { Text("/ " + athlete.body) }
            }.font(.subheadline).foregroundStyle(.secondary)
            ForEach(content.sections.filter { $0.heading != "球员" }, id: \.heading) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text(section.heading).font(.headline).foregroundStyle(Theme.burgundy).id(section.heading)
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
