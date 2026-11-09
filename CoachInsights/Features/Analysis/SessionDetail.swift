import SwiftUI
import UniformTypeIdentifiers

struct MediaWorkspaceFocusPreferenceKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct MediaWorkspaceNavigationHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Requests a layout change without locking the device orientation. Physical
/// rotation continues to work, and leaving focus can return to portrait.
@MainActor private enum MediaSceneOrientation {
    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}

struct SessionDetail: View {
    @EnvironmentObject private var library: LibraryStore
    let session: AnalysisSession
    var initialVideoID: UUID? = nil
    var onClose: (() -> Void)? = nil
    @State private var workspace: AnalysisWorkspace?
    @State private var name = ""
    @State private var renaming = false
    @State private var deleting = false
    @State private var fullscreenRequested = false
    @State private var mediaLoaded = false
    @State private var pageVisible = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        GeometryReader { geometry in
            let immersive = mediaLoaded && (fullscreenRequested ||
                (UIDevice.current.userInterfaceIdiom == .phone && geometry.size.width > geometry.size.height))
            Group {
                if let workspace {
                    AnalysisEditor(workspace: workspace, immersive: immersive, toggleFullscreen: { toggleFullscreen(immersive) }, mediaReady: { mediaLoaded = $0 })
                } else { ProgressView("打开本机分析…").frame(maxWidth:.infinity,maxHeight:.infinity).background(.black) }
            }
            .overlay(alignment: .topLeading) {
                if immersive {
                    closeButton.frame(width: 44, height: 44).background(.black.opacity(0.65), in: Circle()).padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if immersive { sessionMenu.background(.black.opacity(0.65), in: Circle()).padding(4) }
            }
            .toolbar(immersive && pageVisible ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive && pageVisible)
            .preference(key: MediaWorkspaceFocusPreferenceKey.self, value: mediaLoaded && pageVisible)
            .preference(key: MediaWorkspaceNavigationHiddenPreferenceKey.self, value: immersive && pageVisible)
        }
        .navigationTitle(session.name).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarBackground(.black,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
        .toolbarColorScheme(.dark,for:.navigationBar)
        .toolbar {
            ToolbarItem(placement:.topBarLeading) {
                closeButton
            }
            ToolbarItem(placement:.topBarTrailing) {
                sessionMenu
            }
        }
        .alert("删除分析记录？",isPresented:$deleting) {
            Button("取消",role:.cancel) {}
            Button("删除",role:.destructive) { Task { workspace?.stopAndSave();await library.remove(session);if let onClose { onClose() } else { dismiss() } } }
        } message: { Text("清理这份记录与未被其他记录使用的本机副本。") }
        .alert("重命名",isPresented:$renaming) {
            TextField("分析名称",text:$name)
            Button("保存") { library.rename(session,name:name) };Button("取消",role:.cancel) {}
        }
        .task(id:session.id) {
            guard workspace == nil,let repository=library.repository else { return }
            let value=AnalysisWorkspace(session:session,repository:repository)
            value.selectedVideoID=initialVideoID;workspace=value;await value.reload()
        }
        .onAppear { pageVisible = true }
        .onDisappear { pageVisible = false; workspace?.stopAndSave() }
    }
    private var closeButton: some View {
        Button("关闭视频", systemImage: "xmark") {
            workspace?.stopAndSave()
            if fullscreenRequested { MediaSceneOrientation.request(.portrait) }
            fullscreenRequested = false
            if let onClose { onClose() } else { dismiss() }
        }.labelStyle(.iconOnly).foregroundStyle(.white).accessibilityIdentifier("closeVideo")
    }
    private var sessionMenu: some View {
        Menu {
            Button("重命名",systemImage:"pencil") { name=session.name;renaming=true }.accessibilityIdentifier("renameSession")
            if let w=workspace {
                Button("镜像",systemImage:"arrow.left.and.right.righttriangle.left.righttriangle.right") { w.pause();var v=w.viewSettings;v.mirrored.toggle();w.updateView(v) }
                Button("旋转 90°",systemImage:"rotate.right") { w.pause();var v=w.viewSettings;v.quarterTurns+=1;w.updateView(v) }
                Button("复位画面",systemImage:"arrow.counterclockwise") { w.updateView(ViewSettings()) }
                NavigationLink { ExportView(session:session,initialVideoID:w.selectedVideoID,initialPose:w.overlaysVisible && w.poseSettings.visible,initialAnnotations:w.overlaysVisible) } label: { Label("导出分析",systemImage:"square.and.arrow.up") }
            }
            Button("删除记录",systemImage:"trash",role:.destructive) { deleting=true }.accessibilityIdentifier("deleteSession")
        } label: { Image(systemName:"ellipsis.circle").frame(width:44,height:44) }
            .foregroundStyle(.white).accessibilityLabel("更多操作").accessibilityIdentifier("moreActions")
    }
    private func toggleFullscreen(_ immersive: Bool) {
        workspace?.pause(); workspace?.save()
        fullscreenRequested = !immersive
        MediaSceneOrientation.request(immersive ? .portrait : .landscape)
    }
}

struct AnalysisEditor: View {
    @ObservedObject var workspace: AnalysisWorkspace
    var immersive = false
    var toggleFullscreen: () -> Void = {}
    var mediaReady: (Bool) -> Void = { _ in }
    @State private var importing=false
    @State private var photos=false
    @State private var capture=false
    @State private var showKeyframe=false
    @State private var showPose=false
    @State private var showTools=false
    @State private var showNodes=false
    @State private var showAdd=false
    @State private var showCompare=false
    @State private var showTimeline=false
    @State private var keyframeName=""
    @State private var screenshotURL:URL?
    @State private var screenshotBusy=false
    @Environment(\.scenePhase) private var scenePhase
    private var w:AnalysisWorkspace { workspace }
    var body:some View {
        GeometryReader { geometry in
            let landscape=geometry.size.width>geometry.size.height
            VStack(spacing:0) {
                if w.metadata != nil {
                    if immersive {
                        immersiveCanvas(geometry.size)
                    } else {
                        quickActions
                        canvas.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                        if showTools { drawingControls }
                        playbackControls(compact: landscape)
                    }
                } else {
                    Spacer()
                    EmptyPanel(icon:"video.badge.plus",title:"添加分析素材",detail:"拍摄或导入视频，逐帧看清动作。\n原片与分析仅保存在当前设备。")
                    importControls
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--real-footage"),!FileManager.default.fileExists(atPath:URL.documentsDirectory.appendingPathComponent("V101-RegressionFixture.mov").path) { Text("本机测试原片缺失").accessibilityIdentifier("realFixtureUnavailable") }
                    #endif
                    Button("双视频对比",systemImage:"rectangle.split.2x1") { showCompare=true }.padding()
                    Spacer()
                }
                if w.busy { HStack { ProgressView(value:w.progress);Button("取消导入") { w.importTask?.cancel() } }.padding(8) }
                if let error=w.saveIssue { HStack { Text("保存失败："+error);Button("重试保存") { w.save() } }.font(.caption).padding(8) }
                if let issue=w.issue { HStack { Text(issue);Button("重试读取") { Task { await w.reload() } };Button("重新关联原片") { importing=true } }.font(.caption).padding(8).foregroundStyle(.orange) }
                if let notice=w.notice { Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(4).accessibilityIdentifier("editorNotice") }
            }.background(.black).foregroundStyle(.white).tint(Theme.rose)

        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.movie]) { result in
            switch result {
            case .success(let url):
                if w.issue != nil,let asset=w.selectedAsset,w.metadata == nil { Task { do { try await w.repository.relink(url,asset:asset);await w.reload() } catch { w.issue=error.localizedDescription } } }
                else { w.importFile(url) }
            case .failure(let error):w.issue=error.localizedDescription
            }
        }
        .sheet(isPresented:$photos) { PhotoImportView { result in photos=false;switch result { case .success(let selection):w.notice=selection.notice;w.importFile(selection.url,timing:selection.timing)
        case .failure(let error):if !(error is CancellationError) { w.issue=error.localizedDescription } } } }
        .sheet(isPresented:$capture,onDismiss:{Task { await w.reload() }}) { NavigationStack { CaptureView(session:w.session) } }
        .sheet(isPresented:$showTimeline) {
            NavigationStack {
                ScrollView { VideoTimeline(workspace: w).padding() }
                    .navigationTitle("时间轴与片段")
                    .toolbar { Button("完成") { w.save(); showTimeline = false } }
            }.presentationDetents([.medium, .large]).preferredColorScheme(.dark)
        }
        .sheet(isPresented:$showPose) { NavigationStack { PoseToolsView(workspace:w) } }
        .sheet(isPresented:$showNodes) { NavigationStack { ScrollView { keyframes.padding() }.navigationTitle("关键帧").toolbar { Button("完成") { showNodes=false } } }.presentationDetents([.medium,.large]) }
        .sheet(isPresented:Binding(get:{screenshotURL != nil},set:{if !$0 { screenshotURL=nil }})) { if let screenshotURL { ShareSheet(url:screenshotURL) } }
        .navigationDestination(isPresented:$showCompare) { ComparisonView(session:w.session,initialVideoID:w.selectedVideoID) }
        .confirmationDialog("添加素材",isPresented:$showAdd,titleVisibility:.visible) { importControls }
        .alert("命名关键帧",isPresented:$showKeyframe) { TextField("动作节点或自定义名称",text:$keyframeName);Button("保存") { w.addKeyframe(keyframeName);keyframeName="" };Button("取消",role:.cancel) {} }
        .onAppear { w.resumeDisplay() }
        .onChange(of: w.metadata != nil, initial: true) { _, loaded in mediaReady(loaded) }
        .onChange(of:scenePhase) { _,phase in if phase != .active { w.stopAndSave() } else { w.resumeDisplay() } }

        .onChange(of: immersive) { _, focused in if !focused && w.tool != "view" { showTools = true } }
    }
    private var quickActions:some View {
        HStack(spacing: 0) {
            Button { Task { await screenshot() } } label: {
                workspaceAction("截图", symbol: "camera")
            }.disabled(screenshotBusy || w.seeking || w.scrubbing || w.preparing).accessibilityIdentifier("quickScreenshot")
            Button {
                w.pause()
                showTools.toggle()
                w.activateDrawingTool(showTools ? "arrow" : "view")
            } label: {
                workspaceAction("绘图", symbol: "pencil.tip", selected: showTools)
            }.accessibilityIdentifier("drawingTools").accessibilityAddTraits(showTools ? .isSelected : [])
            Button { w.pause(); showPose = true } label: {
                workspaceAction("人体", symbol: "figure.stand")
            }.accessibilityLabel("人体分析").accessibilityIdentifier("poseTools")
            Button { w.pause(); w.save(); showCompare = true } label: {
                workspaceAction("对比", symbol: "rectangle.split.2x1")
            }.accessibilityIdentifier("openComparison")
            Menu {
                Picker("当前素材", selection: Binding(get: { w.selectedVideoID }, set: { id in
                    guard let id else { return }
                    Task { w.save(); await w.select(id) }
                })) { ForEach(w.assets) { Text($0.originalName).tag(Optional($0.id)) } }
                Button("添加素材", systemImage: "plus") { w.pause(); showAdd = true }
                Button("保存关键帧", systemImage: "bookmark.badge.plus") { w.pause(); showKeyframe = true }.accessibilityIdentifier("addKeyframe")
                Button("关键帧列表", systemImage: "bookmark") { w.pause(); showNodes = true }.accessibilityIdentifier("openKeyframes")
                Button(w.muted ? "开启声音" : "静音", systemImage: w.muted ? "speaker.wave.2" : "speaker.slash") {
                    w.muted.toggle()
                    w.playback?.player.isMuted = w.muted
                }
                Button(w.overlaysVisible ? "隐藏标注与骨架" : "显示标注与骨架", systemImage: w.overlaysVisible ? "eye.slash" : "eye") {
                    w.overlaysVisible.toggle()
                    if !w.overlaysVisible { showTools = false; w.activateDrawingTool("view") }
                }.accessibilityIdentifier("toggleOverlays")
            } label: { workspaceAction("选项", symbol: "slider.horizontal.3") }
                .accessibilityIdentifier("videoOptions")
            Button(action: toggleFullscreen) {
                workspaceAction(immersive ? "退出" : "全屏", symbol: immersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }.accessibilityLabel(immersive ? "退出全屏，返回竖屏" : "横屏全屏")
                .accessibilityIdentifier("analysisFullscreen")
        }.buttonStyle(.plain).padding(.horizontal, 6)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .background(immersive ? Color.black.opacity(0.78) : Color(white: 0.08))
    }
    private func workspaceAction(_ title: String, symbol: String, selected: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
            Text(title).font(.caption2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(selected ? Theme.rose : .white)
        .background(selected ? Theme.burgundy.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
    private var canvas: some View {
        ZStack(alignment:.topLeading) {
            AnalysisCanvas(workspace:w)
            if w.seeking || w.preparing { ProgressView(w.preparing ? "准备播放…":"定位中…").font(.caption).padding(10).background(.black.opacity(0.65),in:Capsule()).padding(8).allowsHitTesting(false) }
        }
    }
    private func immersiveCanvas(_ size: CGSize) -> some View {
        canvas
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .overlay(alignment: .top) {
                quickActions.padding(.horizontal, 56).padding(.top, 4)
            }
            .overlay(alignment: .topTrailing) {
                if showTools {
                    drawingControls
                        .frame(width: min(360, size.width * 0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 52).padding(.trailing, 8)
                }
            }
            .overlay(alignment: .bottom) { immersivePlayback }
    }
    private var immersivePlayback: some View {
        HStack(spacing: 6) {
            Button { w.pause(); showTimeline = true } label: { Image(systemName: "timeline.selection").frame(width: 44, height: 44) }
                .accessibilityLabel("时间轴与片段").accessibilityIdentifier("openTimeline")
            FrameStepButton(direction:-1) { w.step(-1) }.accessibilityIdentifier("previousFrame")
            Button {
                if w.playing || w.preparing { w.pause(); w.save() } else { w.play() }
            } label: { Image(systemName: w.playing || w.preparing ? "pause.fill" : "play.fill").font(.title2).frame(width: 44, height: 44) }
                .accessibilityLabel(w.playing ? "暂停" : "播放").accessibilityIdentifier("playPause")
            FrameStepButton(direction:1) { w.step(1) }.accessibilityIdentifier("nextFrame")
            if let metadata = w.metadata {
                Slider(value: Binding(get: { w.time }, set: { w.scrub(to: $0) }), in: 0...max(0.001, metadata.timeline.duration.seconds), onEditingChanged: { editing in
                    if editing { w.beginScrubbing() } else { w.endScrubbing() }
                }).accessibilityIdentifier("frameSlider")
            }
            Text("第 \(w.frameIndex + 1) / \(w.metadata?.timeline.frames.count ?? 0) 帧 · \(w.time, specifier: "%.3f") s")
                .font(.caption2.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: 174).accessibilityIdentifier("frameReadout")
            Menu {
                Picker("速度", selection: Binding(get: { w.rate }, set: { w.setRate($0) })) {
                    ForEach([1.0,0.5,0.25,0.1,0.05], id: \.self) { Text("\($0.formatted())×").tag($0) }
                }
                Button(w.looping ? "关闭循环" : "开启循环") { w.looping.toggle() }
            } label: { Text("\(w.rate.formatted())×").font(.callout.monospacedDigit()).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("播放速度").accessibilityIdentifier("playbackRate")
        }.padding(.horizontal, 8).background(.black.opacity(0.65))
    }
    private func playbackControls(compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("第 \(w.frameIndex + 1) / \(w.metadata?.timeline.frames.count ?? 0) 帧 · \(w.time, specifier: "%.3f") s")
                    .font(.caption.monospacedDigit()).accessibilityIdentifier("frameReadout")
                Spacer(minLength: 0)
                Text("\(w.snapshot.annotations.count) 个标注 · \(w.snapshot.keyframes.count) 个关键帧")
                    .font(.caption2).accessibilityIdentifier("annotationCount")
            }.lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.secondary)
            VideoTimeline(workspace: w, compact: true)
            HStack(spacing: 0) {
                Button { w.pause(); showTimeline = true } label: {
                    workspaceAction("片段", symbol: "timeline.selection").frame(width: 48)
                }.accessibilityLabel("时间轴与片段").accessibilityIdentifier("openTimeline")
                Spacer(minLength: 0)
                FrameStepButton(direction: -1) { w.step(-1) }.accessibilityIdentifier("previousFrame")
                Button {
                    if w.playing || w.preparing { w.pause(); w.save() } else { w.play() }
                } label: {
                    Image(systemName: w.playing || w.preparing ? "pause.fill" : "play.fill")
                        .font(.title2).frame(width: 60, height: 44)
                }.accessibilityLabel(w.playing ? "暂停" : "播放").accessibilityIdentifier("playPause")
                FrameStepButton(direction: 1) { w.step(1) }.accessibilityIdentifier("nextFrame")
                Spacer(minLength: 0)
                Menu {
                    Picker("速度", selection: Binding(get: { w.rate }, set: { w.setRate($0) })) {
                        ForEach([1.0, 0.5, 0.25, 0.1, 0.05], id: \.self) { Text("\($0.formatted())×").tag($0) }
                    }
                    Button(w.looping ? "关闭循环" : "开启循环", systemImage: "repeat") { w.looping.toggle() }
                } label: {
                    Text("\(w.rate.formatted())×").font(.callout.monospacedDigit()).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("播放速度").accessibilityIdentifier("playbackRate")
            }
        }.padding(.horizontal, 12).padding(.top, compact ? 4 : 8)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .background(Color(white: 0.08))
    }
    private var importControls:some View {
        Group {
            Button("相册",systemImage:"photo.on.rectangle") { w.pause();photos=true }.accessibilityIdentifier("importPhotos")
            Button("文件",systemImage:"folder") { w.pause();importing=true }.accessibilityIdentifier("importFile")
            Button("拍摄",systemImage:"video") { w.pause();capture=true }.accessibilityIdentifier("captureVideo")
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") { Button("测试素材") { Task { await importFixture() } }.accessibilityIdentifier("importFixture") }
            #endif
        }.disabled(w.busy)
    }
    private func screenshot() async {
        w.pause();w.save();screenshotBusy=true;defer { screenshotBusy=false }
        do {
            let recipe=try await ExportBuilder.recipe(session:w.session,repository:w.repository,videoID:w.selectedVideoID,compare:false,rate:w.rate,pose:w.overlaysVisible && w.poseSettings.visible,audio:false)
            let original=recipe.left
            let source=ExportSource(id:original.id,asset:original.asset,metadata:original.metadata,settings:original.settings,annotations:w.overlaysVisible ? original.annotations:[],pose:original.pose,confidence:original.confidence,clip:original.clip)
            screenshotURL=try await ExportService().screenshot(source:source,time:w.time,size:recipe.size,directory:w.repository.files.root.appendingPathComponent("Cache/Exports"))
        } catch { w.issue=error.localizedDescription }
    }
    private let drawingTools = [
        (id: "view", symbol: "hand.draw", title: "画面"),
        (id: "select", symbol: "cursorarrow", title: "选择"),
        (id: "line", symbol: "line.diagonal", title: "直线"),
        (id: "arrow", symbol: "arrow.up.right", title: "箭头"),
        (id: "ellipse", symbol: "circle", title: "圆框"),
        (id: "freehand", symbol: "pencil.tip", title: "手绘")
    ]
    private var drawingTitle: String {
        drawingTools.first { $0.id == w.tool }?.title ?? (w.tool == "text" ? "文字" : "角度")
    }
    private var drawingControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(drawingTools, id: \.id) { tool in
                    Button { w.activateDrawingTool(tool.id) } label: {
                        Image(systemName: tool.symbol)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(w.tool == tool.id ? Theme.burgundy : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }.accessibilityLabel(tool.title).accessibilityIdentifier("tool_" + tool.id)
                        .accessibilityAddTraits(w.tool == tool.id ? .isSelected : [])
                }
                Menu {
                    Button("文字", systemImage: "textformat") { w.activateDrawingTool("text") }.accessibilityIdentifier("tool_text")
                    Button("角度", systemImage: "angle") { w.activateDrawingTool("angle") }.accessibilityIdentifier("tool_angle")
                } label: {
                    Image(systemName: "ellipsis").frame(maxWidth: .infinity, minHeight: 44)
                        .background(["text", "angle"].contains(w.tool) ? Theme.burgundy : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.accessibilityLabel("更多绘图工具")
            }
            HStack(spacing: 0) {
                if w.tool == "view" {
                    Text("双指缩放 · 单指移动").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("复位") { w.updateView(ViewSettings()) }.font(.caption).frame(minHeight: 44)
                } else {
                    Menu {
                        ForEach([("金黄", "#F9C74F"), ("白色", "#FFFFFF"), ("天蓝", "#33C3EE"), ("酒红", "#722F37")], id: \.1) { color in
                            Button(color.0, systemImage: w.color == color.1 ? "checkmark.circle" : "circle") {
                                w.color = color.1; w.styleSelection()
                            }
                        }
                        Picker("线宽", selection: $workspace.lineWidth) {
                            ForEach([2.0, 4.0, 7.0], id: \.self) { Text("\(Int($0)) pt").tag($0) }
                        }
                        Picker("显示范围", selection: $workspace.rangeMode) {
                            Text("当前帧").tag("单帧"); Text("整个片段").tag("片段")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color(uiColor: UIColor(hex: w.color))).frame(width: 12, height: 12)
                            Text(drawingTitle + " · " + (w.rangeMode == "单帧" ? "当前帧" : "整个片段"))
                                .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                            Image(systemName: "chevron.down").font(.caption2)
                        }.frame(minHeight: 44)
                    }.accessibilityLabel("标注样式与显示范围").accessibilityIdentifier("drawingStyle")
                        .onChange(of: w.lineWidth) { _, _ in w.styleSelection() }
                    Spacer(minLength: 4)
                    Button { w.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                        .disabled(w.undoStack.isEmpty).accessibilityLabel("撤销").accessibilityIdentifier("undoAnnotation")
                    Button { w.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }
                        .disabled(w.redoStack.isEmpty).accessibilityLabel("重做")
                    Button(role: .destructive) { w.deleteSelection() } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                        .disabled(w.selectedAnnotation == nil).accessibilityLabel("删除标注").accessibilityIdentifier("deleteAnnotation")
                }
            }.padding(.horizontal, 6)
            if w.tool == "text" {
                TextField("标注文字", text: $workspace.textValue).textFieldStyle(.roundedBorder)
                    .onSubmit { w.styleSelection() }.padding(.bottom, 6)
            } else if w.tool == "angle" {
                Text("依次点三个位置，第二点为顶点。").font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            }
        }.buttonStyle(.plain).padding(.horizontal, 8).padding(.top, 4).foregroundStyle(.white)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .background(Color(white: 0.12))
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
            if ProcessInfo.processInfo.arguments.contains("--real-footage"),w.assets.isEmpty {
                w.importFile(URL.documentsDirectory.appendingPathComponent("V101-RegressionFixture.mov"));return
            }
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
