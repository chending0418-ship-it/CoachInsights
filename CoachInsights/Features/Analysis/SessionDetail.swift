import SwiftUI
import UniformTypeIdentifiers

struct SessionDetail: View {
    @EnvironmentObject private var library: LibraryStore
    let session: AnalysisSession
    @State private var workspace: AnalysisWorkspace?
    @State private var name = ""
    @State private var renaming = false
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let workspace { AnalysisEditor(workspace: workspace) }
            else { ProgressView("打开本机分析…") }
        }
        .navigationTitle(session.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("重命名", systemImage: "pencil") { name = session.name; renaming = true }.accessibilityIdentifier("renameSession")
            Button("删除记录", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier("deleteSession")
        }
        .alert("删除分析记录？", isPresented: $deleting) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { Task { workspace?.pause(); await library.remove(session); dismiss() } }
        } message: { Text("清理这份记录与未被其他记录使用的本机副本。") }
        .alert("重命名", isPresented: $renaming) {
            TextField("分析名称", text: $name)
            Button("保存") { library.rename(session, name: name) }
            Button("取消", role: .cancel) {}
        }
        .task(id: session.id) {
            if let repository = library.repository {
                let value = AnalysisWorkspace(session: session, repository: repository)
                workspace = value; await value.reload()
            }
        }
        .onDisappear { workspace?.stopAndSave() }
    }
}

struct AnalysisEditor: View {
    @ObservedObject var workspace: AnalysisWorkspace
    @State private var importing = false
    @State private var photos = false
    @State private var capture = false
    @State private var keyframeName = ""
    @State private var showKeyframe = false
    @State private var showPose = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var w: AnalysisWorkspace { workspace }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !w.assets.isEmpty {
                        Picker("当前素材", selection: Binding(get: { w.selectedVideoID ?? w.assets[0].id }, set: { id in Task { await w.select(id) } })) {
                            ForEach(w.assets) { Text($0.originalName).lineLimit(1).truncationMode(.middle).tag($0.id) }
                        }.accessibilityIdentifier("videoSelection")
                    }
                    if let metadata = w.metadata {
                        AnalysisCanvas(workspace: w)
                            .frame(height: max(190, min(geometry.size.height * 0.5, sizeClass == .regular ? 480 : 330)))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("\(Int(metadata.displayWidth)) × \(Int(metadata.displayHeight)) · 第 \(w.frameIndex + 1) / \(metadata.timeline.frames.count) 帧 · \(w.time, specifier: "%.3f") s")
                            .font(.caption.monospacedDigit()).accessibilityIdentifier("frameReadout")
                        playbackControls
                        drawingControls
                        Text("已保存 \(w.snapshot.annotations.count) 个标注 · \(w.snapshot.keyframes.count) 个关键帧").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("annotationCount")
                        HStack {
                            Button("关键帧", systemImage: "bookmark") { w.pause(); showKeyframe = true }.accessibilityIdentifier("addKeyframe")
                            Spacer()
                            Button("人体分析", systemImage: "figure.stand") { w.pause(); showPose = true }.accessibilityIdentifier("poseTools")
                        }.buttonStyle(.bordered)
                        if let pose=w.currentPose {
                            Text("关节点覆盖 \(pose.joints.filter { $0.name != "nose" }.count) / 12 · 角度为画面估算，请复核点位")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        keyframes
                    } else {
                        EmptyPanel(icon: "video.badge.plus", title: "添加分析素材", detail: "拍摄或导入视频，逐帧看清动作。\n原片与分析仅保存在当前设备。")
                    }
                    importControls
                    if w.busy {
                        ProgressView("正在复制到本机…", value: w.progress)
                        Button("取消导入", role: .cancel) { w.importTask?.cancel() }
                    }
                    if let notice = w.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if let saveIssue=w.saveIssue { Text("保存失败："+saveIssue).foregroundStyle(.red);Button("重试保存") { w.save() } }
                    if let issue = w.issue {
                        Text(issue).font(.callout).foregroundStyle(.red)
                        HStack {
                            Button("重试读取") { Task { await w.reload() } }
                            Button("重新关联原片") { importing = true }
                        }
                    }
                    NavigationLink { ComparisonView(session: w.session) } label: { FeatureCard(icon: "rectangle.split.2x1", title: "双视频对比", detail: "两路画面 · 动作同步 · 联动慢放") }
                    NavigationLink { ExportView(session: w.session, initialVideoID:w.selectedVideoID) } label: { FeatureCard(icon: "square.and.arrow.up", title: "导出分析", detail: "截图、慢放视频与双路合成") }
                }.padding().frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }.background(Theme.paper)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
            switch result {
            case .success(let url):
                if w.issue != nil, let asset = w.selectedAsset, w.metadata == nil {
                    Task { do { try await w.repository.relink(url, asset: asset); await w.reload() } catch { w.issue = error.localizedDescription } }
                } else { w.importFile(url) }
            case .failure(let error): w.issue = error.localizedDescription
            }
        }
        .sheet(isPresented: $photos) {
            PhotoImportView { result in
                photos = false
                switch result {
                case .success(let selection): w.notice = selection.notice; w.importFile(selection.url, timing: selection.timing)
                case .failure(let error): if !(error is CancellationError) { w.issue = error.localizedDescription }
                }
            }
        }
        .sheet(isPresented: $capture, onDismiss: { Task { await w.reload() } }) { NavigationStack { CaptureView(session: w.session) } }
        .sheet(isPresented: $showPose) { NavigationStack { PoseToolsView(workspace: w) } }
        .alert("命名关键帧", isPresented: $showKeyframe) {
            TextField("动作节点或自定义名称", text: $keyframeName)
            Button("保存") { w.addKeyframe(keyframeName); keyframeName = "" }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { w.stopAndSave() } else if w.frame?.index != w.frameIndex { w.seek(frame:w.frameIndex) } }
    }
    private var importControls: some View {
        HStack {
            Button("相册", systemImage: "photo.on.rectangle") { w.pause(); photos = true }.accessibilityIdentifier("importPhotos")
            Button("文件", systemImage: "folder") { w.pause(); importing = true }.accessibilityIdentifier("importFile")
            Button("拍摄", systemImage: "video") { w.pause(); capture = true }.accessibilityIdentifier("captureVideo")
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                Button("测试素材") { Task { await importFixture() } }.accessibilityIdentifier("importFixture")
            }
            #endif
        }.buttonStyle(.bordered).disabled(w.busy)
    }
    private var playbackControls: some View {
        VStack(spacing: 8) {
            if !w.thumbnails.isEmpty {
                GeometryReader { geo in
                    HStack(spacing: 1) { ForEach(w.thumbnails.indices, id: \.self) { index in
                        Image(uiImage: w.thumbnails[index]).resizable().scaledToFill().frame(width: max(1,geo.size.width/CGFloat(w.thumbnails.count)),height: 40).clipped()
                    } }
                }.frame(height: 40).clipShape(RoundedRectangle(cornerRadius: 5))
            }
            if let metadata = w.metadata {
                Slider(value: Binding(get: { Double(w.frameIndex) }, set: { w.seek(frame: Int($0.rounded())) }), in: 0...Double(max(1,metadata.timeline.frames.count-1)), step: 1,
                       onEditingChanged: { editing in if !editing { w.save() } }).accessibilityIdentifier("frameSlider")
            }
            HStack {
                Button { w.step(-1) } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("前一帧").accessibilityIdentifier("previousFrame")
                Spacer()
                Button {
                    if w.playing { w.pause(); w.seek(frame: w.frameIndex); w.save() } else { w.play() }
                } label: { Image(systemName: w.playing ? "pause.fill" : "play.fill").frame(width: 38) }
                    .accessibilityLabel(w.playing ? "暂停" : "播放").accessibilityIdentifier("playPause")
                Spacer()
                Button { w.step(1) } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("后一帧").accessibilityIdentifier("nextFrame")
                Picker("速度", selection: $workspace.rate) { ForEach([1.0,0.5,0.25,0.1,0.05], id: \.self) { Text("\($0.formatted())×").tag($0) } }
                    .onChange(of: w.rate) { _, value in w.snapshot.playbackRates[w.key] = value; w.save(); if w.playing { w.play() } }
            }.buttonStyle(.bordered)
            HStack {
                Toggle("循环", isOn: $workspace.looping).fixedSize()
                Spacer()
                Button { w.muted.toggle(); w.playback?.player.isMuted = w.muted } label: { Image(systemName: w.muted ? "speaker.slash" : "speaker.wave.2") }.accessibilityLabel("切换静音")
                Menu("片段") {
                    Button("当前帧设为起点") { w.pause(); w.markStart() }
                    Button("当前帧设为终点") { w.pause(); w.markEnd() }
                    Button("恢复完整视频") { w.fullClip() }
                }
            }.font(.caption)
            Text("片段 \(w.clip.start.seconds, specifier: "%.3f") – \(w.clip.end.seconds, specifier: "%.3f") s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
    private var drawingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach([("view","hand.draw","画面"),("select","cursorarrow","选择"),("line","line.diagonal","直线"),("arrow","arrow.up.right","箭头"),("ellipse","circle","圆框"),("freehand","pencil.tip","手绘"),("text","textformat","文字"),("angle","angle","角度")], id: \.0) { tool in
                        Button { w.tool = tool.0 } label: { Label(tool.2, systemImage: tool.1).font(.caption).padding(9)
                            .background(w.tool == tool.0 ? Theme.burgundy : Color.white, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(w.tool == tool.0 ? .white : Theme.burgundy) }.accessibilityIdentifier("tool_"+tool.0)
                    }
                }
            }
            if w.tool == "view" {
                HStack {
                    Text("双指缩放 · 单指移动").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu("画面") {
                        Button("复位") { w.updateView(ViewSettings()) }
                        Button("镜像") { var v=w.viewSettings; v.mirrored.toggle(); w.updateView(v) }
                        Button("旋转 90°") { var v=w.viewSettings; v.quarterTurns += 1; w.updateView(v) }
                        Button("放大") { var v=w.viewSettings; v.zoom=min(8,v.zoom+0.5); w.updateView(v) }
                        Button("缩小") { var v=w.viewSettings; v.zoom=max(1,v.zoom-0.5); w.updateView(v) }
                    }
                }
            } else {
                HStack {
                    ForEach(["#722F37","#FFFFFF","#F9C74F","#33C3EE"], id: \.self) { color in
                        Button { w.color = color; w.styleSelection() } label: { Circle().fill(Color(uiColor: UIColor(hex: color))).frame(width: 24,height:24)
                            .overlay(Circle().stroke(.gray, lineWidth: w.color == color ? 3 : 1)) }.accessibilityLabel("颜色 "+color)
                    }
                    Picker("线宽", selection: $workspace.lineWidth) { ForEach([2.0,4.0,7.0],id: \.self) { Text("\(Int($0)) pt").tag($0) } }.onChange(of:w.lineWidth) { _,_ in w.styleSelection() }
                    Picker("显示范围", selection: $workspace.rangeMode) { Text("单帧").tag("单帧"); Text("片段").tag("片段") }
                }
                if w.tool == "text" { TextField("标注文字", text: $workspace.textValue).textFieldStyle(.roundedBorder).onSubmit { w.styleSelection() } }
                if w.tool == "angle" { Text("依次点选三个点，第二点为角度顶点。").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("撤销", systemImage: "arrow.uturn.backward") { w.undo() }.disabled(w.undoStack.isEmpty).accessibilityIdentifier("undoAnnotation")
                    Button("重做", systemImage: "arrow.uturn.forward") { w.redo() }.disabled(w.redoStack.isEmpty)
                    Spacer()
                    Button("删除", systemImage: "trash", role: .destructive) { w.deleteSelection() }.disabled(w.selectedAnnotation == nil).accessibilityIdentifier("deleteAnnotation")
                }.font(.caption)
            }
        }.padding(10).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius:12))
    }
    private var keyframes: some View {
        VStack(alignment: .leading) {
            Menu("动作节点建议") {
                ForEach(w.session.sport == .batting ? ["准备","抬腿","前脚落地","击球","随挥"] : ["准备","抬腿顶点","跨步落地","出手","随挥"], id: \.self) { name in
                    Button(name) { w.addKeyframe(name) }
                }
            }.font(.caption)
            ForEach(w.snapshot.keyframes.filter { $0.videoID == w.selectedVideoID }) { keyframe in
                HStack {
                    Button("\(keyframe.name) · \(keyframe.time.seconds.formatted(.number.precision(.fractionLength(3)))) s") { w.seek(time: keyframe.time.seconds) }
                    Spacer()
                    Button { w.removeKeyframe(keyframe.id) } label: { Image(systemName:"xmark.circle") }.accessibilityLabel("删除关键帧")
                }.font(.caption)
            }
        }
    }
    #if DEBUG
    private func importFixture() async {
        do {
            let url = URL.temporaryDirectory.appendingPathComponent("UI-\(UUID().uuidString).mov")
            let fps = w.assets.isEmpty ? 30 : 120
            try await FixtureFactory.video(at: url, times: (0..<(fps*2)).map { Double($0)/Double(fps) }, duration: 2)
            w.importFile(url)
        } catch { w.issue = error.localizedDescription }
    }
    #endif
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
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }.padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
