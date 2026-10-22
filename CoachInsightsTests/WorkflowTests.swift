import XCTest
import AVFoundation
import UIKit
@testable import CoachInsights

@MainActor final class WorkflowTests:XCTestCase {
    private var workspaces:[AnalysisWorkspace]=[]
    private var comparisons:[ComparisonWorkspace]=[]
    func track(_ w:AnalysisWorkspace)->AnalysisWorkspace { workspaces.append(w);return w }
    func track(_ w:ComparisonWorkspace)->ComparisonWorkspace { comparisons.append(w);return w }
    var root:URL!
    override func setUpWithError() throws {
        root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    }
    override func tearDown() async throws {
        for w in workspaces { await w.shutdown() };for w in comparisons { await w.shutdown() }
        workspaces=[];comparisons=[]
        await Task.yield()
        if FileManager.default.fileExists(atPath:root.path) { try FileManager.default.removeItem(at:root) }
    }
    func fixture(_ name:String="source",fps:Int=30,duration:Double=1) async throws -> URL {
        let url=root.appendingPathComponent(name+".mov")
        try await FixtureFactory.video(at:url,times:(0..<Int(duration*Double(fps))).map{Double($0)/Double(fps)},duration:duration)
        return url
    }
    func wait(_ predicate:@escaping ()->Bool) async throws {
        for _ in 0..<200 { if predicate() { return };try await Task.sleep(for:.milliseconds(10)) };XCTFail("Operation did not complete")
    }
    func testEditorRoundTripFrameScopeHistoryTransformsAndKeyframes() async throws {
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library"))
        let record=try repository.create(name:"完整打击分析",sport:.batting)
        let source=try await fixture(fps:60)
        let asset=try await repository.importVideo(source,into:record)
        let w=track(AnalysisWorkspace(session:record,repository:repository));await w.reload()
        try await wait{w.frame != nil}
        w.seek(frame:20);w.seek(frame:40);w.seek(frame:15)
        try await wait{w.frame?.index==15}
        XCTAssertEqual(w.frameIndex,15);XCTAssertEqual(w.time,0.25,accuracy:0.00001)
        let valid=w.snapshot,savedBefore=try record.snapshot();w.snapshot.version=2;w.save();XCTAssertNotNil(w.saveIssue);XCTAssertEqual(try record.snapshot(),savedBefore)
        w.snapshot=valid;w.save();XCTAssertNil(w.saveIssue)
        w.tool="arrow";w.add(points:[UnitPointValue(x:0.2,y:0.3),UnitPointValue(x:0.8,y:0.7)])
        XCTAssertEqual(w.visibleAnnotations.count,1)
        let annotation=try XCTUnwrap(w.snapshot.annotations.first)
        w.step(1);try await wait{w.frameReady};XCTAssertEqual(w.visibleAnnotations.count,0)
        w.step(-1);try await wait{w.frameReady};XCTAssertEqual(w.visibleAnnotations.count,1)
        var edited=annotation;edited.points[0].x=0.3;w.replace(edited)
        XCTAssertEqual(w.snapshot.annotations[0].points[0].x,0.3)
        w.undo();XCTAssertEqual(w.snapshot.annotations[0],annotation)
        w.redo();XCTAssertEqual(w.snapshot.annotations[0],edited)
        w.rangeMode="片段";w.tool="angle";w.add(points:[.init(x:0.2,y:0.2),.init(x:0.5,y:0.5),.init(x:0.8,y:0.2)])
        w.addKeyframe("击球")
        var view=ViewSettings();view.zoom=1.5;view.mirrored=true;view.quarterTurns=1;view.pan = .init(x:0.1,y:-0.05);w.updateView(view)
        w.markStart();w.seek(frame:45);try await wait{w.frame?.index==45};w.markEnd();w.seek(frame:1000);try await wait{w.frame?.index==45};XCTAssertEqual(w.frameIndex,45);w.stopAndSave()
        let reopened=try LibraryRepository(root:root.appendingPathComponent("Library"))
        let restored=try XCTUnwrap(reopened.sessions().first);let snapshot=try restored.snapshot()
        XCTAssertEqual(snapshot.annotations.count,2);XCTAssertEqual(snapshot.keyframes.first?.name,"击球")
        XCTAssertEqual(snapshot.views[asset.id.uuidString],view)
        XCTAssertEqual(snapshot.clips[asset.id.uuidString]?.start.seconds,0.25)
        XCTAssertEqual(snapshot.clips[asset.id.uuidString]!.end.seconds,46.0/60,accuracy:0.00001)
        let next=track(AnalysisWorkspace(session:restored,repository:reopened));await next.reload();try await wait{next.frame?.index==45};next.stopAndSave()
    }
    func testComparisonDifferentRatesAnchorsPlaybackAndRestore() async throws {
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library")),record=try repository.create(name:"投球对比",sport:.pitching)
        let a=try await fixture("a",fps:30,duration:1.5),b=try await fixture("b",fps:120,duration:1)
        _=try await repository.importVideo(a,into:record);_=try await repository.importVideo(b,into:record)
        let w=track(ComparisonWorkspace(session:record,repository:repository));await w.load()
        w.left.seek(frame:6);w.right.seek(frame:36)
        try await wait{w.left.frame?.index==6 && w.right.frame?.index==36}
        w.anchor(isLeft:true)
        w.right.seek(frame:36);try await wait{w.right.frame?.index==36};w.anchor(isLeft:false)
        XCTAssertEqual(w.setup!.leftAnchor.seconds,0.2,accuracy:0.00001)
        XCTAssertEqual(w.setup!.rightAnchor.seconds,0.3,accuracy:0.00001)
        XCTAssertEqual(w.range!.lowerBound,-0.2,accuracy:0.00001);XCTAssertEqual(w.range!.upperBound,0.7,accuracy:0.00001)
        w.setup?.rate=0.5;w.setup?.layout="vertical";w.changedSetup();w.seek(0)
        try await wait{w.left.frame?.index==6 && w.right.frame?.index==36}
        w.play();try await wait{w.playing};XCTAssertNil(w.issue);try await Task.sleep(for:.milliseconds(600))
        XCTAssertGreaterThan(w.time,0.1);XCTAssertLessThan(w.drift,1.0/120)
        w.pause();w.seek(100);XCTAssertEqual(w.time,0.7,accuracy:0.00001)
        var view=ViewSettings();view.mirrored=true;view.crop=[0.1,0.1,0.8,0.8];w.right.updateView(view);w.save()
        let next=track(ComparisonWorkspace(session:record,repository:repository));await next.load()
        XCTAssertEqual(next.setup?.layout,"vertical");XCTAssertEqual(next.setup?.rightView,view)
        w.pause();next.pause()
    }
    func testScreenshotSlowVideoAndComparisonExportMatchSourceAndTiming() async throws {
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library")),record=try repository.create(name:"导出",sport:.batting)
        let source=try await fixture(fps:60,duration:0.5),asset=try await repository.importVideo(source,into:record)
        var snapshot=try record.snapshot()
        snapshot.annotations=[Annotation(videoID:asset.id,kind:"line",points:[.init(x:0.1,y:0.2),.init(x:0.9,y:0.2)],color:"#FFFFFF",lineWidth:7,range:.init(start:MediaTime(seconds:0),end:MediaTime(seconds:0.5)))]
        snapshot.playheads[asset.id.uuidString]=MediaTime(seconds:0.2)
        try repository.save(record,snapshot:snapshot)
        let recipe=try await ExportBuilder.recipe(session:record,repository:repository,videoID:asset.id,compare:false,rate:0.5,pose:true,audio:false)
        let service=ExportService(),directory=root.appendingPathComponent("Exports")
        let png=try await service.screenshot(source:recipe.left,time:0.2,size:CGSize(width:640,height:360),directory:directory)
        let screenshot=try XCTUnwrap(UIImage(contentsOfFile:png.path)?.cgImage)
        XCTAssertEqual(screenshot.width,640);XCTAssertEqual(screenshot.height,360)
        let white=Self.pixel(screenshot,x:320,y:72);XCTAssertGreaterThan(white.0,220);XCTAssertGreaterThan(white.1,220);XCTAssertGreaterThan(white.2,220)
        let movie=try await service.video(recipe:recipe,directory:directory){_ in}
        try? FileManager.default.copyItem(at:movie,to:URL.documentsDirectory.appendingPathComponent("export-debug.mp4"))
        let info=try await MediaInspector().inspect(url:movie)
        XCTAssertEqual(info.timeline.duration.seconds,1,accuracy:0.04);XCTAssertEqual(info.timeline.frames.count,30)
        XCTAssertEqual(info.codec,"avc1");XCTAssertEqual(info.displayWidth,1920);XCTAssertEqual(info.displayHeight,1080)
        let video=AVURLAsset(url:movie),provider=FrameProvider(asset:video,metadata:info,maximumDimension:640)
        let decoded=try await provider.frame(at:12)
        let line=Self.pixel(decoded.image,x:decoded.image.width/2,y:Int(Double(decoded.image.height)*0.2))
        XCTAssertGreaterThan(line.0,200);XCTAssertGreaterThan(line.1,200)
        let slowColor=Self.pixel(decoded.image,x:Int(Double(decoded.image.width)*0.9),y:Int(Double(decoded.image.height)*0.8))
        XCTAssertGreaterThan(slowColor.0,slowColor.1+40,"Half-speed output frame 12 must sample source frame 12 at 0.2 s")
        snapshot.comparison=ComparisonSetup(leftVideoID:asset.id,rightVideoID:asset.id,leftAnchor:MediaTime(seconds:0.1),rightAnchor:MediaTime(seconds:0.2),
            leftClip:.init(start:MediaTime(seconds:0),end:MediaTime(seconds:0.4)),rightClip:.init(start:MediaTime(seconds:0.1),end:MediaTime(seconds:0.5)))
        try repository.save(record,snapshot:snapshot)
        let pair=try await ExportBuilder.recipe(session:record,repository:repository,videoID:nil,compare:true,rate:1,pose:true,audio:false)
        let comparison=try await service.video(recipe:pair,directory:directory){_ in},comparisonInfo=try await MediaInspector().inspect(url:comparison)
        XCTAssertEqual(comparisonInfo.timeline.duration.seconds,0.4,accuracy:0.04)
        let composed=try await FrameProvider(asset:AVURLAsset(url:comparison),metadata:comparisonInfo,maximumDimension:1920).frame(at:3)
        let leftColor=Self.pixel(composed.image,x:864,y:702),rightColor=Self.pixel(composed.image,x:1824,y:702)
        XCTAssertGreaterThan(leftColor.1,rightColor.1+40,"The composed panels must sample different source times at the saved anchors")
        let audioTracks=try await AVURLAsset(url:comparison).loadTracks(withMediaType:.audio);XCTAssertTrue(audioTracks.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
    }
    func testCancelExportAndImportCleanPartialFiles() async throws {
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library")),record=try repository.create(name:"取消",sport:.batting)
        let source=try await fixture(),asset=try await repository.importVideo(source,into:record)
        let recipe=try await ExportBuilder.recipe(session:record,repository:repository,videoID:asset.id,compare:false,rate:0.05,pose:false,audio:false)
        let directory=root.appendingPathComponent("CancelledExports")
        let task=Task { try await ExportService().video(recipe:recipe,directory:directory){_ in} }
        try await Task.sleep(for:.milliseconds(50));task.cancel()
        do { _=try await task.value;XCTFail("cancelled export completed") } catch { XCTAssertTrue(error is CancellationError,"\(error)") }
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty) ?? true)
        let second=try repository.create(name:"取消导入",sport:.pitching)
        let importing=Task { @MainActor in _=try await repository.importVideo(source,into:second) };importing.cancel()
        do { _=try await importing.value;XCTFail("cancelled import completed") } catch { XCTAssertTrue(error is CancellationError,"\(error)") }
        XCTAssertTrue(try second.snapshot().videoIDs.isEmpty)
        let staging=root.appendingPathComponent("Library/Files/Staging")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:staging.path).isEmpty)
    }
    func testNativeMediaPipeOfflineAndPrivateRegression() async throws {
        let source=try await fixture(),metadata=try await MediaInspector().inspect(url:source)
        var settings=PoseSettings();settings.engine=MediaPipePoseEngine.identity
        let result=try await PoseAnalysis.analyze(provider:FrameProvider(asset:AVURLAsset(url:source),metadata:metadata,maximumDimension:640),metadata:metadata,
            videoID:UUID(),hash:"synthetic",settings:settings,range:.init(start:MediaTime(seconds:0),end:metadata.timeline.duration)){_ in}
        XCTAssertEqual(result.frames.count,30);XCTAssertTrue(result.frames.allSatisfy{$0.joints.isEmpty})
        guard let url=Bundle(for:Self.self).url(forResource:"Regression",withExtension:"mov",subdirectory:nil) else { return }
        let info=try await MediaInspector().inspect(url:url)
        let real=try await PoseAnalysis.analyze(provider:FrameProvider(asset:AVURLAsset(url:url),metadata:info,maximumDimension:1280),metadata:info,
            videoID:UUID(),hash:"local-regression",settings:settings,range:.init(start:MediaTime(seconds:0),end:info.timeline.duration)){_ in}
        XCTAssertEqual(real.frames.count,78)
        XCTAssertGreaterThan(real.frames.filter{!$0.joints.isEmpty}.count,0,"Native offline model must actually detect the person")
        let output=URL.documentsDirectory.appendingPathComponent("pose-regression.json")
        try JSONEncoder().encode(real).write(to:output)
    }
    func testOptionalPitchingPoseQualitySamples() async throws {
        guard let url=Bundle(for:Self.self).url(forResource:"Pitching",withExtension:"mov") else { throw XCTSkip("Optional public baseball throw sample") }
        let metadata=try await MediaInspector().inspect(url:url)
        let provider=FrameProvider(asset:AVURLAsset(url:url),metadata:metadata,maximumDimension:1280)
        let engine=MediaPipePoseEngine()
        var frames:[PoseFrame]=[]
        for index in stride(from:250,through:830,by:20) {
            let frame=try await provider.frame(at:index),bodies=try await engine.bodies(in:frame.image)
            frames.append(PoseFrame(time:frame.requestedTime,joints:bodies.count==1 ? bodies[0].filter{$0.confidence>=0.3}:[]))
        }
        XCTAssertEqual(frames.count,30);XCTAssertGreaterThan(frames.filter{!$0.joints.isEmpty}.count,20)
        var settings=PoseSettings();settings.engine=MediaPipePoseEngine.identity
        let result=PoseResult(videoID:UUID(),contentHash:"openbiomechanics-cv-media-v1",settings:settings,
            analyzedRange:.init(start:frames[0].time,end:frames.last!.time),frames:frames)
        try JSONEncoder().encode(result).write(to:URL.documentsDirectory.appendingPathComponent("pose-pitching.json"))
    }
    func testPersistedPhotosSlowMotionRebuildsOriginalPresentation() async throws {
        let original=try await fixture(fps:120,duration:1),source=AVURLAsset(url:original)
        let composition=AVMutableComposition(),track=try XCTUnwrap(composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid))
        let inputTracks=try await source.loadTracks(withMediaType:.video)
        let input=try XCTUnwrap(inputTracks.first)
        try track.insertTimeRange(CMTimeRange(start:.zero,duration:MediaTime(seconds:1).cmTime),of:input,at:.zero)
        track.scaleTimeRange(CMTimeRange(start:MediaTime(seconds:0.25).cmTime,duration:MediaTime(seconds:0.5).cmTime),toDuration:MediaTime(seconds:2).cmTime)
        let timing=try await MediaInspector().inspect(asset:composition)
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repository.create(name:"相册慢动作",sport:.pitching)
        let asset=try await repository.importVideo(original,into:session,timing:timing)
        let localURL=try await repository.files.existingURL(asset.relativePath)
        let restored=try await LocalMedia.asset(url:localURL,metadata:asset.metadata()),info=try await MediaInspector().inspect(asset:restored)
        XCTAssertEqual(info.timeline.frames,timing.timeline.frames);XCTAssertEqual(info.timeline.duration.seconds,2.5,accuracy:0.00001)
        let provider=FrameProvider(asset:restored,metadata:info)
        for index in [0,29,30,60,89,90,119] { let frame=try await provider.frame(at:index);XCTAssertEqual(frame.actualTime,info.timeline.frames[index].presentationTime) }
    }
    func testDeniedCameraAndMicrophoneKeepImportAndSilentCaptureFallback() async throws {
        let camera=CaptureService(authorization:CaptureAuthorization(camera:{false},microphone:{false}))
        await camera.prepare();XCTAssertFalse(camera.available);XCTAssertTrue(camera.issue?.contains("未允许使用相机") == true)
        await camera.setAudio(true);XCTAssertFalse(camera.audioEnabled);XCTAssertTrue(camera.issue?.contains("继续无声拍摄") == true)
        XCTAssertNil(camera.reviewURL)
        let repo=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repo.create(name:"权限拒绝后导入",sport:.batting)
        let url=try await fixture();let asset=try await repo.importVideo(url,into:session)
        XCTAssertEqual(try session.snapshot().videoIDs,[asset.id])
    }
    func testPoseCancellationRetryReuseAndParameterInvalidation() async throws {
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repository.create(name:"姿态任务",sport:.pitching)
        let url=try await fixture(),asset=try await repository.importVideo(url,into:session)
        let w=track(AnalysisWorkspace(session:session,repository:repository));await w.reload();try await wait{w.frame != nil}
        var settings=PoseSettings();settings.engine=MediaPipePoseEngine.identity;w.poseSettings=settings
        w.analyzePose(force:true);XCTAssertTrue(w.poseBusy)
        try await Task.sleep(for:.milliseconds(15));w.poseTask?.cancel();try await wait{!w.poseBusy}
        XCTAssertTrue(w.snapshot.poseResults.isEmpty)
        w.analyzePose(force:true);try await wait{!w.poseBusy}
        XCTAssertEqual(w.snapshot.poseResults.first?.frames.count,30)
        let result=try XCTUnwrap(w.snapshot.poseResults.first);settings.visible=false;w.poseSettings=settings
        w.analyzePose();XCTAssertFalse(w.poseBusy);XCTAssertEqual(w.snapshot.poseResults.first,result)
        settings.region=[0.1,0.1,0.8,0.8];settings.visible=true;w.poseSettings=settings
        XCTAssertNil(w.currentPose);XCTAssertFalse(result.isReusable(hash:asset.contentHash,settings:settings,range:w.clip))
        w.stopAndSave()
    }
    func testVFRExportHoldsSampleAndAnnotationUntilItsActualEnd() async throws {
        let source=root.appendingPathComponent("vfr.mov")
        try await FixtureFactory.video(at:source,times:[0,0.1,0.6,0.7],duration:0.8)
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repository.create(name:"VFR 导出",sport:.batting)
        let asset=try await repository.importVideo(source,into:session),metadata=try asset.metadata()
        var snapshot=try session.snapshot()
        snapshot.annotations=[Annotation(videoID:asset.id,kind:"line",points:[.init(x:0.2,y:0.2),.init(x:0.8,y:0.2)],color:"#FFFFFF",lineWidth:5,
            range:ClipRange(start:metadata.timeline.frames[1].presentationTime,end:metadata.timeline.frames[2].presentationTime))]
        try repository.save(session,snapshot:snapshot)
        let recipe=try await ExportBuilder.recipe(session:session,repository:repository,videoID:asset.id,compare:false,rate:1,pose:false,audio:false)
        let result=try await ExportService().video(recipe:recipe,directory:root.appendingPathComponent("Exports")){_ in}
        let outputInfo=try await MediaInspector().inspect(url:result)
        let provider=FrameProvider(asset:AVURLAsset(url:result),metadata:outputInfo,maximumDimension:320)
        let held=try await provider.frame(at:12),next=try await provider.frame(at:18)
        let expected=try await FrameProvider(asset:AVURLAsset(url:source),metadata:metadata,maximumDimension:320).frame(at:1)
        let actualColor=Self.pixel(held.image,x:288,y:144),expectedColor=Self.pixel(expected.image,x:288,y:144)
        XCTAssertLessThan(abs(actualColor.0-expectedColor.0),12);XCTAssertLessThan(abs(actualColor.1-expectedColor.1),12);XCTAssertLessThan(abs(actualColor.2-expectedColor.2),12)
        XCTAssertGreaterThan(Self.pixel(held.image,x:160,y:36).0,220)
        XCTAssertLessThan(Self.pixel(next.image,x:160,y:36).0,210,"The frame annotation must end exactly when the next source sample begins")
    }
    func testLivePauseFreezesCurrentFrameAndSelectionPreservesOtherStyleFields() async throws {
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repository.create(name:"暂停帧",sport:.batting)
        let source=try await fixture(duration:1.5);_=try await repository.importVideo(source,into:session)
        let w=track(AnalysisWorkspace(session:session,repository:repository));await w.reload();try await wait{w.frame != nil}
        w.rate=1;w.looping=false;w.play();try await wait{w.playing}
        try await Task.sleep(for:.milliseconds(350));w.tool="line"
        XCTAssertFalse(w.playing);XCTAssertGreaterThan(w.frameIndex,1)
        try await wait{w.frame?.index==w.frameIndex}
        XCTAssertEqual(w.frame?.requestedTime,w.metadata?.timeline.frames[w.frameIndex].presentationTime)
        w.color="#FFFFFF";w.add(points:[.init(x:0.2,y:0.3),.init(x:0.8,y:0.7)])
        let id=try XCTUnwrap(w.selectedAnnotation)
        w.selectedAnnotation=nil;w.color="#722F37";w.selectedAnnotation=id
        XCTAssertEqual(w.color,"#FFFFFF")
        w.lineWidth=7;w.styleSelection();XCTAssertEqual(w.snapshot.annotations[0].color,"#FFFFFF");XCTAssertEqual(w.snapshot.annotations[0].lineWidth,7)
        w.undo();XCTAssertEqual(w.lineWidth,3)
        w.redo();XCTAssertEqual(w.lineWidth,7)
        w.step(1);XCTAssertNil(w.selectedAnnotation);w.stopAndSave()
    }
    func testSingleLoopStopsOnLastFrameAndCanReplay() async throws {
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repository.create(name:"循环边界",sport:.batting)
        let source=try await fixture(fps:30,duration:0.3);_=try await repository.importVideo(source,into:session)
        let w=track(AnalysisWorkspace(session:session,repository:repository));await w.reload();try await wait{w.frame != nil}
        w.rate=1;w.looping=true;w.play();try await wait{w.playing}
        var maximum=0.0,sawWrap=false
        for _ in 0..<45 {
            try await Task.sleep(for:.milliseconds(20));let t=w.playback!.player.currentTime().seconds
            if maximum>0.2 && t<0.08 { sawWrap=true };maximum=max(maximum,t)
        }
        XCTAssertTrue(sawWrap,"The clip must actually restart after its end")
        w.looping=false
        try await wait{!w.playing && w.frameIndex==8 && w.frame?.index==8}
        XCTAssertEqual(w.frameIndex,8)
        w.play();try await wait{w.playing};try await Task.sleep(for:.milliseconds(70))
        XCTAssertLessThan(w.playback!.player.currentTime().seconds,0.2,"Replay starts at the beginning")
        w.stopAndSave()
    }
    func testComparisonStopsBothPlayersAtCommonExclusiveEnd() async throws {
        let repository=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repository.create(name:"对比边界",sport:.pitching)
        let a=try await fixture("short",fps:30,duration:0.2),b=try await fixture("long",fps:60,duration:0.5)
        _=try await repository.importVideo(a,into:session);_=try await repository.importVideo(b,into:session)
        let w=track(ComparisonWorkspace(session:session,repository:repository));await w.load();w.loop=false;w.play();try await wait{w.playing}
        try await wait{!w.playing && w.time>=0.199}
        try await wait{w.left.frame?.index==5 && w.right.frame?.index==11}
        XCTAssertEqual(w.left.frameIndex,5);XCTAssertEqual(w.right.frameIndex,11)
        XCTAssertLessThan(w.right.frame!.requestedTime.seconds,0.2)
        XCTAssertEqual(w.right.playback!.player.rate,0) // Paused rendering no longer seeks a hidden AVPlayer.
        w.pause()
        XCTAssertNil(ComparisonClock(leftAnchor:0,rightAnchor:0,leftRange:0...1,rightRange:1...2).commonRange)
    }
    static func pixel(_ image:CGImage,x:Int,y:Int)->(Int,Int,Int) {
        var data=[UInt8](repeating:0,count:image.width*image.height*4)
        let context=CGContext(data:&data,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        let i=(y*image.width+x)*4;return (Int(data[i]),Int(data[i+1]),Int(data[i+2]))
    }
}
