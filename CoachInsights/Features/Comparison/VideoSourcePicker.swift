import SwiftUI
import UniformTypeIdentifiers

struct VideoSourcePicker:View {
    let repository:LibraryRepository
    let targetSession:AnalysisSession
    var excluding:UUID?
    var selected:(UUID)->Void
    var onCancel:()->Void
    @State private var candidates:[VideoAsset]=[]
    @State private var photos=false
    @State private var files=false
    @State private var busy=false
    @State private var progress=0.0
    @State private var issue:String?
    @State private var task:Task<Void,Never>?
    var body:some View {
        NavigationStack {
            List {
                Section("选择第二段来源") {
                    Button("相册",systemImage:"photo.on.rectangle") { photos=true }.accessibilityIdentifier("comparisonPhotos")
                    Button("文件",systemImage:"folder") { files=true }.accessibilityIdentifier("comparisonFiles")
                }.disabled(busy)
                Section("本机资料库") {
                    if candidates.isEmpty { Text("没有其他视频，可从相册或文件添加。").foregroundStyle(.secondary) }
                    ForEach(candidates) { asset in
                        Button { attach(asset) } label: {
                            HStack { VideoCover(asset:asset,repository:repository).frame(width:80,height:55).clipped();VStack(alignment:.leading) { Text(asset.originalName).lineLimit(2);Text(asset.createdAt.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(.secondary) } }
                        }.disabled(busy).accessibilityIdentifier("chooseVideo_"+asset.id.uuidString)
                    }
                }
                if busy { Section { ProgressView("导入到本机…",value:progress);Button("取消导入") { task?.cancel() } } }
                if let issue { Section { Text(issue).foregroundStyle(.red);Text("请重新选择素材重试。").font(.caption) } }
            }.navigationTitle("选择第二段视频").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("取消") { task?.cancel();onCancel() }.accessibilityIdentifier("cancelVideoPicker") }
            .task { do { candidates=try repository.assets().filter{$0.id != excluding}.sorted{$0.createdAt>$1.createdAt} } catch { issue=error.localizedDescription } }
            .fileImporter(isPresented:$files,allowedContentTypes:[.movie]) { result in switch result { case .success(let url):importVideo(url);case .failure(let error):issue=error.localizedDescription } }
            .sheet(isPresented:$photos) { PhotoImportView { result in photos=false;switch result { case .success(let value):importVideo(value.url,timing:value.timing);case .failure(let error):if !(error is CancellationError) { issue=error.localizedDescription } } } }
            .onDisappear { task?.cancel() }
        }
    }
    private func attach(_ asset:VideoAsset) {
        do { try repository.attach(asset.id,into:targetSession);selected(asset.id) } catch { issue=error.localizedDescription }
    }
    private func importVideo(_ url:URL,timing:MediaMetadata?=nil) {
        busy=true;issue=nil;progress=0
        task=Task { @MainActor in
            defer { busy=false }
            do {
                let asset=try await repository.importVideo(url,into:targetSession,timing:timing) { value in Task { @MainActor in progress=value } }
                guard asset.id != excluding else { issue="请选择另一段视频。";return }
                selected(asset.id)
            } catch is CancellationError { issue="已取消导入，可重新选择。" } catch { issue=error.localizedDescription }
        }
    }
}

struct VideoCover:View {
    let asset:VideoAsset
    let repository:LibraryRepository
    @State private var image:UIImage?
    var body:some View {
        ZStack(alignment:.bottomTrailing) {
            Color(white:0.15)
            if let image { Image(uiImage:image).resizable().scaledToFill() }
            else { Image(systemName:"video").foregroundStyle(.white.opacity(0.6)).frame(maxWidth:.infinity,maxHeight:.infinity) }
            if let info=try? asset.metadata() { Text("\(Int(info.timeline.duration.seconds)/60):\(String(format:"%02d",Int(info.timeline.duration.seconds)%60))").font(.caption2.monospacedDigit()).padding(4).background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:4)).foregroundStyle(.white).padding(4) }
        }.clipped().task(id:asset.id) {
            do {
                let metadata=try asset.metadata(),url=try await repository.files.existingURL(asset.relativePath)
                let local=try await LocalMedia.asset(url:url,metadata:metadata)
                let store=repository.thumbnails
                let value=try await store.image(contentHash:asset.contentHash,frame:0,provider:FrameProvider(asset:local,metadata:metadata,maximumDimension:240,costLimit:1024*1024))
                guard !Task.isCancelled else { return };image=value
            } catch { image=nil }
        }
    }
}
