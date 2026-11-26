import SwiftUI

struct ComparisonView:View {
    let session:AnalysisSession
    var initialVideoID:UUID? = nil
    @EnvironmentObject private var library:LibraryStore
    @State private var workspace:ComparisonWorkspace?
    @State private var choosing=false
    @State private var choosingLeft=false
    @State private var ready = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if ready, let workspace, let repository = library.repository {
                if workspace.setup == nil {
                    let first = workspace.left.selectedVideoID
                    VideoSourcePicker(repository: repository, targetSession: session,
                                      choosingLeft: first == nil, excluding: first) { id in
                        ready = false
                        Task {
                            if let first { await workspace.load(initialVideoID: first, secondVideoID: id) }
                            else { await workspace.left.reload(openVideo: false); await workspace.left.select(id) }
                            ready = true
                        }
                    } onCancel: { dismiss() }
                } else {
                    ComparisonEditor(workspace: workspace) { isLeft in
                        choosingLeft = isLeft; workspace.pause(); choosing = true
                    }
                    .background(.black).foregroundStyle(.white).tint(Theme.rose)
                    .notebookPageTitle("双视频对比")
                }
            } else {
                ProgressView("打开对比…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preference(key: MediaWorkspaceFocusPreferenceKey.self, value: false)
        .preference(key: MediaWorkspaceNavigationHiddenPreferenceKey.self, value: false)
        .task {
            guard workspace == nil, let repository = library.repository else { return }
            let value = ComparisonWorkspace(session: session, repository: repository)
            workspace = value
            let saved = try? session.snapshot().comparison
            if let saved, initialVideoID == nil || saved.leftVideoID == initialVideoID {
                await value.load(initialVideoID: initialVideoID)
            } else {
                await value.left.reload(openVideo: false)
                if let id = initialVideoID ?? value.left.assets.first?.id { await value.left.select(id) }
            }
            ready = true
        }
        .navigationDestination(isPresented: $choosing) {
            if let workspace, let repository = library.repository {
                VideoSourcePicker(repository: repository, targetSession: session, choosingLeft: choosingLeft,
                                  excluding: choosingLeft ? workspace.right.selectedVideoID : workspace.left.selectedVideoID) { id in
                    let isLeft = choosingLeft
                    choosing = false
                    Task { await workspace.refreshAssets(); await workspace.replace(id, isLeft: isLeft) }
                } onCancel: { choosing = false }
            }
        }
        .onDisappear { workspace?.stopAndSave() }
    }
}

struct ComparisonEditor:View {
    @ObservedObject var workspace:ComparisonWorkspace
    var choose:(Bool)->Void
    @State private var adjustingLeft = true
    @Environment(\.scenePhase) private var phase
    var body:some View {
        GeometryReader { geo in
            VStack(spacing:6) {
                if workspace.setup != nil {
                    ScrollView {
                        NotebookColumns(minimumWidth: 740, leadingFraction: 0.68) {
                            VStack(alignment: .leading, spacing: 10) {
                                NotebookHeading(title: "动作对比", detail: workspace.session.name)
                                let horizontal = workspace.setup?.layout == "horizontal"
                                let layout = horizontal ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(spacing: 4))
                                layout {
                                    ComparisonSide(workspace: workspace.left, comparison: workspace, isLeft: true) { choose(true) }
                                    ComparisonSide(workspace: workspace.right, comparison: workspace, isLeft: false) { choose(false) }
                                }.accessibilityElement(children: .contain).accessibilityIdentifier("comparisonSurface")
                                sharedControls(wide: false).foregroundStyle(.white).environment(\.colorScheme, .dark)
                                ForEach([true, false], id: \.self) { left in
                                    ComparisonChannel(workspace: left ? workspace.left : workspace.right, comparison: workspace, isLeft: left)
                                }
                            }
                            VStack(alignment: .leading, spacing: 14) {
                                Text("同步与显示").font(.headline)
                                Text(workspace.independent ? "独立定位" : "两路已联动").foregroundStyle(Notebook.fieldGreen)
                                Button(workspace.independent ? "联动播放定位" : "解除联动") {
                                    if workspace.independent {
                                        workspace.seek(workspace.time)
                                    } else {
                                        workspace.pause(); workspace.independent = true
                                    }
                                }.buttonStyle(NotebookActionStyle())
                                Text("画面布局").font(.subheadline.bold())
                                Picker(
                                    "布局",
                                    selection: Binding(
                                        get: { workspace.layoutChoice },
                                        set: { workspace.selectLayout($0, width: geo.size.width, height: geo.size.height) })
                                ) {
                                    Text("自动").tag("automatic"); Text("左右").tag("horizontal"); Text("上下").tag("vertical")
                                }.pickerStyle(.segmented).accessibilityIdentifier("comparisonLayout")
                                Picker("当前调整", selection: $adjustingLeft) {
                                    Text("A 素材").tag(true); Text("B 素材").tag(false)
                                }.pickerStyle(.segmented)
                                HStack {
                                    Button("同步点 −1 帧") { workspace.frameOffset(-1, isLeft: adjustingLeft) }
                                    Button("同步点 +1 帧") { workspace.frameOffset(1, isLeft: adjustingLeft) }
                                }.buttonStyle(.bordered)
                                Button("替换当前素材") { choose(adjustingLeft) }.buttonStyle(NotebookActionStyle())
                                NavigationLink("导出同屏视频") { ExportView(session: workspace.session, initialComparison: true) }
                                    .buttonStyle(NotebookActionStyle(prominent: true))
                            }.notebookPanel()
                        }.padding(15)
                    }.frame(maxWidth: .infinity).background(Notebook.paper).foregroundStyle(Notebook.ink).tint(Theme.burgundy)
                        .environment(\.colorScheme, .light)

                } else {
                    Spacer();EmptyPanel(icon:"rectangle.split.2x1",title:"将两次动作放在一起",detail:"选择第二段本机视频，设置同步点后联动播放。")
                    Button("选择第二段视频") { choose(false) };Spacer()
                }
                if let issue=workspace.issue { Text(issue).font(.caption).foregroundStyle(.orange).padding(8) }
            }.background(.black)
            .onAppear { workspace.resumeFrames();workspace.adaptLayout(width:geo.size.width,height:geo.size.height) }
            .onChange(of:geo.size) { _, size in workspace.adaptLayout(width: size.width, height: size.height) }
            .onChange(of:workspace.setup != nil) { _,ready in if ready { workspace.adaptLayout(width:geo.size.width,height:geo.size.height) } }
        }.environment(\.colorScheme, .dark)
        .onChange(of:phase) { _,value in if value != .active { workspace.stopAndSave() } else { workspace.resumeFrames() } }
    }
    private var sharedReadout: some View {
        Text(workspace.independent ? "独立定位 · 设同步点后联动播放":"联动 · 共享时间 \(workspace.time.formatted(.number.precision(.fractionLength(3)))) s")
            .font(.caption.monospacedDigit()).accessibilityIdentifier("comparisonReadout")
    }
    private var sharedSlider: some View {
        Group {
            if let range = workspace.range, range.upperBound > range.lowerBound {
                Slider(value: Binding(get: { workspace.time }, set: { value in
                    if workspace.left.scrubbing && workspace.right.scrubbing && !workspace.independent {
                        workspace.scrubShared(to: value)
                    } else {
                        workspace.seek(value)
                    }
                }), in: range, onEditingChanged: { editing in
                    if editing { workspace.beginSharedScrub() }
                    else { workspace.finishSharedScrub() }
                }).accessibilityIdentifier("comparisonSlider")
            }
        }
    }
    private func sharedControls(wide: Bool) -> some View {
        VStack(spacing: 2) {
            sharedReadout
            if !wide { sharedSlider }
            HStack(spacing: 8) {
                Button { workspace.loop.toggle() } label: { Image(systemName:"repeat").frame(width:44,height:44).foregroundStyle(workspace.loop ? Theme.rose:.white) }.accessibilityLabel("切换循环")
                FrameStepButton(direction:-1) { workspace.step(-1) }
                Button { if workspace.playing { workspace.pause();workspace.seek(workspace.time) } else { workspace.play() } } label: { Image(systemName:workspace.playing ? "pause.fill":"play.fill").font(.title2).frame(width:44,height:44) }.accessibilityLabel(workspace.playing ? "暂停":"联动播放").accessibilityIdentifier("comparisonPlay")
                FrameStepButton(direction:1) { workspace.step(1) }
                if wide { sharedSlider } else { Spacer(minLength: 0) }
                Menu { Picker("速度",selection:Binding(get:{workspace.setup?.rate ?? 1},set:{workspace.setRate($0)})) { ForEach([1.0,0.5,0.25,0.1,0.05],id:\.self) { Text("\($0.formatted())×").tag($0) } } } label: { Text("\((workspace.setup?.rate ?? 1).formatted())×").frame(minWidth:44,minHeight:44) }
                    .accessibilityLabel("对比播放速度")
            }
        }.padding(.horizontal, 12).background(Color(white: 0.08))
    }
}

struct ComparisonSide:View {
    @ObservedObject var workspace:AnalysisWorkspace
    @ObservedObject var comparison:ComparisonWorkspace
    let isLeft:Bool
    var choose:()->Void
    var body:some View {
        AnalysisCanvas(workspace: workspace)
            .aspectRatio(workspace.metadata.map { $0.displayWidth / max(1, $0.displayHeight) } ?? 16 / 9, contentMode: .fit)
            .clipped().overlay(alignment: .top) { sideHeader.foregroundStyle(.white).tint(.white) }
            .accessibilityElement(children: .contain).accessibilityIdentifier(isLeft ? "comparisonSideA" : "comparisonSideB")
    }
    private var sideHeader: some View {
        HStack {
                Text(isLeft ? "A":"B").font(.caption.bold()).frame(width: 22, height: 22).background(isLeft ? Theme.burgundy : Notebook.fieldGreen, in: RoundedRectangle(cornerRadius: 3))
                Text(workspace.selectedAsset?.originalName ?? "视频").font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer(minLength:0)
                Menu {
                    Button("替换视频") { choose() }
                    Button("镜像") { comparison.pause();var v=workspace.viewSettings;v.mirrored.toggle();workspace.updateView(v) }
                    Button("旋转 90°") { comparison.pause();var v=workspace.viewSettings;v.quarterTurns+=1;workspace.updateView(v) }
                    Button("复位画面") { comparison.pause();workspace.updateView(ViewSettings()) }
                    Button("当前帧设为片段起点") { comparison.trim(isLeft:isLeft,start:true) }
                    Button("当前帧设为片段终点") { comparison.trim(isLeft:isLeft,start:false) }
                } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel(isLeft ? "A 路设置":"B 路设置")
            }.padding(.horizontal,8)
        .background(.black.opacity(0.55))
    }
}

private struct ComparisonChannel: View {
    @ObservedObject var workspace: AnalysisWorkspace
    @ObservedObject var comparison: ComparisonWorkspace
    let isLeft: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent((isLeft ? "A · " : "B · ") + (workspace.selectedAsset?.originalName ?? "视频")) {
                Text(String(format: "%.3f s", workspace.time)).monospacedDigit()
            }.font(.subheadline.bold())
            if workspace.metadata != nil {
                Slider(
                    value: Binding(get: { workspace.time }, set: { comparison.independentSeek($0, isLeft: isLeft) }),
                    in: workspace.clip.start.seconds...max(workspace.clip.start.seconds + 0.001, workspace.clip.end.seconds),
                    onEditingChanged: { editing in if !editing { workspace.endScrubbing() } }
                )
                .accessibilityIdentifier(isLeft ? "leftSlider" : "rightSlider")
            }
            HStack {
                if let setup = comparison.setup {
                    let anchor = isLeft ? setup.leftAnchor : setup.rightAnchor
                    Text(String(format: "同步点 %.3f s", anchor.seconds)).font(.caption.monospacedDigit())
                }
                Spacer()
                Button("设为同步点") { comparison.anchor(isLeft: isLeft) }
                    .accessibilityIdentifier(isLeft ? "leftAnchor" : "rightAnchor")
            }
        }.notebookPanel()
    }
}
