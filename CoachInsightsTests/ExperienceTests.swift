import XCTest
import AVFoundation
@testable import CoachInsights

@MainActor final class ExperienceTests:XCTestCase {
    private var workspaces:[AnalysisWorkspace]=[]
    private var comparisons:[ComparisonWorkspace]=[]
    func track(_ w:AnalysisWorkspace)->AnalysisWorkspace { workspaces.append(w);return w }
    func track(_ w:ComparisonWorkspace)->ComparisonWorkspace { comparisons.append(w);return w }
    var root:URL!
    override func setUpWithError() throws {
        if let source=Bundle(for:Self.self).url(forResource:"Regression",withExtension:"mov") {
            let target=URL.documentsDirectory.appendingPathComponent("V101-RegressionFixture.mov")
            if !FileManager.default.fileExists(atPath:target.path) { try FileManager.default.copyItem(at:source,to:target) }
        }
        root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true) }
    override func tearDown() async throws {
        for w in workspaces { await w.shutdown() };for w in comparisons { await w.shutdown() }
        workspaces=[];comparisons=[]
        await Task.yield()
        if FileManager.default.fileExists(atPath:root.path) { try FileManager.default.removeItem(at:root) }
    }
    func wait(_ predicate:@escaping ()->Bool) async throws {
        for _ in 0..<400 { if predicate() { return };try await Task.sleep(for:.milliseconds(10)) };XCTFail("Operation timed out")
    }
    func setupVideo() async throws -> (LibraryRepository,AnalysisSession,VideoAsset) {
        let repo=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repo.create(name:"1.0 record",sport:.batting)
        let url=root.appendingPathComponent("fixture.mov")
        try await FixtureFactory.video(at:url,times:[0,0.1,0.35,0.5,0.8],duration:1)
        return (repo,session,try await repo.importVideo(url,into:session))
    }
    func testPoseScrubbingTracksDisplayedImageAndInvalidatesResults() async throws {
        let (repo,session,asset)=try await setupVideo()
        var old=try session.snapshot()
        old.poseResults=[PoseResult(videoID:asset.id,contentHash:asset.contentHash,settings:old.poseSettings,analyzedRange:old.clips[asset.id.uuidString]!,frames:[0.0,0.1,0.35,0.8].map { PoseFrame(time:MediaTime(seconds:$0),joints:[PoseJoint(name:"leftWrist",position:.init(x:$0,y:0.4),confidence:0.9)]) })]
        old.annotations=[Annotation(videoID:asset.id,kind:"line",points:[.init(x:0.1,y:0.1),.init(x:0.9,y:0.1)],range:.init(start:MediaTime(seconds:0),end:MediaTime(seconds:0.1)))]
        try repo.save(session,snapshot:old)
        let w=track(AnalysisWorkspace(session:session,repository:repo));await w.reload();try await wait{w.frameReady}
        XCTAssertEqual(w.currentPose?.time.seconds,0)
        w.beginScrubbing();w.scrub(to:0.35)
        XCTAssertEqual(w.frameIndex,2)
        XCTAssertEqual(w.currentPose?.time,w.frame?.requestedTime,"Requested playhead must not move skeleton ahead of the image")
        XCTAssertEqual(w.visibleAnnotations.count,1,"Old image retains its own overlay until preview arrives")
        try await wait{w.frame?.index==2};XCTAssertEqual(w.currentPose?.time.seconds,0.35);XCTAssertEqual(w.visibleAnnotations.count,0)
        w.endScrubbing();try await wait{w.frameReady};XCTAssertEqual(w.currentPose?.time.seconds,0.35)
        w.seek(frame:3);try await wait{w.frameReady};XCTAssertNil(w.currentPose,"Missing result must stay empty")
        for i in 0..<60 { w.scrub(to:Double(i%5)/5) };w.scrub(to:0.8);w.endScrubbing();try await wait{w.frameReady}
        XCTAssertEqual(w.frameIndex,4);XCTAssertEqual(w.currentPose?.time.seconds,0.8)
        w.beginScrubbing()
        var displayedTimes=Set<MediaTime>()
        for i in 0..<50 {
            w.scrub(to:Double(i%5)/5)
            try await Task.sleep(for:.milliseconds(20))
            if let frame=w.frame {
                displayedTimes.insert(frame.requestedTime)
                if let pose=w.currentPose { XCTAssertEqual(pose.time,frame.requestedTime) }
            }
        }
        XCTAssertGreaterThan(displayedTimes.count,2,"Continuous dragging must publish previews before release")
        w.scrub(to:0.8);w.endScrubbing();try await wait{w.frameReady}
        w.overlaysVisible=false;XCTAssertNil(w.currentPose);XCTAssertEqual(try session.snapshot().overlayVisibility[asset.id.uuidString],false)
        let export=try await ExportBuilder.recipe(session:session,repository:repo,videoID:asset.id,compare:false,rate:1,pose:true,audio:false)
        XCTAssertTrue(export.left.annotations.isEmpty);XCTAssertNil(export.left.pose)
        w.overlaysVisible=true
        w.poseSettings.region=[0.1,0.1,0.8,0.8];XCTAssertNil(w.currentPose)
        w.poseSettings=old.poseSettings
        w.snapshot.poseResults[0].frames[3].joints[0].position.x=0.25
        XCTAssertEqual(w.currentPose?.joints[0].position.x,0.25,"Same-size replacement must rebuild frame index")
        w.stopAndSave()
        let reopened=track(AnalysisWorkspace(session:session,repository:repo));await reopened.reload();try await wait{reopened.frameReady}
        XCTAssertEqual(reopened.frameIndex,4);XCTAssertEqual(reopened.currentPose?.joints[0].position.x,0.25);reopened.stopAndSave()
    }
    func testCrossRecordAttachmentAndDeletionProtectOriginalData() async throws {
        let (repo,source,asset)=try await setupVideo()
        var original=try source.snapshot();original.annotations=[Annotation(videoID:asset.id,kind:"line",points:[.init(x:0,y:0),.init(x:1,y:1)],range:original.clips[asset.id.uuidString]!)];try repo.save(source,snapshot:original)
        let target=try repo.create(name:"comparison",sport:.pitching)
        try repo.attach(asset.id,into:target);try repo.attach(asset.id,into:target)
        XCTAssertEqual(try target.snapshot().videoIDs,[asset.id]);XCTAssertEqual(try target.snapshot().annotations.count,1)
        var edited=try target.snapshot();edited.annotations[0].color="#FFFFFF";try repo.save(target,snapshot:edited)
        XCTAssertEqual(try source.snapshot(),original)
        try await repo.delete(source)
        let url=try await repo.files.existingURL(asset.relativePath);XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
        XCTAssertEqual(try target.snapshot().annotations[0].color,"#FFFFFF")
    }
    func testEmptyComparisonDefaultRateAndOldPreferences() async throws {
        let (repo,session,asset)=try await setupVideo()
        let before=try session.snapshot()
        let unloaded=track(AnalysisWorkspace(session:session,repository:repo));unloaded.stopAndSave();XCTAssertEqual(try session.snapshot(),before)
        let w=track(AnalysisWorkspace(session:session,repository:repo));await w.reload();try await wait{w.frameReady};XCTAssertEqual(w.rate,1)
        w.setRate(0.25);w.stopAndSave()
        let reopened=track(AnalysisWorkspace(session:session,repository:repo));await reopened.reload();XCTAssertEqual(reopened.rate,0.25);reopened.stopAndSave()
        let pair=track(ComparisonWorkspace(session:session,repository:repo));await pair.load(initialVideoID:asset.id);XCTAssertNil(pair.setup)
        XCTAssertNil(try session.snapshot().comparison)
    }
    func testChildChangesMergeAndClipBoundsStayValid() async throws {
        let (repo,session,asset)=try await setupVideo()
        let w=track(AnalysisWorkspace(session:session,repository:repo));await w.reload();try await wait{w.frameReady}
        w.seek(frame:2);try await wait{w.frameReady};w.save()
        var child=try session.snapshot();child.comparison=ComparisonSetup(leftVideoID:asset.id,rightVideoID:asset.id,leftAnchor:MediaTime(seconds:0),rightAnchor:MediaTime(seconds:0.1),leftClip:w.clip,rightClip:w.clip)
        try repo.save(session,snapshot:child)
        w.refreshPersistedChanges();w.save()
        XCTAssertNotNil(try session.snapshot().comparison);XCTAssertEqual(w.frameIndex,2)
        w.setClipBoundary(frame:4,start:true);w.setClipBoundary(frame:0,start:false);w.save()
        XCTAssertGreaterThan(w.clip.end,w.clip.start);XCTAssertEqual(w.metadata?.timeline.frameBounds(in:w.clip),4...4)
        w.stopAndSave()
    }
    func testBothComparisonOverlaysFollowIndependentAndSharedScrubbing() async throws {
        let (repo,session,first)=try await setupVideo()
        let url=root.appendingPathComponent("other.mov")
        try await FixtureFactory.video(at:url,times:(0..<60).map{Double($0)/60},duration:1)
        let second=try await repo.importVideo(url,into:session)
        var snapshot=try session.snapshot()
        for asset in [first,second] {
            let map=try asset.metadata().timeline
            snapshot.poseResults.append(PoseResult(videoID:asset.id,contentHash:asset.contentHash,settings:snapshot.poseSettings,analyzedRange:snapshot.clips[asset.id.uuidString]!,frames:map.frames.map{PoseFrame(time:$0.presentationTime,joints:[PoseJoint(name:"leftWrist",position:.init(x:$0.presentationTime.seconds,y:0.4),confidence:0.9)])}))
        }
        try repo.save(session,snapshot:snapshot)
        let pair=track(ComparisonWorkspace(session:session,repository:repo));await pair.load()
        try await wait{pair.left.frameReady && pair.right.frameReady}
        pair.independentSeek(0.35,isLeft:true);try await wait{pair.left.frame?.index==2}
        XCTAssertEqual(pair.left.currentPose?.time,pair.left.frame?.requestedTime)
        XCTAssertEqual(pair.right.currentPose?.time,pair.right.frame?.requestedTime)
        pair.left.endScrubbing();pair.anchor(isLeft:true);pair.seek(0.2)
        try await wait{pair.left.frameReady && pair.right.frameReady}
        XCTAssertEqual(pair.left.currentPose?.time,pair.left.frame?.requestedTime);XCTAssertEqual(pair.right.currentPose?.time,pair.right.frame?.requestedTime)
        var v=pair.right.viewSettings;v.zoom=2;pair.right.updateView(v)
        await pair.refreshAssets();XCTAssertEqual(pair.right.viewSettings.zoom,2)
        pair.seek(0.1);pair.stopAndSave();pair.resumeFrames();try await wait{pair.left.frameReady && pair.right.frameReady}
        XCTAssertEqual(pair.right.viewSettings.zoom,2);XCTAssertEqual(pair.left.currentPose?.time,pair.left.frame?.requestedTime)
        pair.stopAndSave()
    }
    func testNewComparisonPreservesSourceViewsRateAndTrimmedSecondClip() async throws {
        let (repo,session,first)=try await setupVideo()
        let url=root.appendingPathComponent("trimmed-second.mov")
        try await FixtureFactory.video(at:url,times:[0,0.2,0.4,0.6,0.8],duration:1)
        let second=try await repo.importVideo(url,into:session)
        var snapshot=try session.snapshot()
        var firstView=ViewSettings();firstView.mirrored=true;firstView.zoom=2
        var secondView=ViewSettings();secondView.quarterTurns=1
        let secondClip=ClipRange(start:MediaTime(seconds:0.4),end:MediaTime(seconds:0.8))
        snapshot.views[first.id.uuidString]=firstView;snapshot.views[second.id.uuidString]=secondView
        snapshot.clips[second.id.uuidString]=secondClip;snapshot.playbackRates[first.id.uuidString]=0.25
        snapshot.playheads[first.id.uuidString]=MediaTime(seconds:0.1)
        try repo.save(session,snapshot:snapshot)
        let pair=track(ComparisonWorkspace(session:session,repository:repo))
        await pair.load(initialVideoID:first.id,secondVideoID:second.id)
        try await wait{pair.left.frameReady && pair.right.frameReady}
        XCTAssertEqual(pair.left.viewSettings,firstView);XCTAssertEqual(pair.right.viewSettings,secondView)
        XCTAssertEqual(pair.setup?.rate,0.25);XCTAssertEqual(pair.right.clip,secondClip)
        XCTAssertEqual(pair.right.frame?.requestedTime,secondClip.start)
        pair.stopAndSave()
        let reopened=track(ComparisonWorkspace(session:session,repository:repo));await reopened.load(initialVideoID:first.id)
        XCTAssertEqual(reopened.setup,pair.setup)
        XCTAssertEqual(try session.snapshot().views[first.id.uuidString],firstView)
    }
    func testTwentySingleAndMixedRateComparisonLoops() async throws {
        let repo=try LibraryRepository(root:root.appendingPathComponent("LoopLibrary")),session=try repo.create(name:"20 loops",sport:.batting)
        for fps in [30,60] {
            let url=root.appendingPathComponent("loop-\(fps).mov")
            try await FixtureFactory.video(at:url,times:(0..<fps/5).map{Double($0)/Double(fps)},duration:0.2)
            _=try await repo.importVideo(url,into:session)
        }
        let w=track(AnalysisWorkspace(session:session,repository:repo));await w.reload();try await wait{w.frameReady};w.play()
        var wraps=0,previous=0.0
        let deadline=Date().addingTimeInterval(15)
        while wraps<20 && Date()<deadline {
            try await Task.sleep(for:.milliseconds(10))
            let current=w.playback!.player.currentTime().seconds
            if previous>0.12 && current<0.08 { wraps+=1 };previous=current
        }
        XCTAssertEqual(wraps,20);w.stopAndSave()
        let pair=track(ComparisonWorkspace(session:session,repository:repo));await pair.load();pair.play()
        wraps=0;previous=0
        let end=Date().addingTimeInterval(20)
        var maximumDrift=0.0
        while wraps<20 && Date()<end {
            try await Task.sleep(for:.milliseconds(10))
            let current=pair.left.playback!.player.currentTime().seconds
            if previous>0.12 && current<0.08 { wraps+=1 };previous=current
            if pair.playing { maximumDrift=max(maximumDrift,pair.drift) }
        }
        XCTAssertEqual(wraps,20);XCTAssertLessThan(maximumDrift,1.0/30)
        pair.stopAndSave()
    }
    func testFiveMinuteMediaOpensAndSeeksAtEndWithoutFullFrameCache() async throws {
        let repo=try LibraryRepository(root:root.appendingPathComponent("LongLibrary")),session=try repo.create(name:"five minutes",sport:.pitching)
        let url=root.appendingPathComponent("long.mov")
        try await FixtureFactory.video(at:url,times:(0..<9000).map{Double($0)/30},duration:300,size:CGSize(width:160,height:90))
        _=try await repo.importVideo(url,into:session)
        let w=track(AnalysisWorkspace(session:session,repository:repo));await w.reload();try await wait{w.frameReady}
        w.seek(time:299.9);try await wait{w.frameReady};XCTAssertEqual(w.frameIndex,8997)
        let bytes=await w.provider!.cachedByteCount;XCTAssertLessThanOrEqual(bytes,64*1024*1024)
        w.stopAndSave()
    }
    func testPlaybackRateChangesDoNotSeekBackAndCancelledLoadsStayStopped() async throws {
        let (repo,session,_)=try await setupVideo()
        let w=track(AnalysisWorkspace(session:session,repository:repo));await w.reload();try await wait{w.frameReady}
        w.play();try await wait{w.playing};try await Task.sleep(for:.milliseconds(180));let before=w.playback!.player.currentTime().seconds
        w.setRate(0.5);XCTAssertTrue(w.playing);XCTAssertEqual(w.playback!.player.rate,0.5);XCTAssertGreaterThanOrEqual(w.playback!.player.currentTime().seconds,before-0.001)
        w.pause();try await wait{w.frameReady}
        w.play();w.pause();try await Task.sleep(for:.milliseconds(100));XCTAssertFalse(w.playing);XCTAssertEqual(w.playback!.player.rate,0)
        let desired=w.frame?.index == 4 ? 0:4
        w.seek(frame:desired);w.stopAndSave()
        XCTAssertNotEqual(w.frame?.index,w.frameIndex)
        w.resumeDisplay();try await wait{w.frameReady};XCTAssertEqual(w.frameIndex,desired)
        w.stopAndSave()
    }
}
