import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: UUID?
    @State private var query = ""
    @State private var sport = "全部"
    @State private var period = "全部日期"
    @State private var showCreate = false
    @State private var showCapture = false
    @State private var pendingDelete: AnalysisSession?
    private var filtered: [AnalysisSession] {
        library.sessions.filter { session in
            (query.isEmpty || session.name.localizedCaseInsensitiveContains(query))
            && (sport == "全部" || session.sportValue == sport)
            && (period == "全部日期" || session.createdAt >= Calendar.current.date(
                byAdding: .day, value: period == "最近 7 天" ? -7 : -30, to: Date())!)
        }
    }
    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    libraryPanel
                } detail: {
                    NavigationStack {
                        if let session = library.sessions.first(where: { $0.id == selection }) {
                            SessionDetail(session: session)
                        } else {
                            EmptyPanel(icon: "viewfinder", title: "让每一帧都有发现",
                                       detail: "从左侧打开记录，或新建一份分析。\n所有素材与分析仅保存在这台设备。")
                        }
                    }
                }
            } else {
                NavigationStack { libraryPanel }
            }
        }
        .sheet(isPresented: $showCreate) { CreateSessionView { selection = $0 } }
        .sheet(isPresented: $showCapture) { NavigationStack { CaptureView() } }
        .alert("删除分析记录？", isPresented: Binding(get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let session = pendingDelete {
                    if selection == session.id { selection = nil }
                    Task { await library.remove(session) }
                }
                pendingDelete = nil
            }
        } message: { Text("仅清理这份记录和不再被其他记录使用的本机副本。") }
        .task { await library.retry() }
    }
    private var libraryPanel: some View {
        List(selection: $selection) {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("COACH INSIGHTS").font(.caption.weight(.black)).tracking(3).foregroundStyle(Theme.burgundy)
                    Text("看清动作的每个细节").font(.title2.weight(.bold))
                    Label("本机资料库", systemImage: "iphone.and.arrow.forward")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button { showCreate = true } label: { Label("新建分析", systemImage: "plus") }
                            .labelStyle(.titleOnly).lineLimit(1)
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("createSession")
                        Button { showCapture = true } label: { Label("拍摄", systemImage: "video") }
                            .buttonStyle(.bordered).accessibilityIdentifier("rootCapture")
                    }
                }.padding(.vertical, 8)
            }.listRowBackground(Theme.paper)
            if let issue = library.issue {
                Section {
                    Text(issue).foregroundStyle(.red)
                    Button("重试") { Task { await library.retry() } }
                }
            }
            Section {
                Picker("运动", selection: $sport) {
                    ForEach(["全部", "打击", "投球"], id: \.self) { Text($0) }
                }.accessibilityIdentifier("sportFilter")
                Picker("日期", selection: $period) {
                    ForEach(["全部日期", "最近 7 天", "最近 30 天"], id: \.self) { Text($0) }
                }
            }
            Section("分析记录 · \(filtered.count)") {
                if filtered.isEmpty {
                    EmptyPanel(icon: "rectangle.stack", title: query.isEmpty ? "从一份分析开始" : "没有找到记录",
                               detail: query.isEmpty ? "先记录打击或投球，随后添加视频。" : "试试其他名称或筛选条件。")
                        .listRowBackground(Color.clear)
                }
                ForEach(filtered) { session in
                    if sizeClass == .regular {
                        NavigationLink(value: session.id) { SessionRow(session: session) }
                            .listRowBackground(selection == session.id ? Theme.rose.opacity(0.3) : Color.clear)
                            .contextMenu { Button("删除记录", role: .destructive) { pendingDelete = session } }
                    } else {
                        NavigationLink { SessionDetail(session: session) } label: { SessionRow(session: session) }
                            .swipeActions { Button("删除", role: .destructive) { pendingDelete = session } }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.paper)
        .navigationTitle("素材库")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { NavigationLink { HelpView() } label: { Label("使用说明与隐私", systemImage: "questionmark.circle") } }
            #if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ProbeView() } label: {
                    Label("媒体技术验证", systemImage: "waveform.path.ecg")
                }.accessibilityIdentifier("openProbe")
            }
            #endif
        }
        .searchable(text: $query, prompt: "搜索分析名称")
        .overlay { if library.busy { ProgressView("正在清理本机副本…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
    }
}

struct SessionRow: View {
    let session: AnalysisSession
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session.sport == .batting ? "figure.baseball" : "baseball")
                .font(.title2).frame(width: 44, height: 50)
                .foregroundStyle(Theme.burgundy).background(Theme.rose.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(session.name).font(.headline).foregroundStyle(.primary)
                Text("\(session.sportValue) · \(session.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 5)
    }
}

struct EmptyPanel: View {
    let icon: String, title: String, detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 38, weight: .light)).foregroundStyle(Theme.burgundy)
            Text(title).font(.title3.bold())
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(30)
    }
}

struct CreateSessionView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sport = Sport.batting
    @State private var hand = "未指定"
    @State private var angle = "未指定"
    let created: (UUID) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("分析记录") {
                    TextField("例如：周末打击练习", text: $name).accessibilityIdentifier("sessionName")
                    Picker("运动类型", selection: $sport) { ForEach(Sport.allCases, id: \.self) { Text($0.rawValue) } }
                }
                Section("可选信息") {
                    Picker("惯用手", selection: $hand) { ForEach(["未指定", "左手", "右手"], id: \.self) { Text($0) } }
                    Picker("拍摄角度", selection: $angle) { ForEach(["未指定", "正面", "侧面", "后方"], id: \.self) { Text($0) } }
                }
                Section { Label("只保存在当前设备", systemImage: "internaldrive").foregroundStyle(.secondary) }
            }
            .navigationTitle("新建分析").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        if let session = library.create(name: name, sport: sport,
                            handedness: hand == "未指定" ? nil : hand, angle: angle == "未指定" ? nil : angle) {
                            created(session.id); dismiss()
                        }
                    }.accessibilityIdentifier("confirmCreate")
                }
            }
        }
    }
}
