import SwiftUI
import AVFoundation

@MainActor final class ComparisonWorkspace: ObservableObject {
    let session:AnalysisSession
    let repository:LibraryRepository
    @Published var left:AnalysisWorkspace
    @Published var right:AnalysisWorkspace
    @Published var setup:ComparisonSetup?
    @Published var time:Double=0
    @Published var playing=false
    @Published var issue:String?
    @Published var loop=true
    @Published var drift:Double=0
    @Published var independent=false
    private var newLayout=false
    private var layoutAdapted=false
    private var dual:DualPlaybackCoordinator?
    private var task:Task<Void,Never>?
    private var ticker:Task<Void,Never>?
    init(session:AnalysisSession,repository:LibraryRepository) {
        self.session=session;self.repository=repository
        left=AnalysisWorkspace(session:session,repository:repository);right=AnalysisWorkspace(session:session,repository:repository)
        left.externallyClocked=true;right.externallyClocked=true
    }
    var range:ClosedRange<Double>? { dual?.clock.commonRange }
    func refreshAssets() async {
        for w in [left,right] {
            let view=w.viewSettings,clip=w.clip
            w.snapshot=(try? session.snapshot()) ?? w.snapshot
            if w.metadata != nil { w.snapshot.views[w.key]=view;w.snapshot.clips[w.key]=clip }
            w.assets=(try? repository.assets().filter{w.snapshot.videoIDs.contains($0.id)}.sorted{$0.createdAt<$1.createdAt}) ?? w.assets
        }
    }
    func load(initialVideoID:UUID?=nil,secondVideoID:UUID?=nil) async {
        pause()
        do {
            await left.reload(openVideo:false);await right.reload(openVideo:false)
            let snapshot=try session.snapshot()
            guard let first=left.assets.first(where:{$0.id==initialVideoID}) ?? left.assets.first else { return }
            let saved=snapshot.comparison
            if secondVideoID == nil,let saved,(initialVideoID == nil || saved.leftVideoID == initialVideoID) { setup=saved;newLayout=false }
            else {
                guard let second=left.assets.first(where:{$0.id==secondVideoID && $0.id != first.id}) ?? left.assets.first(where:{$0.id != first.id}) else { await left.select(first.id);setup=nil;return }
                let a=try first.metadata(),b=try second.metadata()
                let rightClip=snapshot.clips[second.id.uuidString] ?? ClipRange(start:b.timeline.frames[0].presentationTime,end:b.timeline.duration)
                setup=ComparisonSetup(leftVideoID:first.id,rightVideoID:second.id,
                    leftAnchor:snapshot.playheads[first.id.uuidString] ?? a.timeline.frames[0].presentationTime,rightAnchor:rightClip.start,
                    leftClip:snapshot.clips[first.id.uuidString] ?? ClipRange(start:a.timeline.frames[0].presentationTime,end:a.timeline.duration),
                    rightClip:rightClip,rate:snapshot.playbackRates[first.id.uuidString] ?? 1,
                    leftView:snapshot.views[first.id.uuidString] ?? ViewSettings(),rightView:snapshot.views[second.id.uuidString] ?? ViewSettings())
                newLayout=true;layoutAdapted=false
            }
            guard let setup else { return }
            await left.select(setup.leftVideoID);await right.select(setup.rightVideoID)
            left.snapshot.views[left.key]=setup.leftView;right.snapshot.views[right.key]=setup.rightView
            left.snapshot.clips[left.key]=setup.leftClip;right.snapshot.clips[right.key]=setup.rightClip
            left.externalSave={ [weak self] snapshot in self?.viewChanged(snapshot,isLeft:true) }
            right.externalSave={ [weak self] snapshot in self?.viewChanged(snapshot,isLeft:false) }
            rebuild();seek(0)
        } catch { issue=error.localizedDescription }
    }
    func adaptLayout(width:CGFloat,height:CGFloat) {
        guard newLayout,!layoutAdapted,setup != nil else { return }
        setup?.layout=width<600 && height>width ? "vertical":"horizontal";layoutAdapted=true;save()
    }
    func independentSeek(_ seconds:Double,isLeft:Bool) {
        pause();independent=true
        (isLeft ? left:right).scrub(to:seconds)
        if let setup,let range {
            let anchor=isLeft ? setup.leftAnchor:setup.rightAnchor
            time=min(range.upperBound,max(range.lowerBound,seconds-anchor.seconds))
        }
    }
    func frameOffset(_ delta:Int,isLeft:Bool) {
        let w=isLeft ? left:right
        guard let map=w.metadata?.timeline else { return }
        let current=isLeft ? setup?.leftAnchor:setup?.rightAnchor
        let start=map.nearestFrame(to:current ?? MediaTime(seconds:w.time))
        let next=map.steppedIndex(from:start,by:delta)
        offset(map.frames[next].presentationTime.seconds-map.frames[start].presentationTime.seconds,isLeft:isLeft)
    }
    func setRate(_ value:Double) {
        guard [1.0,0.5,0.25,0.1,0.05].contains(value) else { return }
        setup?.rate=value
        if playing,let dual { dual.left.player.rate=Float(value);dual.right.player.rate=Float(value) }
        save()
    }
    func resumeFrames() { left.resumeFrame();right.resumeFrame() }
    func shutdown() async { let pending=[task,ticker].compactMap{$0};pause();for worker in pending { await worker.value };await left.shutdown();await right.shutdown();save();task=nil;ticker=nil }
    func stopAndSave() { pause();left.stopAndSave();right.stopAndSave();save() }
    func replace(_ id:UUID,isLeft:Bool) async {
        pause();if isLeft { await left.select(id) } else { await right.select(id) }
        guard var setup,let metadata=(isLeft ? left.metadata:right.metadata) else { return }
        let clip=ClipRange(start:metadata.timeline.frames[0].presentationTime,end:metadata.timeline.duration)
        if isLeft { setup.leftVideoID=id;setup.leftAnchor=clip.start;setup.leftClip=clip;setup.leftView=ViewSettings();left.snapshot.views[left.key]=setup.leftView;left.snapshot.clips[left.key]=clip }
        else { setup.rightVideoID=id;setup.rightAnchor=clip.start;setup.rightClip=clip;setup.rightView=ViewSettings();right.snapshot.views[right.key]=setup.rightView;right.snapshot.clips[right.key]=clip }
        self.setup=setup;rebuild();seek(0);save()
    }
    func anchor(isLeft:Bool) {
        pause();guard var setup else { return }
        if isLeft { setup.leftAnchor=left.metadata?.timeline.frames[left.frameIndex].presentationTime ?? MediaTime(seconds:left.time) } else { setup.rightAnchor=right.metadata?.timeline.frames[right.frameIndex].presentationTime ?? MediaTime(seconds:right.time) }
        self.setup=setup;rebuild();seek(0);save()
    }
    func offset(_ delta:Double,isLeft:Bool) {
        guard var setup else { return };pause()
        if isLeft { setup.leftAnchor=MediaTime(seconds:min(setup.leftClip.end.seconds,max(setup.leftClip.start.seconds,setup.leftAnchor.seconds+delta))) }
        else { setup.rightAnchor=MediaTime(seconds:min(setup.rightClip.end.seconds,max(setup.rightClip.start.seconds,setup.rightAnchor.seconds+delta))) }
        self.setup=setup;rebuild();seek(0);save()
    }
    func trim(isLeft:Bool,start:Bool) {
        pause();guard var setup else { return };let w=isLeft ? left:right
        if start { w.markStart() } else { w.markEnd() }
        if isLeft { setup.leftClip=w.clip } else { setup.rightClip=w.clip }
        self.setup=setup;rebuild();seek(time);save()
    }
    func seek(_ value:Double) {
        pause();independent=false;guard let dual,let range=range,let indices=dual.frameIndices(at:value) else { return }
        time=min(range.upperBound,max(range.lowerBound,value));left.seek(frame:indices.0);right.seek(frame:indices.1)
    }
    func step(_ delta:Int) {
        guard let map=left.metadata?.timeline,let setup else { return }
        let index=map.steppedIndex(from:left.frameIndex,by:delta)
        seek(map.frames[index].presentationTime.seconds-setup.leftAnchor.seconds)
    }
    func play() {
        guard let dual,let setup,let range else { return }
        pause();independent=false;if left.scrubbing { left.endScrubbing() };if right.scrubbing { right.endScrubbing() }
        if time>=range.upperBound-0.001 { time=range.lowerBound }
        task=Task { [weak self] in
            guard let self else { return }
            do {
                left.cancelFrameRequest();right.cancelFrameRequest()
                try await dual.prepare(at:time);try Task.checkCancellation()
                left.cancelFrameRequest();right.cancelFrameRequest()
                if let indices=dual.frameIndices(at:time) { left.frameIndex=indices.0;right.frameIndex=indices.1 }
                try dual.start(at:time,rate:Float(setup.rate));playing=true;left.playing=true;right.playing=true
                ticker=Task { [weak self] in
                    guard let self else { return }
                    var refresh=0
                    while !Task.isCancelled && playing {
                        do { try await Task.sleep(for:.milliseconds(33)) } catch { return }
                        guard !Task.isCancelled else { return }
                        let observed=dual.left.player.currentTime().seconds-setup.leftAnchor.seconds
                        time=min(range.upperBound,max(range.lowerBound,observed));drift=dual.drift
                        if observed>=range.upperBound-0.000001 {
                            let shouldLoop=self.loop;pause()
                            if shouldLoop { time=range.lowerBound;play() } else { seek(range.upperBound) }
                            return
                        }
                        let a=left.metadata?.timeline.frames[safe:left.frameIndex]?.duration.seconds ?? 1/30
                        let b=right.metadata?.timeline.frames[safe:right.frameIndex]?.duration.seconds ?? 1/30
                        let tolerance=max(0.001,min(0.035,min(a,b)*0.9))
                        refresh+=1
                        if refresh%6 == 0 { do { try await dual.correctIfNeeded(tolerance:tolerance) } catch { issue=error.localizedDescription;pause() } }
                    }
                }
            } catch is CancellationError {} catch { issue=error.localizedDescription }
        }
    }
    func pause() {
        if playing,let setup,let range,let current=left.playback?.player.currentTime().seconds,current.isFinite {
            time=min(range.upperBound,max(range.lowerBound,current-setup.leftAnchor.seconds))
        }
        task?.cancel();ticker?.cancel();dual?.pause();playing=false;left.pause();right.pause()
    }
    func save() {
        guard let setup else { return }
        do { var snapshot=try session.snapshot();snapshot.comparison=setup;try repository.save(session,snapshot:snapshot) }
        catch { issue=error.localizedDescription }
    }
    func changedSetup() { pause();rebuild();save() }
    private func viewChanged(_ snapshot:SessionSnapshot,isLeft:Bool) {
        guard var setup else { return }
        if isLeft { setup.leftView=snapshot.views[left.key] ?? ViewSettings() }
        else { setup.rightView=snapshot.views[right.key] ?? ViewSettings() }
        self.setup=setup;save()
    }
    private func rebuild() {
        guard let setup,let a=left.playback,let b=right.playback else { return }
        let clock=ComparisonClock(leftAnchor:setup.leftAnchor.seconds,rightAnchor:setup.rightAnchor.seconds,
                                  leftRange:setup.leftClip.start.seconds...setup.leftClip.end.seconds,
                                  rightRange:setup.rightClip.start.seconds...setup.rightClip.end.seconds)
        dual=DualPlaybackCoordinator(left:a,right:b,clock:clock)
        if clock.commonRange == nil { issue="两路没有共同可播放区间，请调整片段或同步点。" } else { issue=nil }
    }
    deinit { task?.cancel();ticker?.cancel() }
}
