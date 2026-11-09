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
        return section == .toolbox ? toolboxPath.count < 2 : recordPath.isEmpty
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
                    studioSidebar.frame(width: 244)
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
                    ToolboxHomeView()
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
                Text("Drill Buddy").font(.caption).foregroundStyle(.secondary)
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
                                if !tool.isAvailable { Text("待完善").font(.caption2).foregroundStyle(.secondary) }
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
    static let paper = Color(red: 0.980, green: 0.973, blue: 0.961)
    static let wash = Color(red: 0.957, green: 0.914, blue: 0.906)
    static let line = Color(red: 0.925, green: 0.902, blue: 0.886)
    static let navy = Color(red: 0.043, green: 0.098, blue: 0.200)
}

private struct ToolboxHomeView: View {
    @ScaledMetric(relativeTo: .title2) private var cardHeight: CGFloat = 266

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    (Text("Baseball").fontWeight(.heavy) + Text("Master.cc").fontWeight(.regular))
                        .font(.custom("Arial", size: 13)).tracking(-0.585).foregroundStyle(PocketStyle.navy)
                    Text("棒球训练助手").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Capsule().fill(Theme.burgundy).frame(width: 30, height: 3)
                }
                Text("选择本次带训场景").font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        sceneCard(.personal, height: cardHeight)
                        sceneCard(.team, height: cardHeight)
                    }
                    sceneCard(.quick, height: nil)
                }
                #if DEBUG
                NavigationLink("图片分享卡片 · 示例", value: ToolboxRoute.shareExample)
                    .font(.footnote).foregroundStyle(Theme.burgundy).accessibilityIdentifier("shareCardExample")
                #endif
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(PocketStyle.paper)
        .navigationTitle("棒球训练助手")
        .toolbar(.hidden, for: .navigationBar)
    }

    private func sceneCard(_ scene: PocketScene, height: CGFloat?) -> some View {
        NavigationLink(value: ToolboxRoute.scene(scene)) {
            Group {
                if scene == .quick {
                    HStack(spacing: 18) {
                        sceneIcon(scene)
                        sceneCopy(scene)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").foregroundStyle(Theme.burgundy)
                    }.padding(22).frame(minHeight: 148)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        sceneIcon(scene)
                        sceneCopy(scene).padding(.top, 28)
                        Spacer(minLength: 24)
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(Theme.burgundy).frame(maxWidth: .infinity, alignment: .trailing)
                    }.padding(20).frame(height: height)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scene == .quick ? PocketStyle.wash : .white, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(PocketStyle.line, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scene.title)
        .accessibilityIdentifier("scene_" + scene.rawValue)
    }

    private func sceneIcon(_ scene: PocketScene) -> some View {
        Image(systemName: scene.symbol).font(.system(size: 23, weight: .regular))
            .foregroundStyle(Theme.burgundy).frame(width: 46, height: 46)
            .background(scene == .quick ? .white : PocketStyle.wash, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    private func sceneCopy(_ scene: PocketScene) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scene.title).font(scene == .quick ? .title2.bold() : .title.bold()).foregroundStyle(.primary)
            Text(scene.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ToolSceneView: View {
    let scene: PocketScene

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(scene.tools) { tool in
                    NavigationLink(value: ToolboxRoute.tool(tool)) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: tool.symbol).font(.title2).foregroundStyle(Theme.burgundy)
                            Text(tool.title).font(.headline).foregroundStyle(.primary)
                            Text(tool.summary).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !tool.isAvailable { Text("待完善").font(.caption2).foregroundStyle(Theme.burgundy) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
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
        case .stopwatch: StopwatchView()
        case .countdown: CountdownView()
        case .tacticsBoard: TacticsBoardView(recordID: nil)
        case .distance: DistanceView()
        case .battingLog: FieldLogView(kind: .batting)
        case .bullpenLog: FieldLogView(kind: .bullpen)
        case .gameCounter: FieldLogView(kind: .game)
        default:
            VStack(spacing: 18) {
                Image(systemName: tool.symbol).font(.system(size: 42)).foregroundStyle(Theme.burgundy)
                Text(tool.title).font(.title2.bold())
                Text(tool.summary).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("内容待完善").font(.footnote).foregroundStyle(Theme.burgundy)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(PocketStyle.wash, in: Capsule())
            }
            .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PocketStyle.paper)
            .navigationTitle(tool.title).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("pendingTool_" + tool.rawValue)
        }
    }
}

private struct PocketRecordsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var tools: QuickToolsStore
    @EnvironmentObject private var fieldTools: FieldToolsStore
    @Binding var filter: PocketRecordFilter
    @State private var pendingDelete: UUID?

    private var records: [PocketRecord] {
        let video = library.busy ? [] : library.sessions.map(PocketRecord.init)
        return (video + tools.state.boards.map(PocketRecord.init) + tools.state.distances.map(PocketRecord.init)
                + fieldTools.state.records.map(PocketRecord.init(fieldLog:)))
            .filter(filter.includes).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
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
            Section {
                if records.isEmpty {
                    EmptyPanel(icon: "folder", title: "没有符合筛选条件的记录", detail: "保存的资料会显示在这里，也可以试试其他场景或工具类型。")
                        .listRowBackground(Color.clear)
                }
                ForEach(records) { record in
                    NavigationLink(value: record.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(record.scene.title + " · " + record.tool.title).font(.caption).foregroundStyle(Theme.burgundy)
                            if record.sport == nil {
                                Text(record.name).font(.headline)
                                if let summary = record.summary { Text(summary).font(.caption).foregroundStyle(.secondary) }
                                Text(record.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            } else if let sport = record.sport { SessionRow(name: record.name, sport: sport, createdAt: record.createdAt) }
                        }.padding(.vertical, 4)
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
        .scrollContentBackground(.hidden).background(PocketStyle.paper)
        .navigationTitle("记录")
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
                    else { tools.removeRecord(id) }
                }
                pendingDelete = nil
            }
        } message: { Text("删除这份本机记录。已保存到相册的图片会保留；其他记录引用的视频会保留。") }
    }
}
