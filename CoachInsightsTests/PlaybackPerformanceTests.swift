import XCTest
import AVFoundation
import UIKit
@testable import CoachInsights

/// Optimized-host benchmark. Runs only through scripts/measure_playback.py.
/// Frame timings include a canvas render + a display opportunity, not just a seek callback.
@MainActor final class PlaybackPerformanceTests: XCTestCase {
    func testPlaybackBenchmark() async throws {
        #if DEBUG
        throw XCTSkip("Run the isolated Release benchmark with measure_playback.py")
        #else
        let root = URL.temporaryDirectory.appendingPathComponent("Playback-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = try LibraryRepository(root: root.appendingPathComponent("Library"))
        BenchmarkFixture.cleanAfterHostWork(self,root:root,repository:repo)
        var values: [String: [Double]] = [:]
        var failures: [String] = []
        let window = UIWindow(frame: UIScreen.main.bounds)
        let vc = UIViewController(); window.rootViewController = vc; window.makeKeyAndVisible()
        let canvas = AnalysisCanvasView(frame: CGRect(x: 0,y: 100,width: 320,height: 240))
        vc.view.addSubview(canvas)
        defer { window.isHidden = true;window.rootViewController=nil }
        func wait(_ name: String, _ predicate: () -> Bool) async throws {
            for _ in 0..<2000 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            failures.append(name); throw MediaFailure.readFailed
        }
        func render(_ w: AnalysisWorkspace) async {
            canvas.image = w.frame?.image; canvas.imageSize = w.metadata?.displaySize ?? .zero
            canvas.playerLayer.player = w.playback?.player; canvas.live = w.playing
            canvas.annotations = w.visibleAnnotations; canvas.pose = w.currentPose
            canvas.setNeedsLayout(); canvas.layoutIfNeeded(); canvas.setNeedsDisplay()
            CATransaction.flush()
            try? await Task.sleep(for: .milliseconds(17))
            if !w.playing {
                let renderer = UIGraphicsImageRenderer(size: canvas.bounds.size)
                _ = renderer.image { canvas.layer.render(in: $0.cgContext) }
            }
        }
        func record(_ name: String, _ start: Double) { values[name, default: []].append((CACurrentMediaTime()-start)*1000) }
        for sample in ["1080p", "4K"] {
            let session = try repo.create(name: sample, sport: .batting)
            let source: URL
            if sample == "4K", let real = Bundle(for: Self.self).url(forResource: "Regression", withExtension: "mov") { source = real }
            else {
                source = root.appendingPathComponent(sample+".mov")
                try await BenchmarkFixture.video(at: source, times: (0..<120).map{Double($0)/60}, duration: 2, size: CGSize(width:1920,height:1080))
            }
            print("BENCH generated",sample)
            let imported = try await repo.importVideo(source, into: session)
            print("BENCH imported",sample)
            var w = AnalysisWorkspace(session: session, repository: repo)
            for i in 0..<20 {
                if i > 0 { w.stopAndSave() }; w = AnalysisWorkspace(session:session,repository:repo)
                let start = CACurrentMediaTime(); await w.reload()
                try await wait("open") { w.frame != nil }; await render(w)
                record(sample+".open.new-workspace",start)
                if i == 0 {
                    let attachment = XCTAttachment(image: UIGraphicsImageRenderer(size: vc.view.bounds.size).image { _ in vc.view.drawHierarchy(in:vc.view.bounds,afterScreenUpdates:true) })
                    attachment.name = sample+"-canvas"; attachment.lifetime = .keepAlways; add(attachment)
                }
            }
            let count = w.metadata!.timeline.frames.count
            print("BENCH opened",sample)
            for overlay in ["plain","annotations","pose"] {
                w.snapshot.annotations = overlay == "plain" ? [] : (0..<20).map { n in
                    Annotation(videoID:imported.id,kind:"line",points:[.init(x:0.1,y:Double(n)/30),.init(x:0.9,y:Double(n)/30)],range:w.clip)
                }
                if overlay == "pose" {
                    w.snapshot.poseResults = [PoseResult(videoID:imported.id,contentHash:imported.contentHash,settings:w.poseSettings,analyzedRange:w.clip,
                        frames:w.metadata!.timeline.frames.map { PoseFrame(time:$0.presentationTime,joints:[PoseJoint(name:"leftShoulder",position:.init(x:0.4,y:0.3),confidence:0.9),PoseJoint(name:"leftElbow",position:.init(x:0.5,y:0.5),confidence:0.9)]) })]
                }
                for i in 0..<100 {
                    let target = (i%2 == 0 ? i*13 : count-1-i*7).magnitude % UInt(count)
                    let start = CACurrentMediaTime(); w.seek(frame:Int(target))
                    try await wait("step") { w.frame?.index == Int(target) }; await render(w)
                    record(sample+"."+overlay+".seek",start)
                }
                for i in 0..<30 {
                    let start = CACurrentMediaTime()
                    for n in 0..<12 { w.seek(frame:(i*7+n*17)%count) }
                    let target=(i*7+11*17)%count
                    try await wait("scrub") { w.frame?.index == target }; await render(w)
                    record(sample+"."+overlay+".burst-final",start)
                }
            }
            print("BENCH seeks",sample)
            for i in 0..<30 {
                w.seek(frame:i%10); try await wait("ready") { w.frame?.index == i%10 }
                let item = try XCTUnwrap(w.playback?.player.currentItem)
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
                item.add(output)
                let start=CACurrentMediaTime(); w.play()
                try await wait("play") { w.playing && (w.playback?.player.currentTime().seconds ?? 0)>w.time+0.005 }
                try await wait("visible playback") { output.hasNewPixelBuffer(forItemTime:w.playback!.player.currentTime()) }
                _ = output.copyPixelBuffer(forItemTime:w.playback!.player.currentTime(),itemTimeForDisplay:nil)
                await render(w); record(sample+".play.output",start)
                let speed=CACurrentMediaTime();w.rate=[1,0.5,0.25,0.1,0.05][i%5];w.play()
                try await wait("speed") { w.playing && abs(Double(w.playback!.player.rate)-w.rate)<0.001 }
                record(sample+".rate.command",speed)
                let pause=CACurrentMediaTime();w.pause()
                try await wait("pause") { !w.playing && w.frame?.index==w.frameIndex };await render(w)
                record(sample+".pause.render",pause);item.remove(output)
            }
            let dual=ComparisonWorkspace(session:session,repository:repo)
            // Explicit second fixture, even when the original release allowed a repeated first video.
            let second=root.appendingPathComponent("second-\(sample).mov")
            try await BenchmarkFixture.video(at:second,times:(0..<60).map{Double($0)/30},duration:2,size:CGSize(width:320,height:180))
            _=try await repo.importVideo(second,into:session)
            let start=CACurrentMediaTime();await dual.load();dual.play();try await wait("dual") { dual.playing };record(sample+".dual.prepare",start)
            try await Task.sleep(for:.seconds(1));values[sample+".dual.drift-ms"]=[dual.drift*1000];dual.pause();w.stopAndSave()
        }
        let summary=values.mapValues { list -> [String:Double] in
            let s=list.sorted();return ["n":Double(s.count),"p50":s[s.count/2],"p95":s[min(s.count-1,Int(ceil(Double(s.count)*0.95))-1)],"max":s.last!]
        }
        let report:[String:Any] = ["metricsMS":summary,"rawMS":values,"failures":failures,"device":ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown","system":UIDevice.current.systemVersion,"configuration":"Release","measurement":"workspace -> exact frame -> canvas render + 17ms; play includes AVPlayerItemVideoOutput; rate measures command only; open uses new workspace, OS caches uncontrolled; pose is synthetic overlay load, not recognition accuracy"]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:URL.documentsDirectory.appendingPathComponent("playback-performance.json"))
        XCTAssertTrue(failures.isEmpty)
        #endif
    }
}
