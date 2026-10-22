import SwiftUI

struct PoseToolsView: View {
    @ObservedObject var workspace: AnalysisWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var advanced=false
    @State private var region = [0.0,0.0,1.0,1.0]
    private var statusMessage:String { workspace.poseBusy ? "正在本机逐帧分析…" : workspace.issue ?? workspace.notice ?? "选定片段与主体区域后开始分析。" }
    var body: some View {
        Form {
            Section("人体识别 · 辅助估算") {
                Text(PoseGuidance.limitations)
                    .font(.callout).accessibilityIdentifier("poseLimitations")
                Toggle("显示骨架与角度",isOn:Binding(get:{workspace.poseSettings.visible && workspace.overlaysVisible},set:{ value in
                    workspace.poseSettings.visible=value
                    if value { workspace.overlaysVisible=true }
                    workspace.save()
                }))
                DisclosureGroup("高级设置",isExpanded:$advanced) {
                Picker("识别引擎",selection:$workspace.poseSettings.engine) {
                    Text("Apple Vision（不可用时自动切换）").tag("Apple Vision")
                    Text("MediaPipe Full · 本机模型").tag(MediaPipePoseEngine.identity)
                }.disabled(workspace.poseBusy)
                VStack(alignment:.leading) {
                    Text("关节最低置信度 \(workspace.poseSettings.minimumConfidence, specifier:"%.2f")")
                    Slider(value:$workspace.poseSettings.minimumConfidence,in:0.3...0.9)
                }.disabled(workspace.poseBusy)
                }
            }
            Section("指定分析区域") {
                if let frame=workspace.frame {
                    PoseRegionPicker(image:UIImage(cgImage:frame.image),region:$region).frame(height:240)
                        .disabled(workspace.poseBusy)
                    Text("在画面上拖出矩形，再点应用区域。").font(.caption).foregroundStyle(.secondary)
                }
                Text("用画面百分比框住一个完整人体。区域内出现多人或主体明显跳变时，该帧留空。")
                    .font(.caption).foregroundStyle(.secondary)
                if advanced {
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
        }.safeAreaInset(edge:.bottom) {
            VStack(alignment:.leading,spacing:8) {
                if workspace.poseBusy {
                    ProgressView(value:workspace.poseProgress)
                    Button("取消分析") { workspace.poseTask?.cancel() }.accessibilityIdentifier("cancelPose")
                } else {
                    HStack {
                        Button("分析选定片段 · 无需订阅") { workspace.analyzePose() }.buttonStyle(.borderedProminent).accessibilityIdentifier("runPose")
                        Button("重新分析") { workspace.analyzePose(force:true) }.buttonStyle(.bordered)
                    }
                }
                Text(statusMessage)
                    .font(.caption).accessibilityElement(children:.ignore).accessibilityLabel(statusMessage).accessibilityIdentifier("poseStatus")
            }.frame(maxWidth:.infinity,alignment:.leading).padding().background(.regularMaterial)
        }.navigationTitle("人体分析").toolbar { Button("完成") { workspace.save();dismiss() } }
        .onAppear { region=workspace.poseSettings.region }
        .onDisappear { workspace.save() }
    }
}

private struct PoseRegionPicker:View {
    let image:UIImage
    @Binding var region:[Double]
    @State private var start:CGPoint?
    var body:some View {
        GeometryReader { proxy in
            let geometry=VideoGeometry(imageSize:image.size,viewportSize:proxy.size)
            ZStack {
                Color.black
                Image(uiImage:image).resizable().scaledToFit()
                Canvas { context,_ in
                    let a=geometry.viewPoint(from:CGPoint(x:region[0],y:region[1]))
                    let b=geometry.viewPoint(from:CGPoint(x:region[0]+region[2],y:region[1]+region[3]))
                    context.stroke(Path(CGRect(x:a.x,y:a.y,width:b.x-a.x,height:b.y-a.y)),with:.color(.cyan),lineWidth:2)
                }
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
