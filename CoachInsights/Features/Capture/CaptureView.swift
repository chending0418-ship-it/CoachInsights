import SwiftUI
import AVKit

struct CaptureView: View {
    var session: AnalysisSession? = nil
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CaptureService()
    @State private var sport = Sport.batting
    @State private var name = ""
    @State private var saving = false
    @State private var task: Task<Void,Never>?
    @State private var progress: Double = 0
    @State private var savedSession: AnalysisSession?
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let url = camera.reviewURL { VideoPlayer(player: AVPlayer(url:url)).frame(height: 280) }
                else if camera.available { CameraPreview(session:camera.session).frame(height:320).background(.black) }
                else { EmptyPanel(icon:"video.slash",title:"准备拍摄",detail:camera.issue ?? "正在检查相机…") }
                if camera.available {
                    Picker("录制格式",selection:$camera.selectedFormat) { ForEach(camera.formats) { Text($0.label).tag($0.id) } }
                        .disabled(camera.recording).onChange(of:camera.selectedFormat) { _,id in Task { do { try await camera.applyFormat(id) } catch { camera.issue=error.localizedDescription } } }
                    Toggle(camera.audioEnabled ? "录音已开启" : "无声拍摄",isOn:Binding(get:{camera.audioEnabled},set:{ value in Task { await camera.setAudio(value) } })).disabled(camera.recording)
                    Button(camera.recording ? "停止录制" : "开始录制",systemImage:camera.recording ? "stop.circle.fill" : "record.circle") { if camera.recording { camera.stop() } else { camera.start() } }.buttonStyle(.borderedProminent)
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                    Button("模拟录制片段") { Task {
                        do {
                            let url=URL.temporaryDirectory.appendingPathComponent("Capture-\(UUID().uuidString).mov")
                            try await FixtureFactory.video(at:url,times:(0..<60).map{Double($0)/60},duration:1)
                            camera.reviewURL=url
                        } catch { camera.issue=error.localizedDescription }
                    } }.accessibilityIdentifier("simulateCapture")
                }
                #endif
                if camera.reviewURL != nil {
                    if session == nil {
                        TextField("分析名称",text:$name).textFieldStyle(.roundedBorder)
                        Picker("运动类型",selection:$sport) { ForEach(Sport.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    }
                    Button("保存并分析",systemImage:"checkmark.circle") { save() }.buttonStyle(.borderedProminent).disabled(saving).accessibilityIdentifier("saveCapture")
                    Button("重新拍摄") { if let url=camera.reviewURL { try? FileManager.default.removeItem(at:url) }; camera.reviewURL=nil }.disabled(saving)
                }
                if saving { ProgressView("保存本机副本…",value:progress); Button("取消保存") { task?.cancel() } }
                if let issue=camera.issue, camera.available { Text(issue).foregroundStyle(.secondary) }
                if !camera.available { Button("重试相机") { Task { await camera.prepare() } } }
                if let savedSession { NavigationLink("进入分析",destination:SessionDetail(session:savedSession)).accessibilityIdentifier("openCapturedAnalysis") }
            }.padding().frame(maxWidth:850).frame(maxWidth:.infinity)
        }.background(Theme.paper).navigationTitle("拍摄与回看").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("完成") { camera.stop(); dismiss() } } }
        .task { await camera.prepare() }
        .onDisappear { camera.stop(); camera.stopSession(); task?.cancel() }
        .onChange(of:scenePhase) { _,phase in if phase == .active { Task { if camera.available { await camera.startSession() } } } }
    }
    private func save() {
        guard let url=camera.reviewURL,let repository=library.repository else { return }
        saving=true
        task=Task {
            var created: AnalysisSession?
            defer { saving=false }
            do {
                let target: AnalysisSession
                if let session { target=session }
                else { target=try repository.create(name:name,sport:sport); created=target }
                _=try await repository.importVideo(url,into:target) { value in Task { @MainActor in progress=value } }
                library.reload(); savedSession=target
                if session != nil { dismiss() }
            } catch {
                if let created { try? await repository.delete(created) }
                camera.issue=error is CancellationError ? "已取消保存，可重试。" : error.localizedDescription
            }
        }
    }
}
