import SwiftUI

private enum RecordRoute: Hashable {
    case inspect(UUID), open(UUID)
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var tools: QuickToolsStore
    private enum Section { case toolbox, records }
    @State private var section = Section.toolbox
    @State private var toolboxPath: [ToolboxRoute] = []
    @State private var recordPath: [RecordRoute] = []
    @State private var recordFilter = PocketRecordFilter()
    @State private var directory = false
    @State private var sidebarVisible = true
    @State private var mediaWorkspaceFocused = false
    @State private var mediaNavigationHidden = false

    private var showsTabs: Bool {
        #if DEBUG
        if section == .toolbox && toolboxPath.last == .shareExample { return false }
        #endif
        if section == .records { return recordPath.isEmpty }
        if toolboxPath.last == .help { return false }
        if case .tool = toolboxPath.last { return false }
        return true
    }
    private var isBoard: Bool {
        if section == .toolbox { return toolboxPath.last == .tool(.tacticsBoard) }
        guard case .open(let id) = recordPath.last else { return false }
        return tools.state.boards.contains { $0.id == id }
    }

    var body: some View {
        GeometryReader { geometry in
            let studio = geometry.size.width >= 900
            HStack(spacing: 0) {
                if studio && sidebarVisible && !isBoard && !mediaWorkspaceFocused {
                    studioSidebar.frame(width: 195)
                    Divider()
                }
                content(studioLayout: studio)
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
        .environment(\.openNotebookDirectory, { directory = true })
        .sheet(isPresented: $directory) {
            NavigationStack {
                List {
                    ForEach(PocketScene.allCases) { scene in
                        SwiftUI.Section(scene.title) {
                            ForEach(scene.tools) { tool in
                                Button {
                                    section = .toolbox
                                    toolboxPath = [.scene(scene), .tool(tool)]
                                    directory = false
                                } label: { Label(tool.title, systemImage: tool.symbol) }
                            }
                        }
                    }
                }.listStyle(.plain).navigationTitle("页面目录").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("完成") { directory = false } }
            }
        }
        .task { await library.retry() }
    }

    private func content(studioLayout: Bool) -> some View {
        Group {
            if section == .toolbox {
                NavigationStack(path: $toolboxPath) {
                    ToolboxHomeView(studio: sidebarVisible && studioLayout) { id in
                        recordFilter = PocketRecordFilter(); recordPath = id.map { [.open($0)] } ?? []; section = .records
                    }
                        .navigationDestination(for: ToolboxRoute.self) { route in
                            Group {
                                switch route {
                                case .help: HelpView()
                                case .scene(let scene):
                                    ToolSceneView(scene: scene) { id in
                                        recordFilter = PocketRecordFilter(scene: scene)
                                        recordPath = id.map { [.open($0)] } ?? []
                                        section = .records
                                    }
                                case .tool(let tool): ToolDestinationView(tool: tool)
                                #if DEBUG
                                case .shareExample: ShareCardExampleView()
                                #endif
                                }
                            }
                            .modifier(ToolRouteHeader(route: route, studio: studioLayout, mediaHidden: mediaNavigationHidden,
                                                      back: { if toolboxPath.last == route { _ = toolboxPath.popLast() } },
                                                      directory: { directory = true }))
                        }
                }
            } else {
                NavigationStack(path: $recordPath) {
                    PocketRecordsView(filter: $recordFilter, openRecord: { recordPath.append(.open($0)) },
                                      inspectRecord: { recordPath.append(.inspect($0)) },
                                      closeInspection: { if !recordPath.isEmpty { _ = recordPath.popLast() } },
                                      returnHome: { section = .toolbox; toolboxPath = [] })
                }
            }
        }
    }

    private var tabs: some View {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 0) {
                        tab("工具箱", symbol: "square.grid.2x2", section: .toolbox, identifier: "toolboxTab")
                        tab("训练记录", symbol: "folder", section: .records, identifier: "recordsTab")
                    }.padding(.top, 8).padding(.bottom, 4)
                }.background(.white)
    }

    private var studioSidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image("LaunchIdentityLight").resizable().scaledToFit().frame(width: 149, height: 36)
                .accessibilityLabel("棒球训练助手").padding(.horizontal, 6).padding(.bottom, 18)
            railButton("工具箱", "square.grid.2x2", "toolboxTab", section == .toolbox && toolboxPath.isEmpty) {
                section = .toolbox; toolboxPath = []
            }
            railButton("训练记录", "folder", "recordsTab", section == .records) { section = .records }
            Text("训练场景").font(.caption).foregroundStyle(.secondary).padding(.leading, 12).padding(.top, 22)
            ForEach(PocketScene.allCases) { scene in
                let active = section == .toolbox && toolboxPath.contains(.scene(scene))
                railButton(scene.title, scene.symbol, "sidebarScene_" + scene.rawValue, active) {
                    section = .toolbox; toolboxPath = [.scene(scene)]
                }
            }
            Spacer(minLength: 8)
            railButton("使用帮助", "questionmark.circle", "studioHelp", section == .toolbox && toolboxPath.last == .help) { section = .toolbox; toolboxPath = [.help] }
            railButton("页面目录", "square.grid.2x2", "studioDirectory", false) { directory = true }
            railButton("收起侧栏", "sidebar.left", "studioSidebarToggle", false) { sidebarVisible = false }
        }.padding(.horizontal, 12).padding(.vertical, 14).frame(maxHeight: .infinity)
            .background(Color(red: 244/255, green: 242/255, blue: 235/255))
            .accessibilityElement(children: .contain).accessibilityIdentifier("studioSidebar")
    }

    private func railButton(_ title: String, _ icon: String, _ id: String, _ active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(active ? .bold : .medium))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(minHeight: 45)
                .foregroundStyle(active ? Theme.burgundy : Notebook.ink)
                .background(active ? Color(red: 231/255, green: 221/255, blue: 216/255) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id).accessibilityAddTraits(active ? .isSelected : [])
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

private struct ToolRouteHeader: ViewModifier {
    let route: ToolboxRoute
    let studio: Bool
    let mediaHidden: Bool
    let back: () -> Void
    let directory: () -> Void

    private var labels: (String, String)? {
        switch route {
        case .help: ("工具箱", "使用帮助")
        case .scene(let scene): ("工具箱", scene.title)
        case .tool(.tacticsBoard): nil
        case .tool(.videoAnalysis): ("私教", "视频资料库")
        case .tool(.motionComparison): ("私教", "对比选片")
        case .tool(let tool): (tool.scene.title, tool.title)
        #if DEBUG
        case .shareExample: nil
        #endif
        }
    }
    @ViewBuilder func body(content: Content) -> some View {
        if let labels {
            content.safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ZStack {
                        Text(labels.1).font(.headline).accessibilityAddTraits(.isHeader)
                        HStack {
                            Button(action: back) {
                                Label(studio ? labels.0 : "返回", systemImage: "chevron.left")
                            }.accessibilityIdentifier("notebookBack")
                            Spacer()
                            Button(action: directory) { Image(systemName: "square.grid.2x2").frame(width: 44, height: 44) }
                                .accessibilityLabel("页面目录")
                        }.font(.subheadline.weight(.semibold)).padding(.leading, 12).foregroundStyle(Theme.burgundy)
                    }.frame(minHeight: 44)
                    Rectangle().fill(Notebook.rule).frame(height: 1)
                }.background(Notebook.paper)
            }.toolbar(.hidden, for: .navigationBar)
        } else {
            content.toolbar(route == .tool(.tacticsBoard) || mediaHidden ? .hidden : .visible, for: .navigationBar)
        }
    }
}

private func recentRecordRow(_ record: PocketRecord) -> some View {
    NotebookToolRow(title: record.name, detail: record.tool.title, icon: record.tool.symbol)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Notebook.paper, in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Notebook.rule) }
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
    var studio = false
    let showRecords: (UUID?) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date.now.formatted(.dateTime.month().day().weekday(.wide))).font(.caption).foregroundStyle(.secondary)
                    Text("训练工具箱").font(.largeTitle.bold())
                }
                NotebookColumns(minimumWidth: 680, leadingFraction: 0.69) {
                    fieldSection
                    shortcuts(vertical: geometry.size.width >= 720 && geometry.size.height >= 500)
                }
                scenes
                recentSection
                #if DEBUG
                NavigationLink("图片分享卡片 · 示例",value: ToolboxRoute.shareExample).font(.footnote).accessibilityIdentifier("shareCardExample")
                #endif
            }.padding(.horizontal, studio ? 26 : 15).padding(.top, 16).padding(.bottom,20).frame(maxWidth: 1120).frame(maxWidth:.infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !studio {
                VStack(spacing: 0) {
                HStack {
                    Image("LaunchIdentityLight").resizable().scaledToFit().frame(width: 148, height: 32)
                        .accessibilityLabel("棒球训练助手")
                    Spacer()
                    NavigationLink(value: ToolboxRoute.help) { Label("帮助", systemImage: "questionmark.circle").font(.subheadline).frame(minHeight: 44) }
                        .accessibilityLabel("使用帮助")
                }
                    .padding(.horizontal, 15)
                    Divider()
                }.background(Notebook.paper)
            }
        }
        .background(PocketStyle.paper).toolbar(.hidden,for:.navigationBar)
    }

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let draft = fields.log(kind: .bullpen, id: nil)
            NavigationLink(value: ToolboxRoute.tool(.bullpenLog)) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("投球记录", systemImage: PocketTool.bullpenLog.symbol).font(.caption)
                        Text(draft.flatMap { $0.name.isEmpty ? nil : $0.name } ?? "牛棚投球").lineLimit(2).font(.title2.bold()).foregroundStyle(.primary)
                        if let draft, !draft.pitches.isEmpty {
                            Text("\(draft.pitches.count) 球 / \(draft.strikeCount) 好球").font(.subheadline.monospacedDigit())
                        }
                        Label(draft?.events.isEmpty == false ? "继续记球" : "开始记球", systemImage: "arrow.right").font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(.white).background(Theme.burgundy, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 0)
                }.padding(.leading, studio ? 20 : 14).padding(.vertical, 15)
                .frame(maxWidth: .infinity, minHeight: studio ? 168 : 148, alignment: .leading)
                .background(alignment: .trailing) {
                    GeometryReader { card in
                        let mapWidth = card.size.width * 0.425
                        PitchLocationMap(pitches: draft?.pitches ?? [], viewpoint: viewpoint, readOnly: true,
                                         ratio: mapWidth / max(1, card.size.height)) { _ in }
                            .frame(width: mapWidth, height: card.size.height)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
                .background(PocketStyle.wash).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Notebook.rule) }
            }.buttonStyle(.plain).accessibilityIdentifier("bullpenShortcut")
        }
    }
    private func shortcuts(vertical: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("场边常用").font(.headline)
            let flow = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 5))
            flow {
                ForEach([PocketTool.battingLog, .tacticsBoard, .stopwatch]) { tool in
                    NavigationLink(value: ToolboxRoute.tool(tool)) {
                        Label(tool.title, systemImage: tool.symbol).font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 46, alignment: vertical ? .leading : .center)
                            .padding(.horizontal, vertical ? 9 : 0)
                    }.buttonStyle(.plain).foregroundStyle(Theme.burgundy)
                        .overlay(alignment: .bottom) {
                            if vertical { Divider() }
                            else { RoundedRectangle(cornerRadius: 7).strokeBorder(Notebook.rule) }
                        }
                        .accessibilityIdentifier("shortcut_" + tool.rawValue)
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
                    recentRecordRow(record)
                }.buttonStyle(.plain)
            }
        }
    }

    private func sceneLink(_ scene: PocketScene) -> some View {
        NavigationLink(value: ToolboxRoute.scene(scene)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: scene.symbol).font(.subheadline).foregroundStyle(Theme.burgundy)
                    Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                }
                Text(scene.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if studio { Text(scene.tools.prefix(2).map(\.title).joined(separator: "、") + "等").font(.caption).foregroundStyle(.secondary) }
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
                VStack(alignment: .leading, spacing: 5) {
                    Text("训练场景").font(.caption).foregroundStyle(.secondary)
                    Text(scene.title).font(.title.bold())
                    Text(scene.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: twoColumns ? 2 : 1), alignment: .leading, spacing: 10) {
                    ForEach(scene.tools) { tool in
                        NavigationLink(value: ToolboxRoute.tool(tool)) {
                            NotebookToolRow(title: tool.title, detail: tool.summary, icon: tool.symbol)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Notebook.rule) }
                        }.buttonStyle(.plain).accessibilityIdentifier("tool_" + tool.rawValue)
                    }
                }
                let recent = PocketRecord.timeline(library: library, quick: quick, fields: fields, plans: plans, training: training)
                    .filter { $0.scene == scene }.prefix(3)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("相关记录").font(.headline); Spacer(); Button("查看记录") { openRecord(nil) } }
                    if recent.isEmpty { Text("这个场景的训练记录将显示在这里。").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(recent) { record in
                        Button { openRecord(record.id) } label: {
                            recentRecordRow(record)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, twoColumns ? 24 : 15).padding(.vertical, 17).frame(maxWidth: 1040).frame(maxWidth: .infinity)
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
    var inspectRecord: (UUID) -> Void = { _ in }
    var closeInspection: () -> Void = {}
    var returnHome: () -> Void = {}
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
            let visibleRecords = records
            let selected = visibleRecords.first(where: { $0.id == inspection }) ?? visibleRecords.first
            VStack(alignment: .leading, spacing: 0) {
                filters.padding(.horizontal, wide ? 24 : 15).padding(.vertical, 12)
                HStack(alignment: .top, spacing: 0) {
                recordList(wide: wide, records: visibleRecords, selectedID: selected?.id)
                if wide, let selected {
                    Divider()
                    VStack(alignment: .leading) {
                        Button("打开详情", systemImage: "arrow.up.right") { inspectRecord(selected.id) }.padding(.horizontal, 16)
                        RecordInspection(record: selected, open: { openRecord(selected.id) },
                                     delete: { pendingDelete = selected.id })
                    }.frame(width: geometry.size.width * 0.42)
                }
                }
            }
        }.background(PocketStyle.paper)
        .notebookPageTitle("训练记录", back: returnHome)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotebookHeading(title: "训练记录", detail: "按名称、场景或工具查找已保存的训练。")
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索名称或工具", text: $search).submitLabel(.search)
                    if !search.isEmpty { Button("清除", systemImage: "xmark.circle.fill") { search = "" }.labelStyle(.iconOnly) }
                }
                    .padding(.horizontal, 10).frame(minHeight: 44).background(Notebook.inset, in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 5) {
                ForEach([nil] + PocketScene.allCases.map(Optional.some), id: \.self) { scene in
                    let selected = filter.scene == scene
                    Button(scene?.title ?? "全部") { filter.selectScene(scene) }
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 40)
                        .foregroundStyle(selected ? Color.white : Notebook.ink)
                        .background(selected ? Theme.burgundy : Notebook.paper, in: RoundedRectangle(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? .clear : Notebook.rule) }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Menu {
                    Picker("工具类型", selection: $filter.tool) {
                        Text("全部工具").tag(PocketTool?.none)
                        ForEach(filter.tools) { Text($0.title).tag(Optional($0)) }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 42, height: 42) }
                .accessibilityLabel(filter.tool?.title ?? "全部工具").accessibilityIdentifier("recordToolFilter")
            }.accessibilityElement(children: .contain).accessibilityIdentifier("recordSceneFilter")
        }
    }

    private func recordList(wide: Bool, records: [PocketRecord], selectedID: UUID?) -> some View {
        List {
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
                    let row = NotebookToolRow(title: record.name, detail: record.tool.title + " · " + record.createdAt.formatted(date: .abbreviated, time: .omitted), icon: record.tool.symbol)
                    HStack(spacing: 6) {
                        Button {
                            if wide { inspection = record.id } else { openRecord(record.id) }
                        } label: {
                            row.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(record.name + "，" + record.tool.title).accessibilityIdentifier("record_" + record.id.uuidString)
                        if !wide {
                            Button { inspectRecord(record.id) } label: {
                                Image(systemName: "info.circle").frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel("记录详情，" + record.name)
                        }
                    }
                    .listRowBackground(wide && record.id == selectedID ? Notebook.inset : Color.white)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if !wide { Button("详情", systemImage: "info.circle") { inspectRecord(record.id) }.tint(Theme.burgundy) }
                    }
                    .contextMenu {
                        if !wide { Button("记录详情", systemImage: "info.circle") { inspectRecord(record.id) } }
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
        .listStyle(.plain).scrollContentBackground(.hidden).background(PocketStyle.paper)
        .navigationDestination(for: RecordRoute.self) { route in
            switch route {
            case .inspect(let id):
                if let record = records.first(where: { $0.id == id }) {
                    RecordInspection(record: record, open: { openRecord(id) }, delete: {
                        closeInspection(); pendingDelete = id
                    }).notebookPageTitle("记录详情")
                }
            case .open(let id): recordDestination(id)
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
    @ViewBuilder private func recordDestination(_ id: UUID) -> some View {

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

}

struct RecordInspection: View {
    @EnvironmentObject private var library: LibraryStore
    let record: PocketRecord
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.scene.title + " / " + record.tool.title).font(.caption).foregroundStyle(.secondary)
                    Text(record.name).font(.title.bold())
                }
                Divider()
                let session = library.sessions.first { $0.id == record.id }
                if let session, let repository = library.repository, let ids = try? session.snapshot().videoIDs,
                   let asset = try? repository.assets().first(where: { ids.contains($0.id) }) {
                    VideoCover(asset: asset, repository: repository).aspectRatio(16/9, contentMode: .fit)
                }
                LabeledContent("训练内容", value: record.summary ?? session?.sportValue ?? record.tool.title)
                LabeledContent("最近更新") { Text((session?.updatedAt ?? record.createdAt).formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("保存位置", value: "本机记录")
                Divider()
                HStack {
                    Button(action: open) { Label("打开记录", systemImage: "arrow.up.right") }.buttonStyle(DocumentButtonStyle(primary: true))
                    Button(role: .destructive, action: delete) { Label("删除记录", systemImage: "trash") }
                        .buttonStyle(DocumentButtonStyle()).accessibilityIdentifier("deleteInspectedRecord")
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity).background(Theme.paper)
    }
}
