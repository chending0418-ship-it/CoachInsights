import SwiftUI
import AVKit

enum VideoLibraryMode {
    case analysis, comparison
    var title: String { self == .analysis ? "视频分析" : "动作对比" }
}

struct VideoLibraryView: View {
    let mode: VideoLibraryMode
    @EnvironmentObject private var library: LibraryStore
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
    @State private var pickedPhoto: NewVideoSelection?
    @State private var openImported=false
    @State private var importSelection:NewVideoSelection?
    @State private var importedSession:AnalysisSession?
    private var videos:[LibraryVideoItem] {
        guard let repository=library.repository,let all=try? repository.assets() else { return [] }
        return library.sessions.filter(matchesFilters).flatMap { session -> [LibraryVideoItem] in
            let ids=(try? session.snapshot().videoIDs) ?? []
            return all.filter { asset in
                ids.contains(asset.id) && (query.isEmpty || session.name.localizedCaseInsensitiveContains(query) || asset.originalName.localizedCaseInsensitiveContains(query))
            }.map { LibraryVideoItem(session: session, asset: $0) }
        }
    }
    private func matchesFilters(_ session: AnalysisSession) -> Bool {
        let days = period == "最近 7 天" ? -7 : -30
        let earliest = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? .distantPast
        return (sport == "全部" || session.sportValue == sport) && (period == "全部日期" || session.createdAt >= earliest)
    }
    private var filtered: [AnalysisSession] {
        library.sessions.filter { matchesFilters($0) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 690
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    NotebookHeading(title: mode == .comparison ? "选择第一段视频" : "本机视频资料库",
                                    detail: mode == .comparison ? "从本机资料库选择素材。" : "私教 · 素材与分析记录")
                    if mode == .analysis {
                        Button { showCreate = true } label: { Label("新建分析", systemImage: "plus") }
                            .fixedSize().buttonStyle(DocumentButtonStyle(primary: true)).accessibilityIdentifier("createSession")
                    }
                }.padding(.horizontal, wide ? 24 : 15).padding(.vertical, 14)
                HStack(alignment: .top, spacing: 0) {
                    libraryPanel(wide: wide)
                    if wide { sources.frame(width: min(290, geometry.size.width * 0.31)).padding(.trailing, 18) }
                }
            }.background(Notebook.paper)
        }.navigationDestination(isPresented: $openImported) {
            if let importedSession {
                if mode == .comparison {
                    ComparisonView(session: importedSession, initialVideoID: initialVideoID)
                } else {
                    SessionDetail(session: importedSession, initialVideoID: initialVideoID, onClose: {
                        initialVideoID = nil; openImported = false
                    })
                }
            }
        }
        .fileImporter(isPresented:$fileImport,allowedContentTypes:[.movie]) { result in
            switch result { case .success(let url):importSelection=NewVideoSelection(url:url)
            case .failure(let error):library.issue=error.localizedDescription }
        }
        .sheet(isPresented: $photoImport, onDismiss: {
            if let pickedPhoto { importSelection = pickedPhoto; self.pickedPhoto = nil }
        }) {
            PhotoImportView { result in
                switch result {
                case .success(let value): pickedPhoto = NewVideoSelection(url: value.url, timing: value.timing)
                case .failure(let error): if !(error is CancellationError) { library.issue = error.localizedDescription }
                }
                photoImport = false
            }
        }
        .notebookDestination(item: $importSelection) { value in
            NewVideoImportView(selection: value) { session in
            importedSession=session;initialVideoID=nil;importSelection=nil;openImported=true
        } }
        .navigationDestination(isPresented: $showCreate) { CreateSessionView { _ in } }
        .navigationDestination(isPresented: $showCapture) { CaptureView() }
        .alert("删除分析记录？", isPresented: Binding(get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let session = pendingDelete {
                    Task { await library.remove(session) }
                }
                pendingDelete = nil
            }
        } message: { Text("仅清理这份记录和不再被其他记录使用的本机副本。") }
    }
    private func videoCard(_ item:LibraryVideoItem,repository:LibraryRepository)->some View {
        VStack(alignment:.leading,spacing:6) {
            VideoCover(asset:item.asset,repository:repository).aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius:6))
            Text(item.asset.originalName).font(.subheadline.bold()).lineLimit(1).foregroundStyle(.primary)
            Text("\(item.session.name) · \(item.asset.createdAt.formatted(date:.abbreviated,time:.omitted))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private var sources: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("添加素材").font(.headline).padding(.vertical, 10)
            Rectangle().fill(Theme.burgundy).frame(height: 2)
            source("相册", "选择视频", "photo", "rootPhotos") { photoImport = true }
            source("文件", "选择文件", "folder", "rootFiles") { fileImport = true }
            if mode == .analysis { source("拍摄", "录制新动作", "video", "rootCapture") { showCapture = true } }
            if mode == .analysis {
            NavigationLink { HelpView() } label: { Label("使用说明与隐私", systemImage: "questionmark.circle") }.font(.caption).frame(minHeight: 44)
            #if DEBUG
            NavigationLink { ProbeView() } label: { Label("媒体技术验证", systemImage: "waveform.path.ecg") }
                .font(.caption).accessibilityIdentifier("openProbe")
            #endif
            }
        }
    }
    private func source(_ title: String, _ detail: String, _ icon: String, _ id: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack {
                    Image(systemName: icon).foregroundStyle(Theme.burgundy).frame(width: 28)
                    VStack(alignment: .leading) { Text(title).bold(); Text(detail).font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Image(systemName: "arrow.right").font(.caption)
                }.frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier(id)
            Divider()
        }
    }
    private func libraryPanel(wide: Bool) -> some View {
        List {
            VStack(alignment: .leading, spacing: 8) {
                if mode == .comparison { SourceSelectionStrip(first: nil, second: nil, choosingLeft: true) } else {
                Picker("浏览方式", selection: $browseVideos) {
                    Text("视频").tag(true)
                    Text("分析记录").tag(false)
                }.pickerStyle(.segmented).accessibilityIdentifier("libraryBrowseMode")
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索视频或分析名称", text: $query)
                        .submitLabel(.search).accessibilityIdentifier("librarySearch")
                    if !query.isEmpty {
                        Button("清除搜索", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                    }
                }.padding(.leading, 12).frame(minHeight: 44)
                    .background(Notebook.inset.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                HStack {
                    Picker("运动", selection: $sport) { ForEach(["全部", "打击", "投球"], id: \.self) { Text($0) } }
                        .accessibilityIdentifier("sportFilter")
                    Picker("日期", selection: $period) { ForEach(["全部日期", "最近 7 天", "最近 30 天"], id: \.self) { Text($0) } }
                }.pickerStyle(.menu)
                }
            }.listRowBackground(Theme.paper).listRowSeparator(.hidden)
            if let issue = library.issue {
                Section {
                    Text(issue).foregroundStyle(.red)
                    Button("重试") { Task { await library.retry() } }
                }
            }
            if browseVideos,!videos.isEmpty,let repository=library.repository {
                Section("视频 · \(videos.count)") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 16) {
                        ForEach(videos) { item in
                            Button {
                                openCompact(item.session, videoID: item.asset.id)
                            } label: {
                                videoCard(item, repository: repository)
                            }.buttonStyle(.plain).accessibilityIdentifier("videoCard_" + item.id)
                        }
                    }.padding(.vertical, 6)
                        .listRowSeparator(.hidden).listRowBackground(Theme.paper)
                }
            }
            let records = filtered.filter { !browseVideos || (try? $0.snapshot().videoIDs.isEmpty) == true }
            if !records.isEmpty || (filtered.isEmpty && (!browseVideos || videos.isEmpty)) {
                Section("分析记录 · \(records.count)") {
                    if filtered.isEmpty {
                        EmptyPanel(icon: "rectangle.stack", title: query.isEmpty ? (mode == .comparison ? "选择第一段视频" : "从一份分析开始") : "没有找到记录",
                                   detail: query.isEmpty ? (mode == .comparison ? "从相册或文件添加视频，再选择第二段动作。" : "先记录打击或投球，随后添加视频。") : "试试其他名称或筛选条件。")
                            .listRowBackground(Color.clear)
                    }
                    ForEach(records) { session in
                        Button { openCompact(session) } label: { SessionRow(session: session) }.buttonStyle(.plain)
                            .swipeActions { Button("删除", role: .destructive) { pendingDelete = session } }
                    }
                }
            }
            if !wide { sources.listRowBackground(Notebook.paper).listRowSeparator(.hidden) }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.paper)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
        .overlay { if library.busy { ProgressView("正在清理本机副本…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
    }
    private func openCompact(_ session:AnalysisSession,videoID:UUID?=nil) {
        initialVideoID=videoID;importedSession=session;openImported=true
    }
}

struct SessionRow: View {
    let name: String
    let sport: Sport
    let createdAt: Date

    init(session: AnalysisSession) {
        self.init(name: session.name, sport: session.sport, createdAt: session.createdAt)
    }
    init(name: String, sport: Sport, createdAt: Date) {
        self.name = name; self.sport = sport; self.createdAt = createdAt
    }
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: sport == .batting ? "figure.baseball" : "baseball")
                .font(.title2).frame(width: 44, height: 50)
                .foregroundStyle(Theme.burgundy).background(Theme.rose.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.headline).foregroundStyle(.primary)
                Text("\(sport.rawValue) · \(createdAt.formatted(date: .abbreviated, time: .omitted))")
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
    @State private var sport = Sport.pitching
    @State private var hand = "未指定"
    @State private var angle = "未指定"
    let created: (UUID) -> Void
    var body: some View {
        Group {
            ScrollView {
                NotebookColumns {
                    VStack(alignment: .leading, spacing: 16) {
                        NotebookHeading(title: "新建分析记录", detail: "可先建立记录，再添加素材。")
                        NotebookInput(title: "分析名称") { TextField("例如：周末投球练习", text: $name).accessibilityIdentifier("sessionName") }
                        NotebookInput(title: "运动类型") { Picker("运动类型", selection: $sport) { ForEach(Sport.allCases, id: \.self) { Text($0.rawValue) } }.labelsHidden() }
                        NotebookInput(title: "惯用手") { Picker("惯用手", selection: $hand) { ForEach(["未指定", "左手", "右手"], id: \.self) { Text($0) } }.labelsHidden() }
                        NotebookInput(title: "拍摄角度") { Picker("拍摄角度", selection: $angle) { ForEach(["未指定", "正面", "侧面", "后方"], id: \.self) { Text($0) } }.labelsHidden() }
                        Button("创建分析记录") {
                            if let session = library.create(
                                name: name, sport: sport, handedness: hand == "未指定" ? nil : hand, angle: angle == "未指定" ? nil : angle)
                            {
                                created(session.id); dismiss()
                            }
                        }.buttonStyle(NotebookActionStyle(prominent: true)).accessibilityIdentifier("confirmCreate")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        NotebookHeading(title: "记录内容", detail: "素材、关键帧与绘图保存在这份本机分析记录中，可从训练记录重新打开。")
                    }.notebookPanel()
                }.padding()
            }.background(Notebook.paper).notebookPageTitle("新建分析")
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
    @State private var sport=Sport.pitching
    @State private var busy=false
    @State private var progress=0.0
    @State private var issue:String?
    @State private var task:Task<Void,Never>?
    var body:some View {
        Group {
            ScrollView {
                NotebookColumns {
                    VStack(alignment: .leading, spacing: 12) {
                        NotebookHeading(title: "导入视频", detail: selection.url.lastPathComponent)
                        ImportMoviePreview(url: selection.url)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("导入选项").font(.headline)
                        Label(selection.url.deletingPathExtension().lastPathComponent, systemImage: "film").lineLimit(2)
                        Picker("运动类型", selection: $sport) { ForEach(Sport.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(
                            .segmented
                        ).disabled(busy)
                        Text("导入后自动创建分析记录，可随时重命名。").font(.caption).foregroundStyle(.secondary)
                        if busy { ProgressView("复制到本机…", value: progress) }
                        if let issue { Text(issue).foregroundStyle(.red) }
                        Button(busy ? "正在导入…" : "打开并分析") { start() }.buttonStyle(NotebookActionStyle(prominent: true)).disabled(busy)
                            .accessibilityIdentifier("confirmNewImport")
                    }.notebookPanel()
                }.padding()
            }.background(Notebook.paper).notebookPageTitle("导入视频") {
                task?.cancel(); if !busy { dismiss() }
            }
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

private struct ImportMoviePreview: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Label("无法预览此素材", systemImage: "film").foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }.aspectRatio(16 / 9, contentMode: .fit).task(id: url) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1024, height: 768)
            do { image = UIImage(cgImage: try await generator.image(at: .zero).image) } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
