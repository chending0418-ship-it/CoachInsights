import SwiftUI
import UniformTypeIdentifiers

struct VideoSourcePicker:View {
    let repository:LibraryRepository
    let targetSession:AnalysisSession
    var choosingLeft = false
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
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    SourceSelectionStrip(first: choosingLeft ? nil : otherName, second: choosingLeft ? otherName : nil, choosingLeft: choosingLeft)
                    NotebookColumns {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("本机资料库").font(.headline)
                            if candidates.isEmpty { Text("没有其他视频，可从相册或文件添加。").foregroundStyle(.secondary) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 14) {
                                ForEach(candidates) { asset in
                                    Button { attach(asset) } label: {
                                        VStack(alignment: .leading) {
                                            VideoCover(asset: asset, repository: repository).aspectRatio(16/9, contentMode: .fit)
                                            Text(asset.originalName).lineLimit(2)
                                        }
                                    }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("chooseVideo_"+asset.id.uuidString)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text("从其他位置添加").font(.headline)
                            Button("相册",systemImage:"photo.on.rectangle") { photos=true }.accessibilityIdentifier("comparisonPhotos")
                            Button("文件",systemImage:"folder") { files=true }.accessibilityIdentifier("comparisonFiles")
                        }.notebookPanel().disabled(busy)
                    }
                    if busy { ProgressView("导入到本机…",value:progress);Button("取消导入") { task?.cancel() } }
                    if let issue { Text(issue).foregroundStyle(.red) }
                }.padding()
            }.background(Notebook.paper).navigationTitle(choosingLeft ? "选择第一段视频" : "选择第二段视频").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("取消") { task?.cancel();onCancel() }.accessibilityIdentifier("cancelVideoPicker") }
            .task { do { candidates=try repository.assets().filter{$0.id != excluding}.sorted{$0.createdAt>$1.createdAt} } catch { issue=error.localizedDescription } }
            .fileImporter(isPresented:$files,allowedContentTypes:[.movie]) { result in switch result { case .success(let url):importVideo(url);case .failure(let error):issue=error.localizedDescription } }
            .sheet(isPresented:$photos) { PhotoImportView { result in photos=false;switch result { case .success(let value):importVideo(value.url,timing:value.timing);case .failure(let error):if !(error is CancellationError) { issue=error.localizedDescription } } } }
            .onDisappear { task?.cancel() }
        }
    }
    private var otherName: String? {
        guard let excluding else { return nil }
        return (try? repository.assets())?.first { $0.id == excluding }?.originalName
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
        Color(white: 0.15)
            .overlay {
                if let image {
                    GeometryReader { geometry in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: "video").foregroundStyle(.white.opacity(0.6))
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let info = try? asset.metadata() {
                    let seconds = Int(info.timeline.duration.seconds)
                    Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.white)
                        .padding(4).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .task(id: asset.id) {
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

struct SourceSelectionStrip: View {
    let first: String?
    let second: String?
    let choosingLeft: Bool
    var body: some View {
        HStack {
            ForEach([true, false], id: \.self) { left in
                VStack(alignment: .leading, spacing: 4) {
                    Text(left ? "A" : "B").font(.caption.bold()).foregroundStyle(Theme.burgundy)
                    Text((left ? first : second) ?? (left == choosingLeft ? "请选择素材" : "等待选择")).font(.subheadline).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading).notebookPanel()
            }
        }
    }
}
