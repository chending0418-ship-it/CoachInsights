import SwiftUI

struct PoseSettingsPanel: View {
    @ObservedObject var workspace: AnalysisWorkspace
    @Binding var region: [Double]
    @State private var advanced=false
    private var statusMessage:String { workspace.poseBusy ? "正在本机逐帧分析…" : workspace.issue ?? workspace.notice ?? "选定片段与主体区域后开始分析。" }
    var body: some View {
                VStack(alignment: .leading, spacing: 14) {
            Section("指定分析区域") {
                Text("当前框选 · 宽 \(Int(region[2] * 100))% × 高 \(Int(region[3] * 100))%")
                    .font(.subheadline.weight(.semibold))
                DisclosureGroup("精调区域", isExpanded: $advanced) {
                ForEach(0..<4,id:\.self) { i in
                    VStack(alignment:.leading) {
                        Text("\(["左边距","上边距","宽度","高度"][i]) \(Int(region[i]*100))%")
                        Slider(value:$region[i],in:i<2 ? 0...0.9 : 0.1...1,step:0.01)
                    }
                }.disabled(workspace.poseBusy)
                }
                Button("应用区域") {
                    region[2]=min(region[2],1-region[0]); region[3]=min(region[3],1-region[1])
                    workspace.poseSettings.region=region; workspace.save()
                }.disabled(workspace.poseBusy)
                Button("恢复全画面") { region=[0,0,1,1];workspace.poseSettings.region=region;workspace.save() }.disabled(workspace.poseBusy)
            }
            Section("人体识别 · 辅助估算") {
                Toggle("显示骨架与角度",isOn:Binding(get:{workspace.poseSettings.visible && workspace.overlaysVisible},set:{ value in
                    workspace.poseSettings.visible=value
                    if value { workspace.overlaysVisible=true }
                    workspace.save()
                }))
                Picker("识别引擎",selection:$workspace.poseSettings.engine) {
                    Text("Apple Vision（不可用时自动切换）").tag("Apple Vision")
                    Text("MediaPipe Full · 本机模型").tag(MediaPipePoseEngine.identity)
                }.disabled(workspace.poseBusy)
                VStack(alignment:.leading) {
                    Text("关节最低置信度 \(workspace.poseSettings.minimumConfidence, specifier:"%.2f")")
                    Slider(value:$workspace.poseSettings.minimumConfidence,in:0.3...0.9)
                }.disabled(workspace.poseBusy)
            }
            VStack(alignment:.leading,spacing:8) {
                if workspace.poseBusy {
                    ProgressView(value:workspace.poseProgress)
                    Button("取消分析") { workspace.poseTask?.cancel() }.accessibilityIdentifier("cancelPose")
                } else {
                    HStack {
                        Button("分析选定片段 · 无需订阅") { workspace.analyzePose() }.buttonStyle(DocumentButtonStyle(primary: true)).accessibilityIdentifier("runPose")
                        Button("重新分析") { workspace.analyzePose(force:true) }.buttonStyle(.bordered)
                    }
                }
                Text(PoseGuidance.limitations).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("poseLimitations")
                Text(statusMessage)
                    .font(.caption).accessibilityElement(children:.ignore).accessibilityLabel(statusMessage).accessibilityIdentifier("poseStatus")
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.notebookPanel()
    }
}

struct PoseRegionPicker:View {
    @ObservedObject var workspace: AnalysisWorkspace
    @Binding var region:[Double]
    @State private var start:CGPoint?
    var body:some View {
        GeometryReader { proxy in
            let imageSize = workspace.metadata?.displaySize ?? proxy.size
            let geometry = workspace.viewSettings.geometry(image: imageSize, viewport: proxy.size)
            let a = geometry.viewPoint(from: CGPoint(x: region[0], y: region[1]))
            let b = geometry.viewPoint(from: CGPoint(x: region[0] + region[2], y: region[1] + region[3]))
            ZStack {
                AnalysisCanvas(workspace: workspace)
                    .allowsHitTesting(false)
                Path(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).standardized)
                    .stroke(.cyan, lineWidth: 2)
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:5).onChanged { value in
                if start==nil { start=geometry.normalizedPoint(from:value.startLocation) }
                guard let start,let end=geometry.normalizedPoint(from:value.location,allowOutside:true) else { return }
                let x=min(1,max(0,end.x)),y=min(1,max(0,end.y))
                let left=min(start.x,x),top=min(start.y,y),width=abs(start.x-x),height=abs(start.y-y)
                if width>=0.05,height>=0.05 { region=[left,top,width,height] }
            }.onEnded { _ in start=nil })
        }.clipShape(RoundedRectangle(cornerRadius:10)).accessibilityIdentifier("poseRegionPicker")
    }
}
