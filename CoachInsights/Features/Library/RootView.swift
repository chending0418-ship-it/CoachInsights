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
    @State private var initialVideoID:UUID?
    @State private var browseVideos=true
    @State private var fileImport=false
    @State private var photoImport=false
    @State private var openImported=false
    @State private var importSelection:NewVideoSelection?
    @State private var importedSession:AnalysisSession?
    private var usesSplit:Bool { sizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    private var videos:[LibraryVideoItem] {
        guard let repository=library.repository,let all=try? repository.assets() else { return [] }
        return filtered.flatMap { session -> [LibraryVideoItem] in
            let ids=(try? session.snapshot().videoIDs) ?? []
            return all.filter{ids.contains($0.id)}.map{LibraryVideoItem(session:session,asset:$0)}
        }
    }
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
            if usesSplit {
                NavigationSplitView {
                    libraryPanel
                } detail: {
                    NavigationStack {
                        if let session = library.sessions.first(where: { $0.id == selection }) {
                            SessionDetail(session: session,initialVideoID:initialVideoID,onClose:{selection=nil;initialVideoID=nil}).id(session.id.uuidString + (initialVideoID?.uuidString ?? ""))
                        } else {
                            EmptyPanel(icon: "viewfinder", title: "让每一帧都有发现",
                                       detail: "从左侧打开记录，或新建一份分析。\n所有素材与分析仅保存在这台设备。")
                        }
                    }
                }
            } else {
                NavigationStack { libraryPanel.navigationDestination(isPresented:$openImported) { if let importedSession { SessionDetail(session:importedSession,initialVideoID:initialVideoID,onClose:{selection=nil;initialVideoID=nil;openImported=false}) } } }
            }
        }
        .fileImporter(isPresented:$fileImport,allowedContentTypes:[.movie]) { result in
            switch result { case .success(let url):importSelection=NewVideoSelection(url:url)
            case .failure(let error):library.issue=error.localizedDescription }
        }
        .sheet(isPresented:$photoImport) { PhotoImportView { result in photoImport=false;switch result {
            case .success(let value):importSelection=NewVideoSelection(url:value.url,timing:value.timing)
            case .failure(let error):if !(error is CancellationError) { library.issue=error.localizedDescription }
        } } }
        .sheet(item:$importSelection) { value in NewVideoImportView(selection:value) { session in
            importedSession=session;selection=session.id;initialVideoID=nil;importSelection=nil
            if !usesSplit { openImported=true }
        } }
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
        .onChange(of:sizeClass) { _,value in
            guard UIDevice.current.userInterfaceIdiom == .pad else { return }
            if value == .compact,let session=library.sessions.first(where:{$0.id==selection}) {
                importedSession=session;openImported=true
            } else if value == .regular { openImported=false }
        }
        .task { await library.retry() }
    }
    private func videoCard(_ item:LibraryVideoItem,repository:LibraryRepository)->some View {
        VStack(alignment:.leading,spacing:6) {
            VideoCover(asset:item.asset,repository:repository).frame(height:110).clipShape(RoundedRectangle(cornerRadius:10))
            Text(item.session.name).font(.subheadline.bold()).lineLimit(1).foregroundStyle(.primary)
            Text("\(item.session.sportValue) · \(item.asset.createdAt.formatted(date:.abbreviated,time:.omitted))").font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children:.combine).accessibilityIdentifier("videoCard_"+item.id)
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
                        Button("相册",systemImage:"photo.on.rectangle") { photoImport=true }.buttonStyle(.borderedProminent).accessibilityIdentifier("rootPhotos")
                        Button("文件",systemImage:"folder") { fileImport=true }.buttonStyle(.bordered).accessibilityIdentifier("rootFiles")
                    }
                    HStack {
                        Button { showCreate = true } label: { Label("新建分析", systemImage: "plus") }
                            .labelStyle(.titleOnly).lineLimit(1)
                            .buttonStyle(.bordered).accessibilityIdentifier("createSession")
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
            Section {
                Picker("浏览方式",selection:$browseVideos) { Text("视频").tag(true);Text("分析记录").tag(false) }.pickerStyle(.segmented).accessibilityIdentifier("libraryBrowseMode")
            }
            if browseVideos,!videos.isEmpty,let repository=library.repository {
                Section("视频 · \(videos.count)") {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:130),spacing:12)],spacing:16) {
                        ForEach(videos) { item in
                            Group {
                                if usesSplit {
                                    Button { selection=item.session.id;initialVideoID=item.asset.id } label: { videoCard(item,repository:repository) }
                                } else { Button { openCompact(item.session,videoID:item.asset.id) } label: { videoCard(item,repository:repository) } }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical,6)
                }
            }
            Section("分析记录 · \(filtered.count)") {
                if filtered.isEmpty {
                    EmptyPanel(icon: "rectangle.stack", title: query.isEmpty ? "从一份分析开始" : "没有找到记录",
                               detail: query.isEmpty ? "先记录打击或投球，随后添加视频。" : "试试其他名称或筛选条件。")
                        .listRowBackground(Color.clear)
                }
                ForEach(filtered.filter { !browseVideos || (try? $0.snapshot().videoIDs.isEmpty) == true }) { session in
                    if usesSplit {
                        Button { selection=session.id;initialVideoID=nil } label: { SessionRow(session:session) }.buttonStyle(.plain)
                            .listRowBackground(selection == session.id ? Theme.rose.opacity(0.3) : Color.clear)
                            .contextMenu { Button("删除记录", role: .destructive) { pendingDelete = session } }
                    } else {
                        Button { openCompact(session) } label: { SessionRow(session: session) }.buttonStyle(.plain)
                            .swipeActions { Button("删除", role: .destructive) { pendingDelete = session } }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.paper)
        .navigationTitle("素材库").navigationBarTitleDisplayMode(.inline)
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
    private func openCompact(_ session:AnalysisSession,videoID:UUID?=nil) {
        selection=session.id;initialVideoID=videoID;importedSession=session;openImported=true
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

struct LibraryVideoItem:Identifiable {
    let session:AnalysisSession
    let asset:VideoAsset
    var id:String { session.id.uuidString+asset.id.uuidString }
}
struct NewVideoSelection:Identifiable {
    let id=UUID()
    let url:URL
    var timing:MediaMetadata?=nil
}
struct NewVideoImportView:View {
    let selection:NewVideoSelection
    var completed:(AnalysisSession)->Void
    @EnvironmentObject private var library:LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var sport=Sport.batting
    @State private var busy=false
    @State private var progress=0.0
    @State private var issue:String?
    @State private var task:Task<Void,Never>?
    var body:some View {
        NavigationStack {
            Form {
                Section { Text(selection.url.deletingPathExtension().lastPathComponent).lineLimit(2)
                    Picker("运动类型",selection:$sport) { ForEach(Sport.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(busy)
                    Text("导入后自动创建分析记录，可随时重命名。").font(.caption).foregroundStyle(.secondary)
                }
                if busy { ProgressView("复制到本机…",value:progress) }
                if let issue { Text(issue).foregroundStyle(.red) }
                Button(busy ? "正在导入…":"打开并分析") { start() }.disabled(busy).accessibilityIdentifier("confirmNewImport")
            }.navigationTitle("导入视频").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("取消") { task?.cancel();if !busy { dismiss() } } }
            .interactiveDismissDisabled(busy)
            .onDisappear { task?.cancel() }
        }
    }
    private func start() {
        guard let repository=library.repository else { return };busy=true;issue=nil
        task=Task { @MainActor in
            var created:AnalysisSession?
            do {
                let session=try repository.create(name:selection.url.deletingPathExtension().lastPathComponent,sport:sport);created=session
                _=try await repository.importVideo(selection.url,into:session,timing:selection.timing) { value in Task { @MainActor in progress=value } }
                try Task.checkCancellation();library.reload();busy=false;completed(session)
            } catch {
                if let created { try? await repository.delete(created) };library.reload();busy=false
                if error is CancellationError { dismiss() } else { issue=error.localizedDescription }
            }
        }
    }
}
