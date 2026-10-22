import SwiftUI
import UniformTypeIdentifiers

struct SessionDetail: View {
    @EnvironmentObject private var library: LibraryStore
    let session: AnalysisSession
    var initialVideoID: UUID? = nil
    var onClose: (() -> Void)? = nil
    @State private var workspace: AnalysisWorkspace?
    @State private var name = ""
    @State private var renaming = false
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let workspace { AnalysisEditor(workspace: workspace) }
            else { ProgressView("打开本机分析…").frame(maxWidth:.infinity,maxHeight:.infinity).background(.black) }
        }
        .navigationTitle(session.name).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarBackground(.black,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
        .toolbarColorScheme(.dark,for:.navigationBar)
        .toolbar {
            ToolbarItem(placement:.topBarLeading) {
                Button("关闭视频",systemImage:"xmark") { workspace?.stopAndSave();if let onClose { onClose() } else { dismiss() } }
                    .labelStyle(.iconOnly).accessibilityIdentifier("closeVideo")
            }
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    Button("重命名",systemImage:"pencil") { name=session.name;renaming=true }.accessibilityIdentifier("renameSession")
                    if let w=workspace {
                        Button("镜像",systemImage:"arrow.left.and.right.righttriangle.left.righttriangle.right") { w.pause();var v=w.viewSettings;v.mirrored.toggle();w.updateView(v) }
                        Button("旋转 90°",systemImage:"rotate.right") { w.pause();var v=w.viewSettings;v.quarterTurns+=1;w.updateView(v) }
                        Button("复位画面",systemImage:"arrow.counterclockwise") { w.updateView(ViewSettings()) }
                        NavigationLink { ExportView(session:session,initialVideoID:w.selectedVideoID,initialPose:w.overlaysVisible && w.poseSettings.visible,initialAnnotations:w.overlaysVisible) } label: { Label("导出分析",systemImage:"square.and.arrow.up") }
                    }
                    Button("删除记录",systemImage:"trash",role:.destructive) { deleting=true }.accessibilityIdentifier("deleteSession")
                } label: { Image(systemName:"ellipsis.circle").frame(width:44,height:44) }.accessibilityLabel("更多操作").accessibilityIdentifier("moreActions")
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
        .onDisappear { workspace?.stopAndSave() }
    }
}

struct AnalysisEditor: View {
    @ObservedObject var workspace: AnalysisWorkspace
    @State private var importing=false
    @State private var photos=false
    @State private var capture=false
    @State private var showKeyframe=false
    @State private var showPose=false
    @State private var showTools=false
    @State private var showNodes=false
    @State private var showAdd=false
    @State private var showCompare=false
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
                    quickActions
                    HStack(spacing:0) {
                        ZStack(alignment:.topLeading) {
                            AnalysisCanvas(workspace:w)
                            if w.seeking || w.preparing { ProgressView(w.preparing ? "准备播放…":"定位中…").font(.caption).padding(10).background(.black.opacity(0.65),in:Capsule()).padding(8).allowsHitTesting(false) }
                            if w.tool != "view" { Text(w.rangeMode == "单帧" ? "绘图 · 当前帧":"绘图 · 整个片段").font(.caption).padding(8).background(.black.opacity(0.65),in:Capsule()).padding(8).allowsHitTesting(false) }
                        }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
                        if showTools && geometry.size.width>=700 { ScrollView { drawingControls }.frame(width:244).background(Color(white:0.12)) }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    if showTools && geometry.size.width<700 { ScrollView { drawingControls }.frame(height:155).background(Color(white:0.12)) }
                    playbackControls(compact:landscape)
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
        .sheet(isPresented:$showPose) { NavigationStack { PoseToolsView(workspace:w) } }
        .sheet(isPresented:$showNodes) { NavigationStack { ScrollView { keyframes.padding() }.navigationTitle("关键帧").toolbar { Button("完成") { showNodes=false } } }.presentationDetents([.medium,.large]) }
        .sheet(isPresented:Binding(get:{screenshotURL != nil},set:{if !$0 { screenshotURL=nil }})) { if let screenshotURL { ShareSheet(url:screenshotURL) } }
        .navigationDestination(isPresented:$showCompare) { ComparisonView(session:w.session,initialVideoID:w.selectedVideoID) }
        .confirmationDialog("添加素材",isPresented:$showAdd,titleVisibility:.visible) { importControls }
        .alert("命名关键帧",isPresented:$showKeyframe) { TextField("动作节点或自定义名称",text:$keyframeName);Button("保存") { w.addKeyframe(keyframeName);keyframeName="" };Button("取消",role:.cancel) {} }
        .onAppear { w.resumeDisplay() }
        .onChange(of:scenePhase) { _,phase in if phase != .active { w.stopAndSave() } else { w.resumeDisplay() } }
        .onChange(of:showTools) { _,value in if !value { w.tool="view" } }
    }
    private var quickActions:some View {
        HStack(spacing:0) {
            Button { Task { await screenshot() } } label: { Label("截图",systemImage:"camera").frame(maxWidth:.infinity,minHeight:44) }.disabled(screenshotBusy || w.metadata == nil || w.seeking || w.scrubbing || w.preparing).accessibilityIdentifier("quickScreenshot")
            Button { w.pause();showTools.toggle() } label: { Label("绘图",systemImage:"pencil.tip.crop.circle").frame(maxWidth:.infinity,minHeight:44) }.accessibilityIdentifier("drawingTools")
            Button { w.pause();showPose=true } label: { Label("人体分析",systemImage:"figure.stand").frame(maxWidth:.infinity,minHeight:44) }.accessibilityIdentifier("poseTools")
            Button { w.pause();w.save();showCompare=true } label: { Label("对比",systemImage:"rectangle.split.2x1").frame(maxWidth:.infinity,minHeight:44) }.accessibilityIdentifier("openComparison")
            Menu {
                Picker("当前素材",selection:Binding(get:{w.selectedVideoID ?? UUID()},set:{id in Task { w.save();await w.select(id) }})) { ForEach(w.assets) { Text($0.originalName).tag($0.id) } }
                Button("添加素材",systemImage:"plus") { w.pause();showAdd=true }
                Button("关键帧列表",systemImage:"bookmark") { w.pause();showNodes=true }.accessibilityIdentifier("openKeyframes")
                Button(w.overlaysVisible ? "隐藏标注与骨架":"显示标注与骨架",systemImage:w.overlaysVisible ? "eye.slash":"eye") { w.overlaysVisible.toggle() }.accessibilityIdentifier("toggleOverlays")
            } label: { Image(systemName:"slider.horizontal.3").frame(width:44,height:44) }.accessibilityLabel("素材与显示").accessibilityIdentifier("videoOptions")
        }.labelStyle(.iconOnly).font(.title3).background(Color(white:0.08))
    }
    private func playbackControls(compact:Bool)->some View {
        VStack(spacing:compact ? 2:6) {
            Text("第 \(w.frameIndex+1) / \(w.metadata?.timeline.frames.count ?? 0) 帧 · \(w.time,specifier:"%.3f") s")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).accessibilityIdentifier("frameReadout")
            VideoTimeline(workspace:w,compact:compact)
            HStack(spacing:12) {
                Button { w.looping.toggle() } label: { Image(systemName:"repeat").foregroundStyle(w.looping ? Theme.rose:.white).frame(width:44,height:44) }.accessibilityLabel(w.looping ? "关闭循环":"开启循环")
                FrameStepButton(direction:-1) { w.step(-1) }.accessibilityIdentifier("previousFrame")
                Spacer(minLength:0)
                Button { if w.playing || w.preparing { w.pause();w.save() } else { w.play() } } label: { Image(systemName:w.playing || w.preparing ? "pause.fill":"play.fill").font(.title2).frame(width:48,height:44) }.accessibilityLabel(w.playing ? "暂停":"播放").accessibilityIdentifier("playPause")
                Spacer(minLength:0)
                FrameStepButton(direction:1) { w.step(1) }.accessibilityIdentifier("nextFrame")
                Menu { Picker("速度",selection:Binding(get:{w.rate},set:{w.setRate($0)})) { ForEach([1.0,0.5,0.25,0.1,0.05],id:\.self) { Text("\($0.formatted())×").tag($0) } } } label: { Text("\(w.rate.formatted())×").font(.callout.monospacedDigit()).frame(minWidth:44,minHeight:44) }.accessibilityLabel("播放速度").accessibilityIdentifier("playbackRate")
            }
            if !compact {
                HStack {
                    Button { w.muted.toggle();w.playback?.player.isMuted=w.muted } label: { Image(systemName:w.muted ? "speaker.slash":"speaker.wave.2").frame(width:44,height:44) }.accessibilityLabel("切换静音")
                    Text("\(w.snapshot.annotations.count) 个标注 · \(w.snapshot.keyframes.count) 个关键帧").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("annotationCount")
                    Spacer(minLength:0)
                    Button("关键帧",systemImage:"bookmark") { w.pause();showKeyframe=true }.font(.caption).frame(minHeight:44).accessibilityIdentifier("addKeyframe")
                }
            }
        }.padding(.horizontal,12).padding(.top,6).background(Color(white:0.08))
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
    private var drawingControls:some View {
        VStack(alignment:.leading,spacing:2) {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:4) {
                    ForEach([("view","hand.draw","画面"),("select","cursorarrow","选择"),("line","line.diagonal","直线"),("arrow","arrow.up.right","箭头"),("ellipse","circle","圆框"),("freehand","pencil.tip","手绘"),("text","textformat","文字"),("angle","angle","角度")],id:\.0) { tool in
                        Button { w.pause();w.tool=tool.0 } label: {
                            Label(tool.2,systemImage:tool.1).font(.caption).padding(.horizontal,10).frame(minHeight:44)
                                .background(w.tool==tool.0 ? Theme.burgundy:Color(white:0.2),in:RoundedRectangle(cornerRadius:8))
                        }.accessibilityIdentifier("tool_"+tool.0)
                    }
                }
            }
            if w.tool == "view" {
                HStack { Text("双指缩放 · 单指移动 · 双击复位").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength:0);Button("复位") { w.updateView(ViewSettings()) }.font(.caption).frame(minHeight:44)
                }
            } else {
                HStack(spacing:0) {
                    ForEach(["#722F37","#FFFFFF","#F9C74F","#33C3EE"],id:\.self) { color in
                        Button { w.color=color;w.styleSelection() } label: {
                            Circle().fill(Color(uiColor:UIColor(hex:color))).frame(width:22,height:22).overlay(Circle().stroke(w.color==color ? Color.white:Color.gray,lineWidth:w.color==color ? 3:1)).frame(width:44,height:44)
                        }.accessibilityLabel("颜色 "+color)
                    }
                    Spacer(minLength:0)
                    Menu {
                        Picker("线宽",selection:$workspace.lineWidth) { ForEach([2.0,4.0,7.0],id:\.self) { Text("\(Int($0)) pt").tag($0) } }
                        Picker("显示范围",selection:$workspace.rangeMode) { Text("当前帧").tag("单帧");Text("整个片段").tag("片段") }
                    } label: { Text(w.rangeMode=="单帧" ? "当前帧":"整个片段").font(.caption).frame(minWidth:44,minHeight:44) }.accessibilityLabel("标注样式与显示范围")
                }.onChange(of:w.lineWidth) { _,_ in w.styleSelection() }
                HStack {
                    Button("撤销",systemImage:"arrow.uturn.backward") { w.undo() }.disabled(w.undoStack.isEmpty).accessibilityIdentifier("undoAnnotation")
                    Button("重做",systemImage:"arrow.uturn.forward") { w.redo() }.disabled(w.redoStack.isEmpty)
                    Spacer(minLength:0)
                    Button("删除",systemImage:"trash",role:.destructive) { w.deleteSelection() }.disabled(w.selectedAnnotation==nil).accessibilityIdentifier("deleteAnnotation")
                }.font(.caption).frame(minHeight:44)
                if w.tool=="text" { TextField("标注文字",text:$workspace.textValue).textFieldStyle(.roundedBorder).onSubmit { w.styleSelection() } }
                if w.tool=="angle" { Text("依次选三个点，第二点为角度顶点。").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.horizontal,8).padding(.vertical,4).foregroundStyle(.white)
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
