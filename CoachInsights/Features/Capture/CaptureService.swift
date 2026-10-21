import SwiftUI
import AVFoundation
import UIKit

struct RecordingFormat: Identifiable, Equatable {
    let id: Int
    let width: Int32
    let height: Int32
    let fps: Int
    var label: String { "\(width) × \(height) · \(fps) fps" }
}

struct CaptureAuthorization {
    var camera:() async -> Bool
    var microphone:() async -> Bool
    static var live:CaptureAuthorization {
        CaptureAuthorization(camera:{
            #if targetEnvironment(simulator)
            return true // Availability is reported separately; there is no simulator camera.
            #else
            return await AVCaptureDevice.requestAccess(for:.video)
            #endif
        },microphone:{await AVCaptureDevice.requestAccess(for:.audio)})
    }
}

@MainActor final class CaptureService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    // Hardware mutations are confined to queue; the main thread only attaches the preview layer.
    nonisolated(unsafe) let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.coachinsights.capture")
    nonisolated(unsafe) private let output = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private var camera: AVCaptureDevice?
    nonisolated(unsafe) private var microphoneInput: AVCaptureDeviceInput?
    private var observations: [NSObjectProtocol] = []
    @Published var formats: [RecordingFormat] = []
    @Published var selectedFormat: Int = 0
    @Published var available = false
    @Published var recording = false
    @Published var audioEnabled = false
    @Published var issue: String?
    @Published var reviewURL: URL?
    private var stopping = false
    private let authorization:CaptureAuthorization
    init(authorization:CaptureAuthorization = .live) {
        self.authorization=authorization
        super.init()
        observations.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop(); self?.issue = "拍摄已中断，已结束当前录制。可以回看已保存片段或重试。" }
        })
        observations.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop(); self?.stopSession() }
        })
        observations.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] notification in
            Task { @MainActor in self?.issue = "相机暂时不可用，请重试。"; self?.recording = false }
        })
    }
    func prepare() async {
        guard await authorization.camera() else { issue = "未允许使用相机。可在系统设置中开启，也可以直接导入视频。"; return }
        #if targetEnvironment(simulator)
        issue = "模拟器没有相机。可导入视频完成分析。"; return
        #else
        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw MediaFailure.noVideo }
            camera = device
            let input = try AVCaptureDeviceInput(device: device)
            try await perform {
                self.session.beginConfiguration(); defer { self.session.commitConfiguration() }
                if self.session.inputs.isEmpty {
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else { throw MediaFailure.readFailed }
                    self.session.sessionPreset = .inputPriority; self.session.addInput(input); self.session.addOutput(self.output)
                }
            }
            var options: [RecordingFormat] = []
            for (index, format) in device.formats.enumerated() {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                guard dimensions.width >= 1280, dimensions.width <= 1920 else { continue }
                for fps in [30,60,120,240] where format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= Double(fps) && $0.maxFrameRate >= Double(fps) }) {
                    let option = RecordingFormat(id:index*1000+fps,width:dimensions.width,height:dimensions.height,fps:fps)
                    if !options.contains(where: { $0.width == option.width && $0.height == option.height && $0.fps == fps }) { options.append(option) }
                }
            }
            formats = options.sorted { ($0.fps,$0.width) < ($1.fps,$1.width) }
            guard let preferred = formats.first(where: { $0.width == 1920 && $0.fps == 60 }) ?? formats.first else { throw MediaFailure.readFailed }
            selectedFormat = preferred.id; try await applyFormat(preferred.id)
            await startSession(); available = true; issue = nil
        } catch { issue = error.localizedDescription }
        #endif
    }
    func applyFormat(_ id: Int) async throws {
        guard !recording, let camera, let option = formats.first(where: { $0.id == id }) else { return }
        try await perform {
            try camera.lockForConfiguration(); defer { camera.unlockForConfiguration() }
            camera.activeFormat = camera.formats[id/1000]
            camera.activeVideoMinFrameDuration = CMTime(value:1,timescale:Int32(option.fps))
            camera.activeVideoMaxFrameDuration = CMTime(value:1,timescale:Int32(option.fps))
        }
    }
    func setAudio(_ enabled: Bool) async {
        guard !recording else { return }
        let allowed = enabled ? await authorization.microphone() : false
        if enabled && !allowed { issue = "麦克风未授权，继续无声拍摄。" }
        do {
            let input: AVCaptureDeviceInput?
            if allowed, let device = AVCaptureDevice.default(for: .audio) { input = try AVCaptureDeviceInput(device: device) } else { input = nil }
            try await perform {
                self.session.beginConfiguration(); defer { self.session.commitConfiguration() }
                if let old = self.microphoneInput { self.session.removeInput(old); self.microphoneInput = nil }
                if let input, self.session.canAddInput(input) { self.session.addInput(input); self.microphoneInput = input }
            }
            audioEnabled = microphoneInput != nil
        } catch { issue = error.localizedDescription; audioEnabled = false }
    }
    func start() {
        guard available, !recording else { return }
        let url = URL.temporaryDirectory.appendingPathComponent("Recording-\(UUID().uuidString).mov")
        let interface=(UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .portrait
        let angle=CameraOrientation.angle(device:UIDevice.current.orientation,interface:interface)
        recording = true; reviewURL = nil; stopping = false
        queue.async {
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            self.output.startRecording(to: url, recordingDelegate: self)
        }
    }
    func stop() { guard recording, !stopping else { return }; stopping = true; queue.async { self.output.stopRecording() } }
    func startSession() async { try? await perform { if !self.session.isRunning { self.session.startRunning() } } }
    func stopSession() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            recording = false; stopping = false
            let succeeded = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            if succeeded { reviewURL = outputFileURL }
            else { issue = error?.localizedDescription ?? "录制失败，请重试。"; try? FileManager.default.removeItem(at: outputFileURL) }
        }
    }
    private func perform(_ operation: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            queue.async { do { try operation(); continuation.resume() } catch { continuation.resume(throwing:error) } }
        }
    }
    deinit { for observer in observations { NotificationCenter.default.removeObserver(observer) } }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> Preview { let view=Preview(); view.layerView.session=session; view.layerView.videoGravity = .resizeAspect; return view }
    func updateUIView(_ uiView: Preview, context: Context) { uiView.setNeedsLayout() }
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layerView: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            let angle=CameraOrientation.angle(device:UIDevice.current.orientation,interface:window?.windowScene?.interfaceOrientation ?? .portrait)
            if let connection=layerView.connection,connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle=angle }
        }
    }
}

enum CameraOrientation {
    static func angle(device:UIDeviceOrientation,interface:UIInterfaceOrientation)->CGFloat {
        switch device {
        case .landscapeLeft:return 0
        case .landscapeRight:return 180
        case .portrait:return 90
        case .portraitUpsideDown:return 270
        default:
            switch interface {
            case .landscapeLeft:return 180
            case .landscapeRight:return 0
            case .portraitUpsideDown:return 270
            default:return 90
            }
        }
    }
}
