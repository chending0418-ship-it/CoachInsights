import SwiftUI
import ARKit
import SceneKit
import AVFoundation

enum PocketDistanceMath {
    static func meters(from first: SIMD3<Float>, to second: SIMD3<Float>) -> Double? {
        guard [first.x, first.y, first.z, second.x, second.y, second.z].allSatisfy({ $0.isFinite }) else { return nil }
        let length = Double(simd_distance(first, second))
        return length >= 0.005 && length.isFinite ? length : nil
    }
}

@MainActor final class DistanceModel: ObservableObject {
    @Published var instruction = "缓慢移动设备，识别测量表面"
    @Published var canPlace = false
    @Published var hasStart = false
    @Published var result: DistanceRecord?
    @Published var liveMeters: Double?
    @Published var cameraAllowed = false
    @Published var denied = false
    @Published var command = 0
    @Published var resetCommand = 0
    var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func authorize() async {
        guard isSupported else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized { cameraAllowed = true }
        else if status == .notDetermined { cameraAllowed = await AVCaptureDevice.requestAccess(for: .video) }
        else { cameraAllowed = false }
        denied = !cameraAllowed
    }
}

struct DistanceView: View {
    @EnvironmentObject private var tools: QuickToolsStore
    @Environment(\.scenePhase) private var phase
    @StateObject private var model = DistanceModel()
    @State private var centimeters = false
    @State private var saved = false

    var body: some View {
        Group {
            if !model.isSupported {
                ContentUnavailableView {
                    Label("此设备不支持 AR 测距", systemImage: "ruler")
                } description: {
                    Text("请在支持 ARKit 的 iPhone 或 iPad 上使用。模拟器无法提供相机实景和真实距离。")
                }.accessibilityIdentifier("distanceUnavailable")
            } else if model.denied {
                ContentUnavailableView {
                    Label("需要相机权限", systemImage: "camera")
                } description: { Text("用相机识别实景表面并选取两个测量端点。") }
                actions: {
                    Button("打开设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } else if model.cameraAllowed {
                measurement
            } else { ProgressView("准备相机…") }
        }
        .navigationTitle("测距").navigationBarTitleDisplayMode(.inline)
        .task { await model.authorize() }
        .onChange(of: model.result?.id) { _, _ in saved = false }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await model.authorize() } }
        }
        .safeAreaInset(edge: .bottom) { QuickSaveIssueView() }
    }

    private var measurement: some View {
        ZStack {
            ARDistanceCamera(model: model, active: phase == .active).ignoresSafeArea(edges: .bottom)
            Image(systemName: "plus").font(.system(size: 32, weight: .light))
                .foregroundStyle(model.canPlace ? Theme.burgundy : .white.opacity(0.7)).allowsHitTesting(false)
            VStack(spacing: 16) {
                Text(model.instruction).font(.subheadline).padding(12)
                    .background(.ultraThinMaterial, in: Capsule()).padding(.top, 12)
                Spacer()
                if let value = model.result?.meters ?? model.liveMeters {
                    Text(centimeters ? String(format: "%.1f 厘米", value * 100) : String(format: "%.2f 米", value))
                        .font(.system(size: 48, weight: .light)).monospacedDigit()
                        .padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityIdentifier("distanceReadout")
                }
                Text("AR 估算距离 · 请复核").font(.caption).padding(6).background(.ultraThinMaterial, in: Capsule())
                HStack(spacing: 24) {
                    Button {
                        model.resetCommand += 1; saved = false
                    } label: { Label("重测", systemImage: "arrow.counterclockwise") }
                    Button {
                        model.command += 1
                    } label: {
                        Image(systemName: "plus").font(.title).frame(width: 64, height: 64)
                            .background(model.canPlace ? Theme.burgundy : Color.gray, in: Circle()).foregroundStyle(.white)
                    }.disabled(!model.canPlace || model.result != nil)
                        .accessibilityLabel(model.hasStart ? "确定终点" : "确定起点").accessibilityIdentifier("distancePlace")
                    Button(centimeters ? "厘米" : "米") { centimeters.toggle() }.frame(minWidth: 48, minHeight: 44)
                }.buttonStyle(.plain)
                if let result = model.result {
                    Button(saved ? "已保存到记录" : "保存测距记录") {
                        tools.saveDistance(result); saved = tools.issue == nil
                    }.buttonStyle(.borderedProminent).disabled(saved).accessibilityIdentifier("distanceSave")
                }
            }.padding(20).foregroundStyle(Theme.burgundy)
        }.background(Theme.paper).preferredColorScheme(.light).environment(\.colorScheme, .light)
    }
}

private struct ARDistanceCamera: UIViewControllerRepresentable {
    @ObservedObject var model: DistanceModel
    let active: Bool
    func makeUIViewController(context: Context) -> DistanceCameraController { DistanceCameraController(model: model) }
    func updateUIViewController(_ controller: DistanceCameraController, context: Context) {
        DispatchQueue.main.async {
            controller.setActive(active)
            if controller.handledReset != model.resetCommand {
                controller.handledReset = model.resetCommand; controller.reset()
            }
            if controller.handledCommand != model.command {
                controller.handledCommand = model.command; controller.place()
            }
        }
    }
    static func dismantleUIViewController(_ controller: DistanceCameraController, coordinator: ()) { controller.teardown() }
}

private final class DistanceCameraController: UIViewController, ARSessionDelegate {
    let sceneView = ARSCNView(frame: .zero)
    let model: DistanceModel
    var handledCommand = 0
    var handledReset = 0
    private var timer: Timer?
    private var running = false
    private var hasAppeared = false
    private var requestedActive = true
    private var start: SIMD3<Float>?
    private var target: SIMD3<Float>?
    private let marks = SCNNode()
    private var normalTracking = false

    init(model: DistanceModel) { self.model = model; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view = sceneView; sceneView.scene = SCNScene(); sceneView.scene.rootNode.addChildNode(marks)
        sceneView.session.delegate = self; sceneView.session.delegateQueue = .main
        sceneView.automaticallyUpdatesLighting = true
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); hasAppeared = true; setActive(requestedActive)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); hasAppeared = false; stop()
    }
    func setActive(_ value: Bool) {
        requestedActive = value
        guard hasAppeared else { return }
        if value && !running {
            running = true
            // A new world coordinate frame invalidates unfinished endpoints.
            reset()
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.sample() }
        } else if !value { stop() }
    }
    func stop() {
        timer?.invalidate(); timer = nil; sceneView.session.pause(); running = false
    }
    func teardown() { hasAppeared = false; requestedActive = false; stop() }
    func reset() {
        start = nil; target = nil; normalTracking = false
        marks.childNodes.forEach { $0.removeFromParentNode() }
        model.result = nil; model.liveMeters = nil; model.hasStart = false; model.canPlace = false
        model.instruction = "缓慢移动设备，识别测量表面"
    }
    private func sample() {
        guard running, model.result == nil else { return }
        if case .normal = sceneView.session.currentFrame?.camera.trackingState { normalTracking = true }
        else { normalTracking = false }
        guard normalTracking else { model.canPlace = false; model.liveMeters = nil; return }
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        guard let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any),
              let result = sceneView.session.raycast(query).first else {
            target = nil; model.canPlace = false; model.liveMeters = nil
            model.instruction = "将十字准星对准清晰的地面或物体表面"
            return
        }
        let column = result.worldTransform.columns.3
        target = SIMD3(column.x, column.y, column.z)
        model.canPlace = true
        model.instruction = start == nil ? "对准起点，点击 ＋" : "对准终点，点击 ＋"
        if let start, let target {
            model.liveMeters = PocketDistanceMath.meters(from: start, to: target)
            draw(from: start, to: target)
        }
    }
    func place() {
        sample()
        guard model.canPlace, let target, model.result == nil else { return }
        if let start {
            guard let meters = PocketDistanceMath.meters(from: start, to: target) else {
                model.instruction = "两个端点太近，请重新选择终点"; return
            }
            draw(from: start, to: target); model.result = DistanceRecord(meters: meters)
            model.canPlace = false; model.instruction = "测量完成，可保存或重新测量"
        } else {
            start = target; model.hasStart = true; model.instruction = "对准终点，点击 ＋"
            draw(from: target, to: target)
        }
    }
    private func draw(from first: SIMD3<Float>, to second: SIMD3<Float>) {
        marks.childNodes.forEach { $0.removeFromParentNode() }
        for point in [first, second] {
            let node = SCNNode(geometry: SCNSphere(radius: 0.007))
            node.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
            node.geometry?.firstMaterial?.lightingModel = .constant
            node.simdPosition = point; marks.addChildNode(node)
        }
        let vector = second - first, length = simd_length(vector)
        guard length > 0.001 else { return }
        let line = SCNNode(geometry: SCNCylinder(radius: 0.002, height: CGFloat(length)))
        line.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
        line.geometry?.firstMaterial?.lightingModel = .constant
        line.simdPosition = (first + second) / 2
        line.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: vector / length)
        marks.addChildNode(line)
    }
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        guard model.result == nil else { return }
        switch camera.trackingState {
        case .normal: break
        case .notAvailable: model.instruction = "暂时无法追踪，请点击重测"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion: model.instruction = "请缓慢移动设备"
            case .insufficientFeatures: model.instruction = "请对准光线充足、有纹理的表面"
            default: model.instruction = "正在识别环境，请缓慢移动设备"
            }
        }
    }
    func sessionWasInterrupted(_ session: ARSession) {
        model.canPlace = false; model.instruction = "相机已中断，恢复后请重新测量"
    }
    func sessionInterruptionEnded(_ session: ARSession) { stop(); setActive(true) }
    func session(_ session: ARSession, didFailWithError error: Error) {
        model.canPlace = false; model.instruction = "测距未能继续：" + error.localizedDescription
    }
}

struct SavedDistanceView: View {
    let record: DistanceRecord
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "ruler").font(.largeTitle).foregroundStyle(Theme.burgundy)
            Text(record.summary).font(.system(size: 64, weight: .light)).monospacedDigit()
            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            Text("AR 估算距离 · 请复核").font(.footnote).foregroundStyle(.secondary)
        }.padding(24).navigationTitle("测距记录").navigationBarTitleDisplayMode(.inline)
    }
}
