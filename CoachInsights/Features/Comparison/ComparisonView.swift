import SwiftUI

struct ComparisonView: View {
    let session:AnalysisSession
    @EnvironmentObject private var library:LibraryStore
    @State private var workspace:ComparisonWorkspace?
    var body:some View {
        Group {
            if let workspace { ComparisonEditor(workspace:workspace) }
            else { ProgressView() }
        }.navigationTitle("双视频对比").navigationBarTitleDisplayMode(.inline)
        .task { if let repository=library.repository { let w=ComparisonWorkspace(session:session,repository:repository);workspace=w;await w.load() } }
        .onDisappear { workspace?.pause();workspace?.save() }
    }
}

struct ComparisonEditor:View {
    @ObservedObject var workspace:ComparisonWorkspace
    @Environment(\.scenePhase) private var phase
    var body:some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing:14) {
                    if workspace.setup != nil {
                        Picker("布局",selection:Binding(get:{workspace.setup?.layout ?? "horizontal"},set:{workspace.setup?.layout=$0;workspace.changedSetup()})) {
                            Text("左右").tag("horizontal");Text("上下").tag("vertical")
                        }.pickerStyle(.segmented).accessibilityIdentifier("comparisonLayout")
                        let horizontal=workspace.setup?.layout == "horizontal"
                        let layout=horizontal ? AnyLayout(HStackLayout(spacing:8)):AnyLayout(VStackLayout(spacing:12))
                        layout {
                            ComparisonSide(workspace:workspace.left,comparison:workspace,isLeft:true,height:horizontal ? max(160,min(geometry.size.height*0.5,400)):260)
                            ComparisonSide(workspace:workspace.right,comparison:workspace,isLeft:false,height:horizontal ? max(160,min(geometry.size.height*0.5,400)):260)
                        }
                        if let range=workspace.range {
                            Text("共享时间 \(workspace.time, specifier:"%.3f") s · 同步差 \(workspace.drift*1000,specifier:"%.0f") ms").font(.caption.monospacedDigit()).accessibilityIdentifier("comparisonReadout")
                            if range.upperBound>range.lowerBound {
                                Slider(value:Binding(get:{workspace.time},set:{workspace.seek($0)}),in:range).accessibilityIdentifier("comparisonSlider")
                            }
                            HStack {
                                Button("前一帧",systemImage:"backward.end.fill") { workspace.step(-1) }.labelStyle(.iconOnly)
                                Spacer()
                                Button(workspace.playing ? "暂停":"联动播放",systemImage:workspace.playing ? "pause.fill":"play.fill") { if workspace.playing { workspace.pause();workspace.seek(workspace.time) } else { workspace.play() } }.accessibilityIdentifier("comparisonPlay")
                                Spacer()
                                Button("后一帧",systemImage:"forward.end.fill") { workspace.step(1) }.labelStyle(.iconOnly)
                            }.buttonStyle(.bordered)
                            HStack {
                                Toggle("循环",isOn:$workspace.loop).fixedSize();Spacer()
                                Picker("速度",selection:Binding(get:{workspace.setup?.rate ?? 1},set:{workspace.setup?.rate=$0;workspace.changedSetup()})) {
                                    ForEach([1.0,0.5,0.25,0.1,0.05],id:\.self) { Text("\($0.formatted())×").tag($0) }
                                }
                            }
                        }
                        Text("分别定位两路动作节点，设为同步点；共享时间 0 表示这两个节点。共同区间之外不会继续播放。")
                            .font(.caption).foregroundStyle(.secondary)
                        NavigationLink("导出同屏视频") { ExportView(session:workspace.session,initialComparison:true) }
                    } else {
                        EmptyPanel(icon:"rectangle.split.2x1",title:"将两次动作放在一起",detail:"先在分析记录中导入两段本机视频，然后选择同步节点。")
                    }
                    if let issue=workspace.issue { Text(issue).foregroundStyle(.red) }
                }.padding().frame(maxWidth:1400).frame(maxWidth:.infinity)
            }.background(Theme.paper)
        }
        .onChange(of:phase) { _,value in if value != .active { workspace.pause();workspace.save() } }
    }
}

struct ComparisonSide:View {
    @ObservedObject var workspace:AnalysisWorkspace
    @ObservedObject var comparison:ComparisonWorkspace
    let isLeft:Bool
    let height:CGFloat
    var body:some View {
        VStack(spacing:8) {
            Picker(isLeft ? "左路素材":"右路素材",selection:Binding(get:{workspace.selectedVideoID ?? UUID()},set:{id in Task { await comparison.replace(id,isLeft:isLeft) }})) {
                ForEach(workspace.assets) { Text($0.originalName).lineLimit(1).truncationMode(.middle).tag($0.id) }
            }.font(.caption)
            AnalysisCanvas(workspace:workspace).frame(height:height).clipShape(RoundedRectangle(cornerRadius:10))
            Text("\(workspace.time,specifier:"%.3f") s · 第 \(workspace.frameIndex+1) 帧").font(.caption.monospacedDigit())
            if let metadata=workspace.metadata {
                Slider(value:Binding(get:{Double(workspace.frameIndex)},set:{comparison.pause();workspace.seek(frame:Int($0))}),in:0...Double(max(1,metadata.timeline.frames.count-1)),step:1)
            }
            Button("设为同步点") { comparison.anchor(isLeft:isLeft) }.font(.caption).accessibilityIdentifier(isLeft ? "leftAnchor":"rightAnchor")
            HStack {
                Button("−1 帧偏移") { comparison.offset(-(workspace.metadata?.timeline.frames[safe:workspace.frameIndex]?.duration.seconds ?? 1/30),isLeft:isLeft) }
                Button("+1 帧偏移") { comparison.offset(workspace.metadata?.timeline.frames[safe:workspace.frameIndex]?.duration.seconds ?? 1/30,isLeft:isLeft) }
            }.font(.caption2)
            Menu("画面与片段") {
                Button("镜像") { comparison.pause();var value=workspace.viewSettings;value.mirrored.toggle();workspace.updateView(value) }
                Button("旋转 90°") { comparison.pause();var value=workspace.viewSettings;value.quarterTurns+=1;workspace.updateView(value) }
                Button("放大") { comparison.pause();var value=workspace.viewSettings;value.zoom=min(8,value.zoom+0.5);workspace.updateView(value) }
                Button("中心裁切 80%") { comparison.pause();var value=workspace.viewSettings;value.crop=[0.1,0.1,0.8,0.8];workspace.updateView(value) }
                Button("复位画面") { workspace.updateView(ViewSettings()) }
                Button("当前帧设为片段起点") { comparison.trim(isLeft:isLeft,start:true) }
                Button("当前帧设为片段终点") { comparison.trim(isLeft:isLeft,start:false) }
            }.font(.caption)
        }.frame(maxWidth:.infinity)
    }
}
