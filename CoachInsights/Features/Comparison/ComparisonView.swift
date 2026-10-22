import SwiftUI

struct ComparisonView:View {
    let session:AnalysisSession
    var initialVideoID:UUID? = nil
    @EnvironmentObject private var library:LibraryStore
    @State private var workspace:ComparisonWorkspace?
    @State private var choosing=false
    @State private var choosingLeft=false
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        Group {
            if let workspace {
                ComparisonEditor(workspace:workspace) { isLeft in choosingLeft=isLeft;workspace.pause();choosing=true }
            } else { ProgressView("打开对比…") }
        }.background(.black).foregroundStyle(.white).tint(Theme.rose)
        .navigationTitle("双视频对比").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar).toolbarColorScheme(.dark,for:.navigationBar)
        .task {
            guard workspace == nil,let repository=library.repository else { return }
            let w=ComparisonWorkspace(session:session,repository:repository);workspace=w
            let saved=try? session.snapshot().comparison
            if let saved,initialVideoID == nil || saved.leftVideoID==initialVideoID { await w.load(initialVideoID:initialVideoID) }
            else {
                await w.left.reload(openVideo:false)
                if let id=initialVideoID ?? w.left.assets.first?.id { await w.left.select(id) }
            }
            if w.setup == nil { choosingLeft=false;choosing=true }
        }
        .sheet(isPresented:$choosing) {
            if let repository=library.repository {
                VideoSourcePicker(repository:repository,targetSession:session,excluding:choosingLeft ? workspace?.right.selectedVideoID:workspace?.left.selectedVideoID) { id in
                    choosing=false
                    Task {
                        if workspace?.setup == nil { await workspace?.load(initialVideoID:initialVideoID,secondVideoID:id) }
                        else { await workspace?.refreshAssets();await workspace?.replace(id,isLeft:choosingLeft) }
                    }
                } onCancel: { choosing=false;if workspace?.setup == nil { dismiss() } }
            }
        }
        .onDisappear { workspace?.stopAndSave() }
    }
}

struct ComparisonEditor:View {
    @ObservedObject var workspace:ComparisonWorkspace
    var choose:(Bool)->Void
    @Environment(\.scenePhase) private var phase
    var body:some View {
        GeometryReader { geo in
            VStack(spacing:6) {
                if workspace.setup != nil {
                    HStack {
                        Picker("布局",selection:Binding(get:{workspace.setup?.layout ?? "horizontal"},set:{workspace.setup?.layout=$0;workspace.changedSetup()})) {
                            Text("左右").tag("horizontal");Text("上下").tag("vertical")
                        }.pickerStyle(.segmented).accessibilityIdentifier("comparisonLayout")
                        Menu { NavigationLink("导出同屏视频") { ExportView(session:workspace.session,initialComparison:true) } } label: { Image(systemName:"square.and.arrow.up").frame(width:44,height:44) }.accessibilityLabel("导出同屏视频")
                    }.padding(.horizontal,8)
                    let horizontal=workspace.setup?.layout == "horizontal"
                    let layout=horizontal ? AnyLayout(HStackLayout(spacing:4)):AnyLayout(VStackLayout(spacing:4))
                    layout {
                        ComparisonSide(workspace:workspace.left,comparison:workspace,isLeft:true) { choose(true) }
                        ComparisonSide(workspace:workspace.right,comparison:workspace,isLeft:false) { choose(false) }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    VStack(spacing:4) {
                        Text(workspace.independent ? "独立定位 · 设同步点后联动播放":"联动 · 共享时间 \(workspace.time.formatted(.number.precision(.fractionLength(3)))) s")
                            .font(.caption.monospacedDigit()).accessibilityIdentifier("comparisonReadout")
                        if let range=workspace.range,range.upperBound>range.lowerBound {
                            Slider(value:Binding(get:{workspace.time},set:{workspace.seek($0)}),in:range,onEditingChanged:{editing in if !editing { workspace.save() } }).accessibilityIdentifier("comparisonSlider")
                        }
                        HStack {
                            Button { workspace.loop.toggle() } label: { Image(systemName:"repeat").frame(width:44,height:44).foregroundStyle(workspace.loop ? Theme.rose:.white) }.accessibilityLabel("切换循环")
                            FrameStepButton(direction:-1) { workspace.step(-1) }
                            Spacer()
                            Button { if workspace.playing { workspace.pause();workspace.seek(workspace.time) } else { workspace.play() } } label: { Image(systemName:workspace.playing ? "pause.fill":"play.fill").font(.title2).frame(width:44,height:44) }.accessibilityLabel(workspace.playing ? "暂停":"联动播放").accessibilityIdentifier("comparisonPlay")
                            Spacer()
                            FrameStepButton(direction:1) { workspace.step(1) }
                            Menu { Picker("速度",selection:Binding(get:{workspace.setup?.rate ?? 1},set:{workspace.setRate($0)})) { ForEach([1.0,0.5,0.25,0.1,0.05],id:\.self) { Text("\($0.formatted())×").tag($0) } } } label: { Text("\((workspace.setup?.rate ?? 1).formatted())×").frame(minWidth:44,minHeight:44) }
                        }
                    }.padding(.horizontal,12).background(Color(white:0.08))
                    Text("人体结果为画面辅助估算，请逐帧复核点位。").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Spacer();EmptyPanel(icon:"rectangle.split.2x1",title:"将两次动作放在一起",detail:"选择第二段本机视频，设置同步点后联动播放。")
                    Button("选择第二段视频") { choose(false) };Spacer()
                }
                if let issue=workspace.issue { Text(issue).font(.caption).foregroundStyle(.orange).padding(8) }
            }.background(.black)
            .onAppear { workspace.resumeFrames();workspace.adaptLayout(width:geo.size.width,height:geo.size.height) }
            .onChange(of:workspace.setup != nil) { _,ready in if ready { workspace.adaptLayout(width:geo.size.width,height:geo.size.height) } }
        }.onChange(of:phase) { _,value in if value != .active { workspace.stopAndSave() } else { workspace.resumeFrames() } }
    }
}

struct ComparisonSide:View {
    @ObservedObject var workspace:AnalysisWorkspace
    @ObservedObject var comparison:ComparisonWorkspace
    let isLeft:Bool
    var choose:()->Void
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Text(isLeft ? "A":"B").font(.caption.bold())
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
            AnalysisCanvas(workspace:workspace).frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
            HStack(spacing:8) {
                Text("\(workspace.time,specifier:"%.3f")s").font(.caption2.monospacedDigit()).frame(minWidth:44)
                if workspace.metadata != nil {
                    Slider(value:Binding(get:{workspace.time},set:{comparison.independentSeek($0,isLeft:isLeft)}),in:workspace.clip.start.seconds...max(workspace.clip.start.seconds+0.001,workspace.clip.end.seconds),onEditingChanged:{editing in if !editing { workspace.endScrubbing() } }).accessibilityIdentifier(isLeft ? "leftSlider":"rightSlider")
                }
                Button("同步点") { comparison.anchor(isLeft:isLeft) }.font(.caption).frame(minHeight:44).accessibilityIdentifier(isLeft ? "leftAnchor":"rightAnchor")
                Menu { Button("−1 帧偏移") { comparison.frameOffset(-1,isLeft:isLeft) };Button("+1 帧偏移") { comparison.frameOffset(1,isLeft:isLeft) } } label: { Image(systemName:"plusminus").frame(width:44,height:44) }.accessibilityLabel("微调同步点")
            }.padding(.horizontal,8).background(Color(white:0.08))
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}
