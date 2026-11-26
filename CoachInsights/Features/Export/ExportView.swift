import SwiftUI
import Photos
import AVKit

struct ExportView:View {
    let session:AnalysisSession
    var initialVideoID:UUID? = nil
    var initialComparison=false
    var initialPose=true
    var initialAnnotations=true
    @State private var includeAnnotations=true
    @State private var lastScreenshot=false
    @EnvironmentObject private var library:LibraryStore
    @Environment(\.scenePhase) private var phase
    @State private var videoID:UUID?
    @State private var assets:[VideoAsset]=[]
    @State private var compare=false
    @State private var includePose=true
    @State private var audio=false
    @State private var rate:Double=1
    @State private var progress:Double=0
    @State private var busy=false
    @State private var resultURL:URL?
    @State private var sharing=false
    @State private var issue:String?
    @State private var notice:String?
    @State private var task:Task<Void,Never>?
    private var summaryRate:Double { compare ? ((try? session.snapshot().comparison?.rate) ?? 1) : rate }
    @State private var resultSummary: String?
    @State private var comparisonAvailable = false
    private var rangeSummary: String {
        guard let snapshot = try? session.snapshot() else { return "无法读取片段" }
        if compare {
            guard let setup = snapshot.comparison else { return "请选择两段素材" }
            let clock = ComparisonClock(
                leftAnchor: setup.leftAnchor.seconds, rightAnchor: setup.rightAnchor.seconds,
                leftRange: setup.leftClip.start.seconds...setup.leftClip.end.seconds,
                rightRange: setup.rightClip.start.seconds...setup.rightClip.end.seconds)
            guard let range = clock.commonRange else { return "没有共同片段" }
            return String(format: "%.2f – %.2f s", range.lowerBound, range.upperBound)
        }
        guard let asset = assets.first(where: { $0.id == videoID }), let metadata = try? asset.metadata() else { return "—" }
        let clip = snapshot.clips[asset.id.uuidString]
        return String(
            format: "%.2f – %.2f s", clip?.start.seconds ?? metadata.timeline.frames.first?.presentationTime.seconds ?? 0,
            clip?.end.seconds ?? metadata.timeline.duration.seconds)
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                NotebookHeading(title: resultURL == nil ? "导出分析" : "导出预览已就绪", detail: session.name)
                if resultURL == nil, !assets.isEmpty {
                    NotebookColumns(leadingFraction: 0.54) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let id = videoID, let asset = assets.first(where: { $0.id == id }), let repository = library.repository {
                            VideoCover(asset: asset, repository: repository).aspectRatio(16/9, contentMode: .fit)
                                    .frame(maxWidth: .infinity).clipped()
                        }
                            Text("视频信息").font(.headline)
                            Divider()
                            LabeledContent("输出范围", value: rangeSummary)
                            LabeledContent("视频格式", value: "H.264 · SDR · 30 fps")
                        }.notebookPanel()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("输出设置").font(.headline)
                        Picker("单视频素材",selection:$videoID) { ForEach(assets) { Text($0.originalName).lineLimit(1).truncationMode(.middle).tag(Optional($0.id)) } }.disabled(busy)
                        Toggle("双视频同屏合成",isOn:$compare).disabled(busy || !comparisonAvailable)
                        if !comparisonAvailable {
                            Text("先在动作对比中选择两段视频，再导出同屏视频。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("包含可见绘图标注",isOn:$includeAnnotations).disabled(busy)
                        Toggle("包含可见骨架和角度（辅助估算）",isOn:$includePose).disabled(busy)
                        if includePose {
                            Text(PoseGuidance.exportNotice).font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("exportPoseLimitations")
                        }
                    if !compare {
                        Picker("视频速度",selection:$rate) { ForEach([1.0,0.5,0.25,0.1,0.05],id:\.self) { Text("\($0.formatted())×").tag($0) } }.disabled(busy)
                        Toggle("保留原声（仅 1×）",isOn:$audio).disabled(busy || rate != 1)
                        Button("导出当前帧截图",systemImage:"photo") { run(screenshot:true) }.buttonStyle(NotebookActionStyle()).disabled(busy).accessibilityIdentifier("exportScreenshot")
                    }
                            Button(compare ? "导出同屏视频" : "导出慢放视频", systemImage: "film") { run(screenshot: false) }.buttonStyle(
                                NotebookActionStyle(prominent: true)
                            ).disabled(busy).accessibilityIdentifier("exportVideo")
                    Text(compare ? "按已保存的布局、同步点和对比速度导出，无声。":"选定片段按展示时间导出。慢放结果无声；1× 可选保留原声。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("导出摘要：\(compare ? "双视频同屏":"当前素材") · \(summaryRate.formatted())× · \(includePose ? "包含可见分析图层":"不含人体图层")").font(.caption).foregroundStyle(.secondary)
                        }.notebookPanel()
                    }
                } else if assets.isEmpty { EmptyPanel(icon:"square.and.arrow.up",title:"添加视频后导出",detail:"回到分析记录，先导入或拍摄一段视频。") }
                if busy { ProgressView("正在本机导出…",value:progress);Button("取消导出",role:.cancel){task?.cancel()}.accessibilityIdentifier("cancelExport") }
                if let resultURL {
                    NotebookColumns {
                        VStack(alignment: .leading, spacing: 12) {
                            if resultURL.pathExtension == "png", let image = UIImage(contentsOfFile: resultURL.path) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 520)
                            } else {
                                ReviewMovie(url: resultURL).aspectRatio(16/9, contentMode: .fit).frame(maxHeight: 360)
                            }
                            Text("视频信息").font(.headline)
                            Divider()
                            Text(resultSummary ?? session.name).font(.subheadline)
                        }.notebookPanel()
                        VStack(alignment: .leading, spacing: 14) {
                            Text("去向").font(.headline)
                            Button("分享 / 存储到文件", systemImage: "square.and.arrow.up") { sharing = true }.buttonStyle(
                                NotebookActionStyle(prominent: true)
                            ).accessibilityIdentifier("shareExport")
                        Button("保存到相册",systemImage:"square.and.arrow.down") { Task { await savePhoto(resultURL) } }
                    Label("导出完成", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Notebook.fieldGreen).accessibilityIdentifier("exportComplete")
                    Button("调整导出设置") { self.resultURL = nil; notice = nil; issue = nil }
                        }.notebookPanel()
                    }
                }
                if let notice { Text(notice).font(.caption) }
                if let issue {
                    Text(issue).foregroundStyle(.red)
                    if let resultURL { Button("重试保存到相册") { Task { await savePhoto(resultURL) } } }
                    else { Button("重试导出") { run(screenshot:lastScreenshot) } }
                }
            }.padding().frame(maxWidth: 1160).frame(maxWidth: .infinity)
        }.background(Theme.paper).notebookPageTitle(resultURL == nil ? "导出设置" : "导出结果")
        .task {
            includePose=initialPose;includeAnnotations=initialAnnotations
            do {
                let snapshot = try session.snapshot()
                assets = try library.repository?.assets().filter { snapshot.videoIDs.contains($0.id) } ?? []
                let ids = Set(assets.map(\.id))
                if let setup = snapshot.comparison {
                    comparisonAvailable = setup.leftVideoID != setup.rightVideoID && ids.contains(setup.leftVideoID) && ids.contains(setup.rightVideoID)
                }
                videoID = assets.first(where: { $0.id == initialVideoID })?.id ?? assets.first?.id
                compare = initialComparison && comparisonAvailable
                if let id = videoID { rate = snapshot.playbackRates[id.uuidString] ?? 1 }
            }
            catch { issue=error.localizedDescription }
        }
        .onChange(of:videoID) { _,id in if let id { rate=(try? session.snapshot().playbackRates[id.uuidString]) ?? 1 } }
        .sheet(isPresented:$sharing) { if let resultURL { ShareSheet(url:resultURL) } }
        .onDisappear { task?.cancel() }
        .onChange(of:phase) { _,value in if value == .background { task?.cancel();notice="应用进入后台，已取消导出；可以返回重试。" } }
    }
    private func run(screenshot:Bool) {
        lastScreenshot=screenshot
        guard let repository=library.repository else { return };busy=true;progress=0;resultURL=nil;issue=nil
        task=Task {
            defer { busy=false }
            do {
                let recipe=try await ExportBuilder.recipe(session:session,repository:repository,videoID:videoID,compare:compare,rate:rate,pose:includePose,audio:audio,annotations:includeAnnotations)
                let directory=repository.files.root.appendingPathComponent("Cache/Exports")
                let service=ExportService()
                if screenshot {
                    let snapshot=try session.snapshot(),time=snapshot.playheads[recipe.left.id.uuidString]?.seconds ?? recipe.start
                    resultSummary =
                        "\(assets.first { $0.id == recipe.left.id }?.originalName ?? session.name) · \(String(format: "%.2f", time)) s · PNG"
                    resultURL=try await service.screenshot(source:recipe.left,time:time,size:recipe.size,directory:directory)
                } else {
                    let sources = [recipe.left.id, recipe.right?.id].compactMap { id in assets.first { $0.id == id }?.originalName }.joined(
                        separator: " + ")
                    resultSummary = "\(sources) · \(rangeSummary) · \(recipe.rate.formatted())× · H.264 · 30 fps"
                    resultURL=try await service.video(recipe:recipe,directory:directory) { value in Task { @MainActor in progress=value } }
                }
            } catch is CancellationError { notice="已取消导出，未完成文件已清理。" }
            catch { issue=error.localizedDescription }
        }
    }
    private func savePhoto(_ url:URL) async {
        issue = nil
        let status=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
        guard status == .authorized || status == .limited else { issue="未允许保存到相册，可使用分享菜单存储到文件。";return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if url.pathExtension=="png" { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL:url) }
                else { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:url) }
            };notice="已保存到相册。"
        } catch { issue=error.localizedDescription }
    }
}
struct ShareSheet:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIActivityViewController {
        let controller=UIActivityViewController(activityItems:[url],applicationActivities:nil)
        return controller
    }
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context) {}
}
