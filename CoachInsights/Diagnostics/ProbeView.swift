#if DEBUG
import AVFoundation
import SwiftUI

struct ProbeReport: Codable {
    var sample: String
    var frames: Int
    var displayWidth: Double
    var displayHeight: Double
    var frameTimes: [Double]
    var exactFrameErrorsMS: [Double]
    var frameLatencyMS: [Double]
    var dualMaximumDriftMS: Double
    var dualElapsedSeconds: Double
    var visionMS: [Double]
    var visionVisibleJoints: [Int]
    var visionStatus: String
    var visionFailure: String?
    var cacheBytes: Int
    var residentMemoryBytes: UInt64
    var simulatorModel: String
    var systemVersion: String
    var simulator: Bool = true
}
@MainActor enum MediaProbe {
    static func run(url: URL) async throws -> (ProbeReport, CGImage) {
        let asset = AVURLAsset(url: url)
        let metadata = try await MediaInspector().inspect(asset: asset)
        let provider = FrameProvider(asset: asset, metadata: metadata)
        var errors: [Double] = [], latencies: [Double] = [], visionTimes: [Double] = [], joints: [Int] = []
        var sampledMemory = residentMemory()
        var image: CGImage?
        let vision = VisionProbe()
        var visionFailure: String?
        let indices = Array(Set([0, metadata.timeline.frames.count / 4, metadata.timeline.frames.count / 2,
                                 metadata.timeline.frames.count * 3 / 4, metadata.timeline.frames.count - 1])).sorted()
        for index in indices {
            let start = CFAbsoluteTimeGetCurrent()
            let frame = try await provider.frame(at: index)
            latencies.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            errors.append(abs(frame.actualTime.seconds - frame.requestedTime.seconds) * 1000)
            if visionFailure == nil {
                let poseStart = CFAbsoluteTimeGetCurrent()
                do {
                    let pose = try await vision.analyze(frame.image, time: frame.actualTime)
                    visionTimes.append((CFAbsoluteTimeGetCurrent() - poseStart) * 1000)
                    joints.append(pose.joints.filter { $0.confidence >= 0.3 }.count)
                } catch {
                    let failure = error as NSError
                    guard failure.domain == "com.apple.Vision", failure.code == 9 else { throw error }
                    // Capability probe: setup failure is unavailable inference, never "no person".
                    visionFailure = "\(failure.domain) \(failure.code): \(failure.localizedDescription)"
                }
            }
            image = frame.image
            sampledMemory = max(sampledMemory, residentMemory())
        }
        let left = PlaybackCoordinator(asset: asset, timeline: metadata.timeline)
        let right = PlaybackCoordinator(asset: asset, timeline: metadata.timeline)
        let duration = metadata.timeline.duration.seconds
        let dual = DualPlaybackCoordinator(left: left, right: right,
            clock: ComparisonClock(leftAnchor: 0, rightAnchor: 0, leftRange: 0...duration, rightRange: 0...duration))
        try await dual.prepare(at: 0)
        try dual.start(at: 0, rate: 0.5)
        defer { dual.pause() }
        var drift = 0.0
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(75))
            drift = max(drift, dual.drift)
            sampledMemory = max(sampledMemory, residentMemory())
        }
        let report = ProbeReport(sample: url.lastPathComponent, frames: metadata.timeline.frames.count,
            displayWidth: metadata.displayWidth, displayHeight: metadata.displayHeight,
            frameTimes: metadata.timeline.frames.map { $0.presentationTime.seconds },
            exactFrameErrorsMS: errors, frameLatencyMS: latencies, dualMaximumDriftMS: drift * 1000,
            dualElapsedSeconds: left.player.currentTime().seconds,
            visionMS: visionTimes, visionVisibleJoints: joints,
            visionStatus: visionFailure == nil ? "available" : "runtimeUnavailable",
            visionFailure: visionFailure, cacheBytes: await provider.cachedByteCount,
            residentMemoryBytes: sampledMemory,
            simulatorModel: ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown",
            systemVersion: UIDevice.current.systemVersion)
        guard let image else { throw MediaFailure.readFailed }
        let output = URL.documentsDirectory.appendingPathComponent("probe-report.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: output, options: .atomic)
        let named = URL.documentsDirectory.appendingPathComponent(
            "probe-report-\(url.deletingPathExtension().lastPathComponent).json")
        try data.write(to: named, options: .atomic)
        await provider.clear()
        return (report, image)
    }
    private static func residentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }
}
struct ProbeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: ProbeReport?
    @State private var image: CGImage?
    @State private var issue: String?
    @State private var running = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("模拟器媒体探针").font(.title2.bold())
                Text("真实帧定位 · 共享时钟双路播放 · Vision\n本页仅在 Debug 构建中出现。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("运行探针") { Task { await run() } }
                    .buttonStyle(.borderedProminent).disabled(running).accessibilityIdentifier("runProbe")
                if running { ProgressView("读取帧与执行本机识别…") }
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 300) }
                if let report {
                    Text("验证完成").font(.headline).accessibilityIdentifier("probeComplete")
                    Text("\(report.frames) 帧 · \(Int(report.displayWidth)) × \(Int(report.displayHeight))")
                    Text(String(format: "定位最大偏差 %.3f ms\n双路最大偏差 %.3f ms",
                                report.exactFrameErrorsMS.max() ?? 0, report.dualMaximumDriftMS))
                    if let failure = report.visionFailure {
                        Label("Vision 在当前模拟器不可用", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(failure).font(.caption)
                    } else {
                        Text(String(format: "Vision 平均 %.1f ms", report.visionMS.reduce(0, +) / Double(report.visionMS.count)))
                        Text("检测到的可用关节：\(report.visionVisibleJoints.map(String.init).joined(separator: " / "))")
                    }
                    Text("结果已保存到 Documents/probe-report.json").font(.caption).foregroundStyle(.secondary)
                }
                if let issue { Text(issue).foregroundStyle(.red).accessibilityIdentifier("probeError") }
            }.padding().frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.navigationTitle("技术验证").toolbar { Button("完成") { dismiss() } }
    }
    private func run() async {
        running = true; issue = nil; defer { running = false }
        do {
            let supplied = URL.documentsDirectory.appendingPathComponent("ProbeInput.mov")
            let url: URL
            if FileManager.default.fileExists(atPath: supplied.path) { url = supplied }
            else {
                url = URL.temporaryDirectory.appendingPathComponent("Probe.mov")
                try await FixtureFactory.video(at: url, times: (0..<60).map { Double($0) / 60 }, duration: 1)
            }
            let result = try await MediaProbe.run(url: url)
            report = result.0; image = result.1
        } catch { issue = error.localizedDescription }
    }
}
#endif
