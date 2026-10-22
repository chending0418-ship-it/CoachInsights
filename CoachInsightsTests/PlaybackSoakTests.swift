import XCTest
import SwiftUI
import AVFoundation
@testable import CoachInsights

@MainActor final class PlaybackSoakTests:XCTestCase {
    func testFourTenMinuteScenarios() async throws {
        #if DEBUG
        throw XCTSkip("Use scripts/soak_playback.py for the 40-minute optimized-host resource test")
        #else
        let settingsURL=URL.documentsDirectory.appendingPathComponent("v101-soak-settings.json")
        let settings=(try? Data(contentsOf:settingsURL)).flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Double]}
        let seconds=settings?["secondsPerScenario"] ?? 600
        guard seconds>=1 && seconds<=600 else { throw MediaFailure.invalidTiming }
        let root=URL.temporaryDirectory.appendingPathComponent("Soak-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let repo=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repo.create(name:"Playback resource soak",sport:.batting)
        BenchmarkFixture.cleanAfterHostWork(self,root:root,repository:repo)
        let real=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"Regression",withExtension:"mov"))
        let first=try await repo.importVideo(real,into:session)
        let other=root.appendingPathComponent("60fps.mov")
        try await BenchmarkFixture.video(at:other,times:(0..<120).map{Double($0)/60},duration:2)
        let second=try await repo.importVideo(other,into:session)
        let window=UIWindow(frame:UIScreen.main.bounds)
        window.windowScene=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first
        defer { window.isHidden=true;window.rootViewController=nil }
        let wholeStart=CACurrentMediaTime()
        var reports:[[String:Any]]=[]
        for mode in ["plain","annotations","pose","dual"] {
            window.rootViewController=nil
            try await Task.sleep(for:.milliseconds(150))
            var snapshot=try session.snapshot()
            snapshot.annotations=[];snapshot.poseResults=[]
            if mode != "plain" {
                for asset in [first,second] {
                    let info=try asset.metadata(),clip=snapshot.clips[asset.id.uuidString]!
                    snapshot.annotations += (0..<20).map { n in Annotation(videoID:asset.id,kind:"line",points:[.init(x:0.1,y:Double(n)/30),.init(x:0.9,y:Double(n)/30)],range:clip) }
                    if mode == "pose" || mode == "dual" {
                        snapshot.poseResults.append(PoseResult(videoID:asset.id,contentHash:asset.contentHash,settings:snapshot.poseSettings,analyzedRange:clip,frames:info.timeline.frames.map { PoseFrame(time:$0.presentationTime,joints:BenchmarkFixture.poseJoints) }))
                    }
                }
            }
            try repo.save(session,snapshot:snapshot)
            let w=AnalysisWorkspace(session:session,repository:repo);w.selectedVideoID=first.id;await w.reload()
            let pair=ComparisonWorkspace(session:session,repository:repo)
            if mode == "dual" { w.stopAndSave();await pair.load() }
            let content:AnyView=mode == "dual" ? AnyView(ComparisonEditor(workspace:pair,choose:{_ in})):AnyView(AnalysisEditor(workspace:w))
            window.rootViewController=UIHostingController(rootView:NavigationStack { content });window.makeKeyAndVisible()
            let start=CACurrentMediaTime()
            var samples:[[String:Double]]=[]
            var operation=0,lastSample = -1,lastPressure = -1
            while CACurrentMediaTime()-start < seconds {
                let elapsed=CACurrentMediaTime()-start
                let subject=mode == "dual" ? pair.left:w
                if operation%40<20 {
                    let t=subject.clip.start.seconds+(subject.clip.end.seconds-subject.clip.start.seconds)*Double((operation*17)%97)/100
                    if mode == "dual" { pair.seek(t-(pair.setup?.leftAnchor.seconds ?? 0)) }
                    else { w.scrub(to:t);if operation%5==4 { w.endScrubbing() } }
                } else if operation%40==20 {
                    if mode == "dual" { pair.play() } else { w.endScrubbing();w.play() }
                } else if operation%40==39 {
                    if mode == "dual" { pair.pause() } else { w.pause() }
                }
                for side in (mode == "dual" ? [pair.left,pair.right]:[w]) {
                    if let pose=side.currentPose,let map=side.metadata?.timeline {
                        let displayed=side.playing ? map.frames[side.frameIndex].presentationTime:side.frame?.requestedTime
                        XCTAssertEqual(pose.time,displayed)
                    }
                    if let provider=side.provider { let bytes=await provider.cachedByteCount;XCTAssertLessThanOrEqual(bytes,64*1024*1024) }
                    XCTAssertNil(side.saveIssue)
                }
                if Int(elapsed)/30 != lastPressure {
                    lastPressure=Int(elapsed)/30
                    NotificationCenter.default.post(name:UIApplication.didReceiveMemoryWarningNotification,object:nil)
                }
                if Int(elapsed)/5 != lastSample {
                    lastSample=Int(elapsed)/5
                    let rss=Double(Self.residentMemory())
                    samples.append(["seconds":elapsed,"residentBytes":rss])
                    if rss>=Double(1024*1024*1024) { XCTFail("Resident memory exceeded 1 GiB: \(rss)");throw MediaFailure.readFailed }
                    let progress:[String:Any] = ["mode":mode,"modeSeconds":elapsed,"totalSeconds":CACurrentMediaTime()-wholeStart,"residentBytes":rss,"completed":reports]
                    try JSONSerialization.data(withJSONObject:progress,options:[.prettyPrinted,.sortedKeys]).write(to:URL.documentsDirectory.appendingPathComponent("playback-soak-progress.json"),options:.atomic)
                }
                operation+=1
                try await Task.sleep(for:.milliseconds(100))
            }
            if mode == "dual" { pair.stopAndSave() } else { w.stopAndSave() }
            let early=samples.filter{$0["seconds"]!>=30 && $0["seconds"]!<90}.map{$0["residentBytes"]!}.max() ?? 0
            let late=samples.filter{$0["seconds"]!>=max(0,seconds-60)}.map{$0["residentBytes"]!}.max() ?? 0
            if seconds>=120 { XCTAssertLessThan(late-early,Double(128*1024*1024),"Sustained resident growth after warm-up") }
            reports.append(["mode":mode,"durationSeconds":CACurrentMediaTime()-start,"operations":operation,"samples":samples,"growthBytes":late-early])
            let attachment=XCTAttachment(image:UIGraphicsImageRenderer(size:window.bounds.size).image { _ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:true) })
            attachment.name="soak-"+mode;attachment.lifetime = .keepAlways;add(attachment)
            window.rootViewController=nil
            if mode == "dual" { await pair.shutdown() } else { await w.shutdown() }
        }
        let report:[String:Any] = ["configuration":"Release","secondsPerScenario":seconds,"fullDuration":seconds>=600,"device":ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown","scenarios":reports,"notes":"Full SwiftUI editor process RSS; synthetic saved pose results, no inference during playback; two simulator processes may run concurrently, latency comparisons are measured separately in isolation."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL.documentsDirectory.appendingPathComponent("playback-soak.json"),options:.atomic)
        #endif
    }
    private static func residentMemory()->UInt64 {
        var info=mach_task_basic_info(),count=mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size/MemoryLayout<integer_t>.size)
        let result=withUnsafeMutablePointer(to:&info) { p in p.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count) } }
        return result == KERN_SUCCESS ? info.resident_size:0
    }
}
