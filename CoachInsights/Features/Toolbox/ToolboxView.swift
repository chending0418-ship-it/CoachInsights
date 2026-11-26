import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var tools: QuickToolsStore
    private enum Section { case toolbox, records }
    @State private var section = Section.toolbox
    @State private var toolboxPath: [ToolboxRoute] = []
    @State private var recordPath: [UUID] = []
    @State private var recordFilter = PocketRecordFilter()
    @State private var sidebarVisible = true
    @State private var mediaWorkspaceFocused = false
    @State private var mediaNavigationHidden = false

    private var showsTabs: Bool {
        #if DEBUG
        if section == .toolbox && toolboxPath.last == .shareExample { return false }
        #endif
        if section == .records { return recordPath.isEmpty }
        if case .tool = toolboxPath.last { return false }
        return true
    }
    private var isBoard: Bool {
        if section == .toolbox { return toolboxPath.last == .tool(.tacticsBoard) }
        return recordPath.last.map { id in tools.state.boards.contains { $0.id == id } } ?? false
    }

    var body: some View {
        GeometryReader { geometry in
            let studio = geometry.size.width >= 900
            HStack(spacing: 0) {
                if studio && sidebarVisible && !isBoard && !mediaWorkspaceFocused {
                    studioSidebar.frame(width: 195)
                    Divider()
                }
                content
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if studio && !sidebarVisible && !isBoard && !mediaWorkspaceFocused {
                            HStack {
                                Button { sidebarVisible = true } label: { Label("展开工作室侧栏", systemImage: "sidebar.left") }
                                    .frame(minHeight: 44).accessibilityIdentifier("studioSidebarToggle")
                                Spacer()
                            }.padding(.horizontal, 16).background(PocketStyle.paper)
                        }
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsTabs && !studio { tabs }
            }
        }
        .background(PocketStyle.paper)
        .onPreferenceChange(MediaWorkspaceFocusPreferenceKey.self) { mediaWorkspaceFocused = $0 }
        .onPreferenceChange(MediaWorkspaceNavigationHiddenPreferenceKey.self) { mediaNavigationHidden = $0 }
        .task { await library.retry() }
    }

    private var content: some View {
        Group {
            if section == .toolbox {
                NavigationStack(path: $toolboxPath) {
                    ToolboxHomeView { id in
                        recordFilter = PocketRecordFilter(); recordPath = id.map { [$0] } ?? []; section = .records
                    }
                        .navigationDestination(for: ToolboxRoute.self) { route in
                            Group {
                                switch route {
                                case .scene(let scene):
                                    ToolSceneView(scene: scene) { id in
                                        recordFilter = PocketRecordFilter(scene: scene)
                                        recordPath = id.map { [$0] } ?? []
                                        section = .records
                                    }
                                case .tool(let tool): ToolDestinationView(tool: tool)
                                #if DEBUG
                                case .shareExample: ShareCardExampleView()
                                #endif
                                }
                            }
                            .toolbar(route == .tool(.tacticsBoard) || mediaNavigationHidden ? .hidden : .visible, for: .navigationBar)
                        }
                }
            } else {
                NavigationStack(path: $recordPath) { PocketRecordsView(filter: $recordFilter) { recordPath.append($0) } }
            }
        }
    }

    private var tabs: some View {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 0) {
                        tab("工具箱", symbol: "square.grid.2x2", section: .toolbox, identifier: "toolboxTab")
                        tab("记录", symbol: "folder", section: .records, identifier: "recordsTab")
                    }.padding(.top, 8).padding(.bottom, 4)
                }.background(.white)
    }

    private var studioSidebar: some View {
        List {
            SwiftUI.Section {
                Image("LaunchIdentityLight").resizable().scaledToFit().frame(maxWidth: 158, maxHeight: 36).accessibilityLabel("棒球训练助手")
                Text("训练工具箱").font(.caption).foregroundStyle(.secondary)
                Button { sidebarVisible = false } label: { Label("收起侧栏", systemImage: "sidebar.left") }
                    .accessibilityIdentifier("studioSidebarToggle")
                Button { section = .toolbox; toolboxPath = [] } label: { Label("工具箱", systemImage: "square.grid.2x2") }
                    .accessibilityIdentifier("toolboxTab")
                Button { section = .records } label: { Label("记录", systemImage: "folder") }
                    .accessibilityIdentifier("recordsTab")
            }
            SwiftUI.Section("训练场景") {
                ForEach(PocketScene.allCases) { scene in
                    Button {
                        section = .toolbox
                        toolboxPath = [.scene(scene)]
                    } label: {
                        Label(scene.title, systemImage: scene.symbol)
                    }.accessibilityIdentifier("sidebarScene_" + scene.rawValue)
                }
            }
        }
        .listStyle(.sidebar).scrollContentBackground(.hidden).background(PocketStyle.paper)
        .accessibilityIdentifier("studioSidebar")
    }

    private func tab(_ title: String, symbol: String, section target: Section, identifier: String) -> some View {
        Button {
            if section == target && target == .toolbox { toolboxPath.removeAll() }
            section = target
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(.caption)
            }.frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(section == target ? Theme.burgundy : .secondary)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(section == target ? .isSelected : [])
    }
}

private enum PocketStyle {
    static let paper = Theme.paper
    static let wash = Notebook.inset
    static let line = Notebook.rule
    static let navy = Color(red: 0.043, green: 0.098, blue: 0.200)
}

private struct ToolboxHomeView: View {
    @EnvironmentObject private var fields: FieldToolsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var quick: QuickToolsStore
    @EnvironmentObject private var training: TrainingStore
    @EnvironmentObject private var plans: PersonalPlanStore
    @AppStorage("bullpen.viewpoint") private var viewpoint = PitchViewpoint.catcher
    let showRecords: (UUID?) -> Void
    @State private var showHelp = false
    @State private var wideShortcuts = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image("LaunchIdentityLight").resizable().scaledToFit().frame(width: 148, height: 32)
                        .accessibilityLabel("棒球训练助手")
                    Spacer()
                    Button { showHelp = true } label: { Label("帮助", systemImage: "questionmark.circle").font(.subheadline).frame(minHeight: 44) }
                        .accessibilityLabel("使用帮助")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date.now.formatted(.dateTime.month().day().weekday(.wide))).font(.caption).foregroundStyle(.secondary)
                    Text("训练工具箱").font(.largeTitle.bold())
                }
                NotebookColumns(minimumWidth: 680, leadingFraction: 0.57) {
                    fieldSection
                    shortcuts
                }
                scenes
                recentSection
                #if DEBUG
                NavigationLink("图片分享卡片 · 示例",value: ToolboxRoute.shareExample).font(.footnote).accessibilityIdentifier("shareCardExample")
                #endif
            }.padding(.horizontal,20).padding(.bottom,20).frame(maxWidth: 1120).frame(maxWidth:.infinity)
            }
        }.onGeometryChange(for: Bool.self) { $0.size.width >= 720 } action: { wideShortcuts = $0 }
        .background(PocketStyle.paper).toolbar(.hidden,for:.navigationBar)
        .sheet(isPresented: $showHelp) { NavigationStack { HelpView().toolbar { Button("完成") { showHelp = false } } } }
    }

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let draft = fields.log(kind: .bullpen, id: nil)
            NavigationLink(value: ToolboxRoute.tool(.bullpenLog)) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("投球记录", systemImage: PocketTool.bullpenLog.symbol).font(.caption)
                        Text(draft.flatMap { $0.name.isEmpty ? nil : $0.name } ?? "牛棚投球").font(.title2.bold()).foregroundStyle(.primary)
                        if let draft, !draft.pitches.isEmpty {
                            Text("\(draft.pitches.count) 球 · 好球率 \(draft.strikeRateText)").font(.subheadline.monospacedDigit())
                        }
                        Label(draft?.events.isEmpty == false ? "继续记球" : "开始记球", systemImage: "arrow.right").font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(.white).background(Theme.burgundy, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                    PitchLocationMap(pitches: draft?.pitches ?? [], viewpoint: viewpoint, readOnly: true) { _ in }
                        .frame(width: 100).allowsHitTesting(false).accessibilityHidden(true)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(PocketStyle.wash,in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("bullpenShortcut")
        }
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("场边常用").font(.headline)
            let flow = wideShortcuts ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 5))
            flow {
                ForEach([PocketTool.battingLog, .tacticsBoard, .stopwatch]) { tool in
                    NavigationLink(value: ToolboxRoute.tool(tool)) {
                        Label(tool.title,systemImage: tool.symbol).font(.subheadline)
                            .frame(maxWidth: .infinity,minHeight: 46)
                    }.accessibilityIdentifier("shortcut_" + tool.rawValue)
                }
            }
        }
    }

    private var scenes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("训练场景").font(.headline)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                ForEach(PocketScene.allCases) { scene in sceneLink(scene) }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近记录").font(.headline); Spacer()
                Button("查看全部") { showRecords(nil) }.font(.subheadline)
            }
            let recent = PocketRecord.timeline(library: library, quick: quick, fields: fields, plans: plans, training: training).prefix(3)
            if recent.isEmpty { Text("保存的训练会显示在这里。").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(recent) { record in
                Button { showRecords(record.id) } label: {
                    HStack {
                        Image(systemName: record.tool.symbol)
                        VStack(alignment: .leading) {
                            Text(record.name).font(.headline).foregroundStyle(.primary)
                            Text(record.tool.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                    }.padding(.vertical,6).contentShape(Rectangle())
                }
                Divider()
            }
        }
    }

    private func sceneLink(_ scene: PocketScene) -> some View {
        NavigationLink(value: ToolboxRoute.scene(scene)) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: scene.symbol).font(.subheadline).foregroundStyle(Theme.burgundy)
                Text(scene.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }.padding(10).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(Notebook.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Notebook.rule) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("scene_"+scene.rawValue)
    }
}

private extension PocketRecord {
    @MainActor static func timeline(library: LibraryStore, quick: QuickToolsStore, fields: FieldToolsStore, plans: PersonalPlanStore, training: TrainingStore) -> [PocketRecord] {
        let video = library.busy ? [] : library.sessions.map(PocketRecord.init)
        return (video + quick.state.boards.map(PocketRecord.init) + quick.state.distances.map(PocketRecord.init)
                + fields.state.records.map(PocketRecord.init(fieldLog:)) + plans.plans.map(\.record) + training.items.map(\.record))
            .sorted { $0.createdAt > $1.createdAt }
    }
}

private struct ToolSceneView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var quick: QuickToolsStore
    @EnvironmentObject private var fields: FieldToolsStore
    @EnvironmentObject private var plans: PersonalPlanStore
    @EnvironmentObject private var training: TrainingStore
    let scene: PocketScene
    let openRecord: (UUID?) -> Void
    @State private var twoColumns = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NotebookHeading(title: scene.title, detail: scene.summary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: twoColumns ? 2 : 1), alignment: .leading, spacing: 10) {
                    ForEach(scene.tools) { tool in
                        NavigationLink(value: ToolboxRoute.tool(tool)) {
                            NotebookToolRow(title: tool.title, detail: tool.summary, icon: tool.symbol)
                                .notebookPanel()
                        }.buttonStyle(.plain).accessibilityIdentifier("tool_" + tool.rawValue)
                    }
                }
                let recent = PocketRecord.timeline(library: library, quick: quick, fields: fields, plans: plans, training: training)
                    .filter { $0.scene == scene }.prefix(3)
                if !recent.isEmpty {
                    HStack { Text("相关记录").font(.headline); Spacer(); Button("查看全部") { openRecord(nil) } }
                    ForEach(recent) { record in
                        Button { openRecord(record.id) } label: {
                            NotebookToolRow(title: record.name, detail: record.tool.title, icon: record.tool.symbol)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }.padding(20).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 620 } action: { twoColumns = $0 }
        .navigationTitle(scene.title).navigationBarTitleDisplayMode(.inline)
    }
}

private struct ToolDestinationView: View {
    let tool: PocketTool

    var body: some View {
        switch tool {
        case .videoAnalysis: VideoLibraryView(mode: .analysis)
        case .motionComparison: VideoLibraryView(mode: .comparison)
        case .personalPlan: PersonalPlanListView()
        case .stopwatch: StopwatchView()
        case .countdown: CountdownView()
        case .tacticsBoard: TacticsBoardView(recordID: nil)
        case .distance: DistanceView()
        case .battingLog: FieldLogView(kind: .batting)
        case .bullpenLog: FieldLogView(kind: .bullpen)
        case .gameCounter: FieldLogView(kind: .game)
        case .coachNotes: TrainingList(kind: .note)
        case .homeworkCard: TrainingList(kind: .homework)
        case .teamPlan: TrainingList(kind: .team)
        case .planTimer: PlanRunView()
        }
    }
}

private struct PocketRecordsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var tools: QuickToolsStore
    @EnvironmentObject private var fieldTools: FieldToolsStore
    @EnvironmentObject private var training: TrainingStore
    @EnvironmentObject private var personalPlans: PersonalPlanStore
    @Binding var filter: PocketRecordFilter
    let openRecord: (UUID) -> Void
    @State private var pendingDelete: UUID?
    @State private var deletionIssue: String?
    @State private var search = ""
    @State private var inspection: UUID?
    @State private var compactDetail: PocketRecord?
    private enum DetailAction { case open(UUID), delete(UUID) }
    @State private var detailAction: DetailAction?


    private var records: [PocketRecord] {
        PocketRecord.timeline(library: library, quick: tools, fields: fieldTools, plans: personalPlans, training: training)
            .filter { filter.includes($0) && (search.isEmpty || [$0.name,$0.tool.title,$0.summary ?? ""].contains { $0.localizedCaseInsensitiveContains(search) }) }
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 660
            let visibleRecords = records
            let selected = visibleRecords.first(where: { $0.id == inspection }) ?? visibleRecords.first
            HStack(spacing: 0) {
                recordList(wide: wide, records: visibleRecords, selectedID: selected?.id)
                if wide, let selected {
                    Divider()
                    RecordInspection(record: selected, open: { openRecord(selected.id) },
                                     delete: { pendingDelete = selected.id })
                        .frame(maxWidth: 310)
                }
            }
        }.background(PocketStyle.paper)
        .navigationTitle("记录").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $compactDetail, onDismiss: {
            switch detailAction {
            case .open(let id): openRecord(id)
            case .delete(let id): pendingDelete = id
            case nil: break
            }
            detailAction = nil
        }) { record in
            NavigationStack {
                RecordInspection(record: record, open: {
                    detailAction = .open(record.id)
                    compactDetail = nil
                }, delete: {
                    detailAction = .delete(record.id)
                    compactDetail = nil
                })
                    .navigationTitle("记录详情").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("完成") { compactDetail = nil } }
            }.presentationDetents([.medium, .large])
        }
    }

    private func recordList(wide: Bool, records: [PocketRecord], selectedID: UUID?) -> some View {
        List {
            NotebookHeading(title: "训练记录", detail: "按名称、场景或工具查找已保存的训练。")
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索名称或工具", text: $search).submitLabel(.search)
                    if !search.isEmpty { Button("清除", systemImage: "xmark.circle.fill") { search = "" }.labelStyle(.iconOnly) }
                }
                Picker("来源场景", selection: Binding(get: { filter.scene }, set: { filter.selectScene($0) })) {
                    Text("全部").tag(PocketScene?.none)
                    ForEach(PocketScene.allCases) { Text($0.title).tag(Optional($0)) }
                }.pickerStyle(.segmented).accessibilityIdentifier("recordSceneFilter")
                Picker("工具类型", selection: $filter.tool) {
                    Text("全部工具").tag(PocketTool?.none)
                    ForEach(filter.tools) { Text($0.title).tag(Optional($0)) }
                }.accessibilityIdentifier("recordToolFilter")
            }
            if let issue = library.issue {
                Section {
                    Text(issue).foregroundStyle(.red)
                    Button("重试") { Task { await library.retry() } }
                }
            }
            if let issue = fieldTools.issue {
                Section {
                    Text(issue).foregroundStyle(.red)
                    Button("重试读取训练记录") { fieldTools.reload() }
                }
            }
            if let issue = training.issue { Section { Text(issue); Button("重试读取教学内容") { training.reload() } } }
            if let issue = personalPlans.readIssue {
                Section {
                    Text(issue).foregroundStyle(.red)
                    Button("重试读取个人训练计划") { personalPlans.reload() }
                }
            }
            Section {
                if records.isEmpty {
                    EmptyPanel(icon: "folder", title: "没有符合筛选条件的记录", detail: "保存的资料会显示在这里，也可以试试其他场景或工具类型。")
                        .listRowBackground(Color.clear)
                }
                ForEach(records) { record in
                    let row = VStack(alignment: .leading, spacing: 8) {
                            Text(record.scene.title + " · " + record.tool.title).font(.caption).foregroundStyle(Theme.burgundy)
                            if record.sport == nil {
                                Text(record.name).font(.headline)
                                if let summary = record.summary { Text(summary).font(.caption).foregroundStyle(.secondary) }
                                Text(record.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            } else if let sport = record.sport { SessionRow(name: record.name, sport: sport, createdAt: record.createdAt) }
                        }.padding(.vertical, 4)
                    HStack(spacing: 6) {
                        Button {
                            if wide { inspection = record.id } else { openRecord(record.id) }
                        } label: {
                            row.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("record_" + record.id.uuidString)
                        if !wide {
                            Button { compactDetail = record } label: {
                                Image(systemName: "info.circle").frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel("记录详情，" + record.name)
                        }
                    }
                    .listRowBackground(wide && record.id == selectedID ? Notebook.inset : Color.white)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if !wide { Button("详情", systemImage: "info.circle") { compactDetail = record }.tint(Theme.burgundy) }
                    }
                    .contextMenu {
                        if !wide { Button("记录详情", systemImage: "info.circle") { compactDetail = record } }
                        Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = record.id }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            pendingDelete = record.id
                        }
                    }
                }
            } header: {
                Text("\(filter.scene?.title ?? "全部")记录 · \(records.count)")
            }
        }
        .scrollContentBackground(.hidden).background(PocketStyle.paper)
        .navigationDestination(for: UUID.self) { id in
            if let session = library.sessions.first(where: { $0.id == id }) {
                if PocketRecord(session: session).tool == .motionComparison { ComparisonView(session: session) }
                else { SessionDetail(session: session) }
            } else if tools.state.boards.contains(where: { $0.id == id }) {
                TacticsBoardView(recordID: id)
            } else if let distance = tools.state.distances.first(where: { $0.id == id }) {
                SavedDistanceView(record: distance)
            } else if let log = fieldTools.state.records.first(where: { $0.id == id }) {
                FieldLogView(kind: log.kind, recordID: id)
            } else if training.item(id) != nil {
                TrainingDetail(id: id)
            } else if personalPlans.plan(id) != nil {
                PersonalPlanDetailView(id: id)
            } else {
                ContentUnavailableView("记录已不存在", systemImage: "folder.badge.questionmark")
            }
        }
        .alert("删除记录？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let id = pendingDelete {
                    if let session = library.sessions.first(where: { $0.id == id }) { Task { await library.remove(session) } }
                    else if fieldTools.state.records.contains(where: { $0.id == id }) { fieldTools.remove(id) }
                    else if training.item(id) != nil {
                        do { try training.remove(id) } catch { deletionIssue = error.localizedDescription }
                    } else if personalPlans.plan(id) != nil {
                        do { try personalPlans.remove(id) }
                        catch { deletionIssue = error.localizedDescription }
                    }
                    else { tools.removeRecord(id) }
                }
                pendingDelete = nil
            }
        } message: { Text("删除这份本机记录。已保存到相册的图片会保留；其他记录引用的视频会保留。") }
        .alert("删除失败", isPresented: Binding(get: { deletionIssue != nil }, set: { if !$0 { deletionIssue = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(deletionIssue ?? "") }
    }
}

struct RecordInspection: View {
    @EnvironmentObject private var library: LibraryStore
    let record: PocketRecord
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NotebookHeading(title: record.name, detail: record.scene.title + " · " + record.tool.title)
                let session = library.sessions.first { $0.id == record.id }
                if let session, let repository = library.repository, let ids = try? session.snapshot().videoIDs,
                   let asset = try? repository.assets().first(where: { ids.contains($0.id) }) {
                    VideoCover(asset: asset, repository: repository).aspectRatio(16/9, contentMode: .fit)
                }
                LabeledContent("训练内容", value: record.summary ?? session?.sportValue ?? record.tool.title)
                LabeledContent("最近更新") { Text((session?.updatedAt ?? record.createdAt).formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("保存位置", value: "本机记录")
                Button("打开记录", action: open).buttonStyle(.borderedProminent)
                Button("删除记录", role: .destructive, action: delete)
                    .frame(minHeight: 44).accessibilityIdentifier("deleteInspectedRecord")
            }.notebookPanel().padding(20).frame(maxWidth: 620)
        }.frame(maxWidth: .infinity).background(Theme.paper)
    }
}
