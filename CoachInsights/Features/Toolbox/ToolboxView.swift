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
                                case .scene(let scene): ToolSceneView(scene: scene)
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
                NavigationStack(path: $recordPath) { PocketRecordsView(filter: $recordFilter) }
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
                Text("棒球训练助手").font(.title3.bold())
                Text("训练工具箱").font(.caption).foregroundStyle(.secondary)
                Button { sidebarVisible = false } label: { Label("收起侧栏", systemImage: "sidebar.left") }
                    .accessibilityIdentifier("studioSidebarToggle")
                Button { section = .toolbox; toolboxPath = [] } label: { Label("工具箱", systemImage: "square.grid.2x2") }
                    .accessibilityIdentifier("toolboxTab")
                Button { section = .records } label: { Label("记录", systemImage: "folder") }
                    .accessibilityIdentifier("recordsTab")
            }
            ForEach(PocketScene.allCases) { scene in
                SwiftUI.Section(scene.title) {
                    ForEach(scene.tools) { tool in
                        Button {
                            section = .toolbox
                            toolboxPath = [.scene(scene), .tool(tool)]
                        } label: {
                            HStack {
                                Label(tool.title, systemImage: tool.symbol)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(toolboxPath.last == .tool(tool) && section == .toolbox ? Theme.burgundy : .primary)
                        }.accessibilityIdentifier("sidebar_" + tool.rawValue)
                    }
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
    static let wash = Color(red: 0.957, green: 0.914, blue: 0.906)
    static let line = Color(red: 0.925, green: 0.902, blue: 0.886)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image("LaunchIdentity").resizable().scaledToFit().frame(width: 148, height: 32)
                        .accessibilityLabel("棒球训练助手")
                    Spacer()
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle").frame(width: 44,height: 44) }
                        .accessibilityLabel("使用帮助")
                }
                Text("训练工具箱").font(.largeTitle.bold())
                let draft = fields.log(kind: .bullpen, id: nil)
                NavigationLink(value: ToolboxRoute.tool(.bullpenLog)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("投球记录", systemImage: PocketTool.bullpenLog.symbol).font(.caption)
                            Text(draft.flatMap { $0.name.isEmpty ? nil : $0.name } ?? "牛棚投球").font(.title2.bold()).foregroundStyle(.primary)
                            if let draft, !draft.pitches.isEmpty {
                                Text("\(draft.pitches.count) 球 · 好球率 \(draft.strikeRateText)").font(.subheadline.monospacedDigit())
                            }
                            Label(draft?.events.isEmpty == false ? "继续记球" : "开始记球", systemImage: "arrow.right").font(.subheadline.bold())
                        }
                        Spacer()
                        PitchLocationMap(pitches: draft?.pitches ?? [], viewpoint: viewpoint, readOnly: true) { _ in }
                            .frame(width: 100).allowsHitTesting(false).accessibilityHidden(true)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(PocketStyle.wash,in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityIdentifier("bullpenShortcut")
                Text("场边常用").font(.headline)
                HStack {
                    ForEach([PocketTool.battingLog, .tacticsBoard, .stopwatch]) { tool in
                        NavigationLink(value: ToolboxRoute.tool(tool)) {
                            Label(tool.title,systemImage: tool.symbol).font(.subheadline)
                                .frame(maxWidth: .infinity,minHeight: 46)
                        }.accessibilityIdentifier("shortcut_" + tool.rawValue)
                    }
                }
                Text("训练场景").font(.headline)
                VStack(spacing: 8) {
                    HStack(spacing: 8) { sceneLink(.personal); sceneLink(.team) }
                    sceneLink(.quick)
                }
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
                #if DEBUG
                NavigationLink("图片分享卡片 · 示例",value: ToolboxRoute.shareExample).font(.footnote).accessibilityIdentifier("shareCardExample")
                #endif
            }.padding(.horizontal,20).padding(.bottom,20).frame(maxWidth: 930).frame(maxWidth:.infinity)
        }.background(PocketStyle.paper).toolbar(.hidden,for:.navigationBar)
        .sheet(isPresented: $showHelp) { NavigationStack { HelpView().toolbar { Button("完成") { showHelp = false } } } }
    }

    private func sceneLink(_ scene: PocketScene) -> some View {
        NavigationLink(value: ToolboxRoute.scene(scene)) {
            HStack {
                Image(systemName: scene.symbol)
                Text(scene.title).font(.headline).foregroundStyle(.primary)
                Spacer(); Image(systemName:"arrow.up.right").font(.caption)
            }.padding(14).frame(maxWidth:.infinity,minHeight:54).background(.white,in:RoundedRectangle(cornerRadius:10))
            .overlay { RoundedRectangle(cornerRadius:10).stroke(PocketStyle.line) }
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
    let scene: PocketScene

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270))], spacing: 8) {
                ForEach(scene.tools) { tool in
                    NavigationLink(value: ToolboxRoute.tool(tool)) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: tool.symbol).font(.title2).foregroundStyle(Theme.burgundy)
                            Text(tool.title).font(.headline).foregroundStyle(.primary)
                            Text(tool.summary).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .overlay { RoundedRectangle(cornerRadius: 18).stroke(PocketStyle.line, lineWidth: 1) }
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).accessibilityIdentifier("tool_" + tool.rawValue)
                }
            }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(PocketStyle.paper)
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
    @State private var pendingDelete: UUID?
    @State private var deletionIssue: String?
    @State private var search = ""
    @State private var inspection: UUID?


    private var records: [PocketRecord] {
        PocketRecord.timeline(library: library, quick: tools, fields: fieldTools, plans: personalPlans, training: training)
            .filter { filter.includes($0) && (search.isEmpty || [$0.name,$0.tool.title,$0.summary ?? ""].contains { $0.localizedCaseInsensitiveContains(search) }) }
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 660
            HStack(spacing: 0) {
                recordList(wide: wide)
                if wide, let selected = records.first(where: { $0.id == inspection }) ?? records.first {
                    Divider()
                    VStack(alignment: .leading,spacing: 14) {
                        Image(systemName: selected.tool.symbol).font(.largeTitle).foregroundStyle(Theme.burgundy)
                        Text(selected.tool.title).font(.caption).foregroundStyle(.secondary)
                        Text(selected.name).font(.title2.bold())
                        if let summary = selected.summary { Text(summary) }
                        Text(selected.createdAt,style:.date).foregroundStyle(.secondary)
                        NavigationLink("打开记录", value:selected.id).buttonStyle(.borderedProminent)
                    }.padding(20).frame(maxWidth: 285,maxHeight:.infinity,alignment:.topLeading)
                }
            }
        }.background(PocketStyle.paper)
        .navigationTitle("记录")
    }

    private func recordList(wide: Bool) -> some View {
        List {
            Section {
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
                    Group {
                        if wide { Button { inspection = record.id } label: { row }.buttonStyle(.plain) }
                        else { NavigationLink(value: record.id) { row } }
                    }
                    .accessibilityIdentifier("record_" + record.id.uuidString)
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
        .searchable(text: $search,prompt:"搜索名称或工具")
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
