import XCTest
import AVFoundation
import UIKit
@testable import CoachInsights

@MainActor final class PlaybackLoopBenchmarkTests:XCTestCase {
    func testLoopSeams() async throws {
        #if DEBUG
        throw XCTSkip("Run measure_loop.py with the optimized original/candidate source")
        #else
        let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let repo=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repo.create(name:"seam",sport:.batting)
        BenchmarkFixture.cleanAfterHostWork(self,root:root,repository:repo)
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"Regression",withExtension:"mov"))
        let asset=try await repo.importVideo(url,into:session)
        let w=AnalysisWorkspace(session:session,repository:repo);await w.reload()
        for _ in 0..<500 { if w.frame != nil { break };try await Task.sleep(for:.milliseconds(10)) }
        let map=try asset.metadata().timeline
        w.snapshot.clips[asset.id.uuidString]=ClipRange(start:map.frames[0].presentationTime,end:map.frames[min(7,map.frames.count-1)].presentationTime)
        var reports:[String:[Double]] = [:]
        let window=UIWindow(frame:UIScreen.main.bounds),vc=UIViewController()
        window.windowScene=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first
        window.rootViewController=vc;window.makeKeyAndVisible();defer { window.isHidden=true;window.rootViewController=nil }
        let canvas=AnalysisCanvasView(frame:CGRect(x:0,y:80,width:320,height:240));vc.view.addSubview(canvas)
        for mode in ["plain","annotations","pose"] {
            w.snapshot.annotations=mode == "plain" ? []:(0..<20).map { i in Annotation(videoID:asset.id,kind:"line",points:[.init(x:0.1,y:Double(i)/30),.init(x:0.9,y:Double(i)/30)],range:w.clip) }
            w.snapshot.poseResults=mode == "pose" ? [PoseResult(videoID:asset.id,contentHash:asset.contentHash,settings:w.poseSettings,analyzedRange:w.clip,frames:map.frames.map{PoseFrame(time:$0.presentationTime,joints:BenchmarkFixture.poseJoints)})]:[]
            w.seek(frame:0)
            for _ in 0..<500 { if w.frame?.index==0 { break };try await Task.sleep(for:.milliseconds(5)) }
            w.rate=1;w.looping=true;w.play()
            let item=try XCTUnwrap(w.playback?.player.currentItem)
            let output=AVPlayerItemVideoOutput(pixelBufferAttributes:nil);item.add(output)
            var previousTime = -1.0,lastOutputWall=CACurrentMediaTime(),gapStart:Double?,gaps:[Double]=[]
            let deadline=CACurrentMediaTime()+30
            while gaps.count<20 && CACurrentMediaTime()<deadline {
                let time=w.playback!.player.currentTime(),now=CACurrentMediaTime()
                if output.hasNewPixelBuffer(forItemTime:time),output.copyPixelBuffer(forItemTime:time,itemTimeForDisplay:nil) != nil {
                    if time.seconds < previousTime-0.001,gapStart == nil { gapStart=lastOutputWall }
                    if let started=gapStart { gaps.append((now-started)*1000);gapStart=nil }
                    previousTime=time.seconds;lastOutputWall=now
                    canvas.playerLayer.player=w.playback?.player;canvas.live=true;canvas.image=w.frame?.image;canvas.imageSize=w.metadata!.displaySize;canvas.annotations=w.visibleAnnotations;canvas.pose=w.currentPose;canvas.setNeedsLayout();canvas.setNeedsDisplay();CATransaction.flush()
                }
                try await Task.sleep(for:.milliseconds(5))
            }
            item.remove(output);w.pause();XCTAssertEqual(gaps.count,20)
            reports[mode]=gaps
            let a=XCTAttachment(image:UIGraphicsImageRenderer(size:vc.view.bounds.size).image { _ in vc.view.drawHierarchy(in:vc.view.bounds,afterScreenUpdates:true) });a.name="loop-"+mode;a.lifetime = .keepAlways;add(a)
        }
        w.stopAndSave()
        let ordinary=root.appendingPathComponent("1080p.mov")
        try await BenchmarkFixture.video(at:ordinary,times:(0..<120).map{Double($0)/60},duration:2,size:CGSize(width:1920,height:1080))
        let ordinaryAsset=try await repo.importVideo(ordinary,into:session)
        var cacheReports:[String:[Double]] = [:]
        for (name,source) in [("4K",asset),("1080p",ordinaryAsset)] {
            let value=AnalysisWorkspace(session:session,repository:repo);value.selectedVideoID=source.id;await value.reload();value.fullClip()
            value.snapshot.annotations=[];value.snapshot.poseResults=[]
            func settle(_ target:Int) async throws {
                for _ in 0..<1000 { if value.frame?.index==target { return };try await Task.sleep(for:.milliseconds(5)) }
                XCTFail("Exact frame did not settle");throw MediaFailure.readFailed
            }
            func render() async throws {
                canvas.playerLayer.player=value.playback?.player;canvas.live=false;canvas.image=value.frame?.image;canvas.imageSize=value.metadata!.displaySize;canvas.annotations=[];canvas.pose=nil
                canvas.setNeedsLayout();canvas.layoutIfNeeded();canvas.setNeedsDisplay();CATransaction.flush()
                try await Task.sleep(for:.milliseconds(17))
                _=UIGraphicsImageRenderer(size:canvas.bounds.size).image { canvas.layer.render(in:$0.cgContext) }
            }
            value.seek(frame:0);try await settle(0);value.seek(frame:1);try await settle(1)
            for i in 0..<100 {
                let target=i%2,start=CACurrentMediaTime();value.seek(frame:target);try await settle(target);try await render()
                cacheReports[name+".warm",default:[]].append((CACurrentMediaTime()-start)*1000)
            }
            for i in 0..<100 {
                value.cancelFrameRequest();await value.provider?.clear()
                let target=2+i%2,start=CACurrentMediaTime();value.seek(frame:target);try await settle(target);try await render()
                cacheReports[name+".uncached",default:[]].append((CACurrentMediaTime()-start)*1000)
            }
            value.stopAndSave()
        }
        let report:[String:Any]=["rawOutputGapMS":reports,"rawSeekMS":cacheReports,"note":"Wall-clock interval from the last observed output of one cycle to first output of the next; includes normal frame interval and seek. Samples AVPlayerItemVideoOutput and displays canvas; does not measure photons or prove every screen frame is non-black."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL.documentsDirectory.appendingPathComponent("playback-loop.json"))
        #endif
    }
}
