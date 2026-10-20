import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SessionDetail: View {
    @EnvironmentObject private var library: LibraryStore
    let session: AnalysisSession
    @State private var name = ""
    @State private var renaming = false
    @State private var importing = false
    @State private var busy = false
    @State private var issue: String?
    @State private var assetInfos: [(VideoAsset, MediaMetadata, URL?)] = []
    @State private var relinkAsset: VideoAsset?
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(session.sportValue, systemImage: "figure.baseball")
                    Spacer()
                    Text("本机保存").foregroundStyle(.secondary)
                }.font(.subheadline)
                if assetInfos.isEmpty {
                    EmptyPanel(icon: "video.badge.plus", title: "添加分析素材",
                               detail: "先关联本机视频，保留原片和逐帧信息。\n慢放、标注与姿态工具准备中。")
                }
                ForEach(assetInfos, id: \.0.id) { asset, metadata, url in
                    VStack(alignment: .leading, spacing: 10) {
                        if let url { VideoPreview(url: url).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 12)) }
                        else {
                            Label("素材缺失", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            Button("重新关联原片") { relinkAsset = asset; importing = true }
                        }
                        Text(asset.originalName).font(.headline)
                        Text("\(Int(metadata.displayWidth)) × \(Int(metadata.displayHeight)) · \(metadata.codec) · \(metadata.timeline.frames.count) 帧")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                Button("关联本机视频", systemImage: "folder.badge.plus") { relinkAsset = nil; importing = true }
                    .buttonStyle(.borderedProminent).disabled(busy || library.repository == nil)
                if busy { ProgressView("正在安全复制并读取帧时间…") }
                if let issue { Text(issue).foregroundStyle(.red); Button("重试") { importing = true } }
                NavigationLink { ComparisonView(session: session) } label: { FeatureCard(icon: "rectangle.split.2x1", title: "双视频对比", detail: "选择两路素材与动作同步点") }
                NavigationLink { ExportView(session: session) } label: { FeatureCard(icon: "square.and.arrow.up", title: "导出分析", detail: "截图、单视频与双路合成") }
                Text("1.0 · 基础模块预览").font(.caption).foregroundStyle(.secondary)
            }.padding().frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Theme.paper)
        .navigationTitle(session.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("重命名", systemImage: "pencil") { name = session.name; renaming = true }.accessibilityIdentifier("renameSession")
            Button("删除记录", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier("deleteSession")
        }
        .alert("删除分析记录？", isPresented: $deleting) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { Task { await library.remove(session); dismiss() } }
        } message: { Text("清理这份记录与未被其他记录使用的本机副本。") }
        .alert("重命名", isPresented: $renaming) {
            TextField("分析名称", text: $name)
            Button("保存") { library.rename(session, name: name) }
            Button("取消", role: .cancel) {}
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
            Task {
                busy = true; defer { busy = false }
                do {
                    let url = try result.get()
                    guard let repository = library.repository else { throw StorageFailure.invalidRecord }
                    if let relinkAsset { try await repository.relink(url, asset: relinkAsset) }
                    else { _ = try await repository.importVideo(url, into: session) }
                    issue = nil; await refresh()
                } catch { issue = error.localizedDescription }
            }
        }
        .task(id: session.id) { await refresh() }
    }
    @MainActor private func refresh() async {
        do {
            guard let repository = library.repository else { return }
            let snapshot = try session.snapshot()
            var infos: [(VideoAsset, MediaMetadata, URL?)] = []
            for asset in try repository.assets() where snapshot.videoIDs.contains(asset.id) {
                infos.append((asset, try asset.metadata(), try? await repository.files.existingURL(asset.relativePath)))
            }
            assetInfos = infos
        } catch { issue = error.localizedDescription }
    }
}

struct VideoPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PlayerSurface {
        let view = PlayerSurface()
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.playerLayer.player = AVPlayer(url: url)
        return view
    }
    func updateUIView(_ view: PlayerSurface, context: Context) {
        if (view.playerLayer.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            view.playerLayer.player = AVPlayer(url: url)
        }
    }
    static func dismantleUIView(_ view: PlayerSurface, coordinator: ()) {
        view.playerLayer.player?.pause(); view.playerLayer.player = nil
    }
}
struct FeatureCard: View {
    let icon: String, title: String, detail: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.burgundy)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }.padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
