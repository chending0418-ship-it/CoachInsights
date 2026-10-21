import SwiftUI
import Photos
import AVKit

struct ExportView:View {
    let session:AnalysisSession
    var initialVideoID:UUID? = nil
    var initialComparison=false
    @EnvironmentObject private var library:LibraryStore
    @Environment(\.scenePhase) private var phase
    @State private var videoID:UUID?
    @State private var assets:[VideoAsset]=[]
    @State private var compare=false
    @State private var includePose=true
    @State private var audio=false
    @State private var rate:Double=0.25
    @State private var progress:Double=0
    @State private var busy=false
    @State private var resultURL:URL?
    @State private var sharing=false
    @State private var issue:String?
    @State private var notice:String?
    @State private var task:Task<Void,Never>?
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("分享动作里的发现").font(.title2.bold())
                if !assets.isEmpty {
                    Picker("单视频素材",selection:$videoID) { ForEach(assets) { Text($0.originalName).lineLimit(1).truncationMode(.middle).tag(Optional($0.id)) } }.disabled(busy)
                    Toggle("双视频同屏合成",isOn:$compare).disabled(busy)
                    Toggle("包含可见骨架和角度",isOn:$includePose).disabled(busy)
                    if !compare {
                        Picker("视频速度",selection:$rate) { ForEach([1.0,0.5,0.25,0.1,0.05],id:\.self) { Text("\($0.formatted())×").tag($0) } }.disabled(busy)
                        Toggle("保留原声（仅 1×）",isOn:$audio).disabled(busy || rate != 1)
                        Button("导出当前帧截图",systemImage:"photo") { run(screenshot:true) }.buttonStyle(.bordered).disabled(busy).accessibilityIdentifier("exportScreenshot")
                    }
                    Button(compare ? "导出同屏视频":"导出慢放视频",systemImage:"film") { run(screenshot:false) }.buttonStyle(.borderedProminent).disabled(busy).accessibilityIdentifier("exportVideo")
                    Text(compare ? "按已保存的布局、同步点和对比速度导出，无声。":"选定片段按展示时间导出。慢放结果无声；1× 可选保留原声。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("兼容格式：H.264 · SDR · 30 fps；横画面最长边 1920，竖画面最长边 1920。画面保留原比例，不覆盖原片。")
                        .font(.caption).foregroundStyle(.secondary)
                } else { EmptyPanel(icon:"square.and.arrow.up",title:"添加视频后导出",detail:"回到分析记录，先导入或拍摄一段视频。") }
                if busy { ProgressView("正在本机导出…",value:progress);Button("取消导出",role:.cancel){task?.cancel()}.accessibilityIdentifier("cancelExport") }
                if let resultURL {
                    if resultURL.pathExtension=="png",let image=UIImage(contentsOfFile:resultURL.path) { Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:300) }
                    else { VideoPlayer(player:AVPlayer(url:resultURL)).frame(height:240) }
                    HStack {
                        Button("分享 / 存储到文件",systemImage:"square.and.arrow.up") { sharing=true }.accessibilityIdentifier("shareExport")
                        Button("保存到相册",systemImage:"square.and.arrow.down") { Task { await savePhoto(resultURL) } }
                    }.buttonStyle(.bordered)
                    Text("导出完成").accessibilityIdentifier("exportComplete")
                }
                if let notice { Text(notice).font(.caption) }
                if let issue { Text(issue).foregroundStyle(.red);Button("重试") { run(screenshot:false) } }
            }.padding().frame(maxWidth:850).frame(maxWidth:.infinity)
        }.background(Theme.paper).navigationTitle("导出分析").navigationBarTitleDisplayMode(.inline)
        .task {
            do { let ids=try session.snapshot().videoIDs;assets=try library.repository?.assets().filter{ids.contains($0.id)} ?? [];videoID=assets.first(where:{$0.id==initialVideoID})?.id ?? assets.first?.id; compare=initialComparison; if let id=videoID { rate=try session.snapshot().playbackRates[id.uuidString] ?? 0.25 } }
            catch { issue=error.localizedDescription }
        }
        .onChange(of:videoID) { _,id in if let id { rate=(try? session.snapshot().playbackRates[id.uuidString]) ?? 0.25 } }
        .sheet(isPresented:$sharing) { if let resultURL { ShareSheet(url:resultURL) } }
        .onDisappear { task?.cancel() }
        .onChange(of:phase) { _,value in if value == .background { task?.cancel();notice="应用进入后台，已取消导出；可以返回重试。" } }
    }
    private func run(screenshot:Bool) {
        guard let repository=library.repository else { return };busy=true;progress=0;resultURL=nil;issue=nil
        task=Task {
            defer { busy=false }
            do {
                let recipe=try await ExportBuilder.recipe(session:session,repository:repository,videoID:videoID,compare:compare,rate:rate,pose:includePose,audio:audio)
                let directory=repository.files.root.appendingPathComponent("Cache/Exports")
                let service=ExportService()
                if screenshot {
                    let snapshot=try session.snapshot(),time=snapshot.playheads[recipe.left.id.uuidString]?.seconds ?? recipe.start
                    resultURL=try await service.screenshot(source:recipe.left,time:time,size:recipe.size,directory:directory)
                } else {
                    resultURL=try await service.video(recipe:recipe,directory:directory) { value in Task { @MainActor in progress=value } }
                }
            } catch is CancellationError { notice="已取消导出，未完成文件已清理。" }
            catch { issue=error.localizedDescription }
        }
    }
    private func savePhoto(_ url:URL) async {
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
