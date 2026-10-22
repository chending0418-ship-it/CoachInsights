import SwiftUI
import AVFoundation

@MainActor final class AnalysisWorkspace: ObservableObject {
    let session: AnalysisSession
    let repository: LibraryRepository
    @Published var snapshot = SessionSnapshot() {
        didSet { if snapshot.poseResults != oldValue.poseResults { rebuildPoseIndex() } }
    }
    @Published var assets: [VideoAsset] = []
    @Published var selectedVideoID: UUID?
    @Published var metadata: MediaMetadata?
    @Published var frame: ResolvedFrame?
    @Published var thumbnails: [UIImage] = []
    @Published var frameIndex = 0
    @Published var playing = false
    @Published var rate: Double = 1
    @Published var seeking = false
    @Published var preparing = false
    @Published var scrubbing = false
    var overlaysVisible:Bool {
        get { snapshot.overlayVisibility[key] ?? true }
        set { snapshot.overlayVisibility[key]=newValue;save() }
    }
    private var loadedSnapshot = false
    private var prefetchTask: Task<Void, Never>?
    private var scrubTask: Task<Void, Never>?
    private var poseFrames: [UUID: [MediaTime: PoseFrame]] = [:]
    private var poseConfigurations: [UUID: PoseResult] = [:]
    @Published var looping = true
    private var reachedEnd=false
    @Published var muted = true
    @Published var issue: String?
    @Published var saveIssue: String?
    @Published var notice: String?
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var tool = "view" { didSet { if tool != "view" { pause() } } }
    @Published var color = "#722F37"
    @Published var lineWidth: Double = 3
    @Published var textValue = "关注点"
    @Published var selectedAnnotation: UUID? { didSet { loadSelectionStyle() } }
    @Published var rangeMode = "单帧"
    @Published var undoStack: [[Annotation]] = []
    @Published var redoStack: [[Annotation]] = []
    @Published var poseBusy = false
    @Published var poseProgress: Double = 0
    var externallyClocked = false
    var externalSave: ((SessionSnapshot) -> Void)?
    var playback: PlaybackCoordinator?
    var provider: FrameProvider?
    var avAsset: AVAsset?
    var importTask: Task<Void, Never>?
    var poseTask: Task<Void, Never>?
    private let runner = LatestTaskRunner<ResolvedFrame>()
    private var observer: Any?
    private var endObserver:NSObjectProtocol?
    private var loadGeneration = 0
    private var thumbnailTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?
    init(session: AnalysisSession, repository: LibraryRepository) { self.session = session; self.repository = repository }
    var selectedAsset: VideoAsset? { assets.first { $0.id == selectedVideoID } }
    var key: String { selectedVideoID?.uuidString ?? "" }
    var time: Double { metadata?.timeline.frames[safe: frameIndex]?.presentationTime.seconds ?? 0 }
    var clip: ClipRange {
        snapshot.clips[key] ?? ClipRange(start: MediaTime(seconds: 0), end: metadata?.timeline.duration ?? MediaTime(seconds: 1))
    }
    var viewSettings: ViewSettings { snapshot.views[key] ?? ViewSettings() }
    var visibleAnnotations: [Annotation] {
        (overlaysVisible ? snapshot.annotations : []).filter { $0.videoID == selectedVideoID && AnalysisRenderer.visible($0, at: displayTime, tolerance: 0.00001) }
    }
    var poseSettings: PoseSettings {
        get { snapshot.poseConfigurations[key] ?? snapshot.poseSettings }
        set { snapshot.poseConfigurations[key] = newValue }
    }
    var frameReady: Bool { !seeking && !scrubbing && frame?.index == frameIndex }
    // Overlay time follows the displayed image while seeking, never a requested future frame.
    var displayTime: Double { playing ? time : frame?.requestedTime.seconds ?? time }
    var currentPose: PoseFrame? {
        guard overlaysVisible,poseSettings.visible,let selectedAsset,
              let result=poseConfigurations[selectedAsset.id],result.contentHash==selectedAsset.contentHash,
              result.settings.matchesAnalysis(poseSettings) else { return nil }
        let pts=playing ? metadata?.timeline.frames[safe:frameIndex]?.presentationTime : frame?.requestedTime
        return pts.flatMap { poseFrames[selectedAsset.id]?[$0] }
    }
    private func rebuildPoseIndex() {
        poseFrames=[:];poseConfigurations=[:]
        for result in snapshot.poseResults {
            poseConfigurations[result.videoID]=result
            poseFrames[result.videoID]=Dictionary(result.frames.map { ($0.time,$0) },uniquingKeysWith:{_,new in new})
        }
    }
    func setRate(_ value: Double) {
        guard [1.0,0.5,0.25,0.1,0.05].contains(value) else { return }
        rate=value;snapshot.playbackRates[key]=value
        if playing { playback?.player.rate=Float(value) }
        save()
    }
    func beginScrubbing() {
        pause(refreshFrame:false);runner.cancel();prefetchTask?.cancel();scrubTask?.cancel()
        scrubTask=nil;scrubbing=true;seeking=false
    }
    func scrub(to seconds:Double) {
        if !scrubbing { beginScrubbing() }
        guard let metadata,let bounds=metadata.timeline.frameBounds(in:clip),let provider else { return }
        frameIndex=min(bounds.upperBound,max(bounds.lowerBound,metadata.timeline.nearestFrame(to:MediaTime(seconds:max(0,seconds)))))
        // A single preview worker samples the latest target while the finger moves.
        // Debouncing every change would starve previews during a continuous drag.
        guard scrubTask == nil else { return }
        let generation=loadGeneration
        scrubTask=Task { [weak self] in
            var displayed = -1
            while !Task.isCancelled,let self,self.scrubbing,self.loadGeneration==generation {
                let target=self.frameIndex
                do {
                    if target != displayed {
                        let image=try await provider.preview(at:target)
                        try Task.checkCancellation()
                        guard self.scrubbing,self.loadGeneration==generation else { return }
                        self.frame=image;displayed=target
                    }
                    try await Task.sleep(for:.milliseconds(33))
                } catch is CancellationError { return }
                catch { try? await Task.sleep(for:.milliseconds(50)) }
            }
        }
    }

    func endScrubbing() {
        scrubTask?.cancel();scrubTask=nil;scrubbing=false;seek(frame:frameIndex);save()
    }
    func reload(openVideo:Bool=true) async {
        do {
            snapshot = try session.snapshot(); loadedSnapshot=true
            assets = try repository.assets().filter { snapshot.videoIDs.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
            let id = selectedVideoID ?? assets.first?.id
            if openVideo,let id { await select(id) }
        } catch { issue = error.localizedDescription }
    }
    /// A child editor can attach media or save a comparison. Merge it before the
    /// retained single-video workspace saves again; keep its local playback state.
    func refreshPersistedChanges() {
        guard loadedSnapshot else { return }
        do {
            snapshot=try session.snapshot()
            assets=try repository.assets().filter{snapshot.videoIDs.contains($0.id)}.sorted{$0.createdAt<$1.createdAt}
            if let metadata { snapshot.playheads[key]=metadata.timeline.frames[safe:frameIndex]?.presentationTime }
        } catch { saveIssue=error.localizedDescription }
    }
    func resumeFrame() {
        if metadata != nil,!playing,!seeking,frame?.index != frameIndex { seek(frame:frameIndex) }
    }
    func resumeDisplay() {
        refreshPersistedChanges();resumeFrame()
        if let metadata,let avAsset,let asset=selectedAsset,thumbnails.count<min(12,metadata.timeline.frames.count) {
            thumbnails=[];makeThumbnails(avAsset,metadata:metadata,hash:asset.contentHash)
        }
    }
    func setClipBoundary(frame index:Int,start:Bool) {
        guard let metadata,let bounds=metadata.timeline.frameBounds(in:clip) else { return }
        pause()
        let index=metadata.timeline.steppedIndex(from:index,by:0)
        if start {
            let safe=min(index,bounds.upperBound)
            snapshot.clips[key]=ClipRange(start:metadata.timeline.frames[safe].presentationTime,end:clip.end)
        } else {
            let safe=max(index,bounds.lowerBound),sample=metadata.timeline.frames[safe]
            snapshot.clips[key]=ClipRange(start:clip.start,end:min(metadata.timeline.duration,MediaTime(seconds:sample.presentationTime.seconds+sample.duration.seconds)))
        }
        seek(frame:frameIndex)
    }
    func select(_ id: UUID) async {
        pause(); runner.cancel(); thumbnailTask?.cancel(); poseTask?.cancel();prefetchTask?.cancel();scrubTask?.cancel();scrubbing=false
        if let observer, let playback { playback.player.removeTimeObserver(observer) }; observer = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver=nil
        loadGeneration += 1; let generation = loadGeneration
        do {
            guard let asset = assets.first(where: { $0.id == id }) else { throw StorageFailure.missingMedia }
            selectedVideoID = id; metadata = nil; frame = nil; thumbnails = []; selectedAnnotation = nil;playback=nil;provider=nil;seeking=false;preparing=false
            let metadata = try asset.metadata()
            let url = try await repository.files.existingURL(asset.relativePath)
            let local = try await LocalMedia.asset(url: url, metadata: metadata)
            guard generation == loadGeneration else { return }
            self.metadata = metadata; avAsset = local
            rate = snapshot.playbackRates[key] ?? 1
            let playback = PlaybackCoordinator(asset: local, timeline: metadata.timeline)
            playback.player.isMuted = muted
            self.playback = playback
            provider = FrameProvider(asset: local, metadata: metadata)
            observer = playback.player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
                Task { @MainActor in self?.tick(time.seconds) }
            }
            endObserver=NotificationCenter.default.addObserver(forName:AVPlayerItem.didPlayToEndTimeNotification,object:playback.player.currentItem,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.handleBoundary() }
            }
            seek(time: snapshot.playheads[key]?.seconds ?? clip.start.seconds)
            makeThumbnails(local, metadata: metadata, hash: asset.contentHash)
            issue = nil
        } catch { if generation == loadGeneration { issue = error.localizedDescription;seeking=false } }
    }
    func seek(time: Double, preferEarlier:Bool=false) {
        guard let metadata else { return }
        let value=MediaTime(seconds:min(clip.end.seconds-0.000001,max(clip.start.seconds,time)))
        seek(frame:preferEarlier ? metadata.timeline.presentingFrame(at:value):metadata.timeline.nearestFrame(to:value))
    }
    func seek(frame index: Int) {
        guard let provider, playback != nil, let metadata else { return }
        pause(refreshFrame:false);prefetchTask?.cancel();scrubTask?.cancel();scrubbing=false
        guard let bounds = metadata.timeline.frameBounds(in: clip) else { issue = "片段没有可读取的帧，请恢复完整视频。"; return }
        let index = min(bounds.upperBound, max(bounds.lowerBound, index))
        if index != frameIndex { selectedAnnotation=nil }
        frameIndex = index;reachedEnd=false
        snapshot.playheads[key] = metadata.timeline.frames[index].presentationTime
        seeking=true
        runner.submit(operation: {
            let frame = try await provider.frame(at: index)
            try Task.checkCancellation()
            return frame
        }, result: { [weak self] result in
            guard let self else { return }
            switch result { case .success(let value):
                self.frame = value;self.seeking=false
                self.prefetchTask=Task { [weak self] in
                    do { try await Task.sleep(for:.milliseconds(80)) } catch { return }
                    guard let self,!self.playing,!self.scrubbing else { return }
                    await provider.prefetch(around:value.index)
                }
            case .failure(let error): self.seeking=false;self.issue = error.localizedDescription }
        })
    }
    func cancelFrameRequest() { runner.cancel();scrubTask?.cancel();prefetchTask?.cancel();seeking=false;scrubbing=false }
    func step(_ delta: Int) { seek(frame: frameIndex + delta) }
    func play() {
        guard let playback,let metadata,let bounds=metadata.timeline.frameBounds(in:clip) else { return }
        if playing { playback.player.rate=Float(rate);return }
        if scrubbing { endScrubbing() }
        runner.cancel();prefetchTask?.cancel();selectedAnnotation=nil;tool="view";seeking=false;preparing=true
        if reachedEnd { frameIndex=bounds.lowerBound };reachedEnd=false
        playback.player.currentItem?.forwardPlaybackEndTime=clip.end.cmTime
        let index=frameIndex
        endTask?.cancel()
        endTask=Task { [weak self] in
            guard let self else { return }
            let ready=abs(playback.player.currentTime().seconds-metadata.timeline.frames[index].presentationTime.seconds)<0.000001 ? true : await playback.seek(frame:index)
            guard !Task.isCancelled else { return }
            preparing=false
            guard ready else { issue="视频暂时无法播放，请重试。";return }
            playback.player.isMuted=muted;playing=true;playback.player.playImmediately(atRate:Float(rate))
        }
    }
    private var activeClip:ClipRange {
        guard let end=playback?.player.currentItem?.forwardPlaybackEndTime,end.isNumeric,end.seconds>clip.start.seconds else { return clip }
        return ClipRange(start:clip.start,end:min(clip.end,MediaTime(end)))
    }
    func pause(refreshFrame:Bool=true) {
        let wasPlaying=playing
        endTask?.cancel();preparing=false
        if wasPlaying,let metadata,let seconds=playback?.player.currentTime().seconds,seconds.isFinite {
            frameIndex=metadata.timeline.presentingFrame(at:MediaTime(seconds:seconds),in:activeClip) ?? frameIndex
        }
        playback?.player.pause();playing=false
        if let metadata { snapshot.playheads[key]=metadata.timeline.frames[safe:frameIndex]?.presentationTime }
        if wasPlaying && refreshFrame { seek(frame:frameIndex) }
    }
    func stopAndSave() {
        if scrubbing { endScrubbing() }
        pause();cancelFrameRequest();thumbnailTask?.cancel();poseTask?.cancel();importTask?.cancel();save()
    }
    /// Await cancelled I/O before destroying a temporary repository or its database.
    func shutdown() async {
        let pending=[thumbnailTask,poseTask,importTask,prefetchTask,scrubTask,endTask].compactMap{$0}
        stopAndSave()
        for worker in pending { await worker.value }
        thumbnailTask=nil;poseTask=nil;importTask=nil;prefetchTask=nil;scrubTask=nil;endTask=nil
        if let observer,let playback { playback.player.removeTimeObserver(observer) };observer=nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) };endObserver=nil
        playback?.player.replaceCurrentItem(with:nil);playback=nil;provider=nil;avAsset=nil
    }
    func save() {
        guard loadedSnapshot else { return }
        if let externalSave { externalSave(snapshot); return }
        do { try repository.save(session, snapshot: snapshot); saveIssue=nil } catch { saveIssue = error.localizedDescription }
    }
    private func tick(_ observed: Double) {
        let seconds=playback?.player.currentTime().seconds ?? observed
        guard playing, seconds.isFinite, let metadata else { return }
        frameIndex = metadata.timeline.presentingFrame(at:MediaTime(seconds:seconds),in:activeClip) ?? frameIndex
        if externallyClocked { return }
        if seconds >= clip.end.seconds { handleBoundary() }
    }
    private func handleBoundary() {
        guard playing,!externallyClocked,let metadata,let playback,
              let bounds=metadata.timeline.frameBounds(in:clip) else { return }
        guard playback.player.currentTime().seconds >= clip.end.seconds-0.00001 else { return }
        let shouldLoop=looping
        if shouldLoop {
            endTask?.cancel();runner.cancel();frameIndex=bounds.lowerBound;reachedEnd=false
            snapshot.playheads[key]=metadata.timeline.frames[frameIndex].presentationTime
            let index=frameIndex
            endTask=Task { [weak self] in
                guard let self else { return }
                let ready=await playback.seek(frame:index)
                guard !Task.isCancelled else { return }
                guard ready else { issue="循环播放未能定位，请重试。";return }
                playing=true;playback.player.playImmediately(atRate:Float(rate))
            }
        } else {
            pause(refreshFrame:false);seek(frame:bounds.upperBound);reachedEnd=true;save()
        }
    }
    func updateView(_ value: ViewSettings) { snapshot.views[key] = value; save() }
    func markStart() {
        guard time < clip.end.seconds else { return }
        guard let metadata else { return }
        snapshot.clips[key] = ClipRange(start: metadata.timeline.frames[frameIndex].presentationTime, end: clip.end); save()
    }
    func markEnd() {
        guard let metadata else { return }
        let sample=metadata.timeline.frames[frameIndex]
        let end=MediaTime(CMTimeAdd(sample.presentationTime.cmTime,sample.duration.cmTime))
        guard end > clip.start else { return }
        snapshot.clips[key] = ClipRange(start: clip.start, end: min(metadata.timeline.duration,end)); save()
    }
    func fullClip() {
        guard let metadata else { return }
        snapshot.clips[key] = ClipRange(start: metadata.timeline.frames[0].presentationTime, end: metadata.timeline.duration); save()
    }
    func add(points: [UnitPointValue]) {
        guard let selectedVideoID, let metadata, !points.isEmpty else { return }
        recordHistory()
        let sample = metadata.timeline.frames[frameIndex]
        let range = rangeMode == "片段" ? clip : ClipRange(start: sample.presentationTime,
                                  end: MediaTime(CMTimeAdd(sample.presentationTime.cmTime,sample.duration.cmTime)))
        let value = Annotation(videoID: selectedVideoID, kind: tool, points: points, color: color, lineWidth: lineWidth,
                               text: tool == "text" ? textValue : nil, range: range)
        snapshot.annotations.append(value); selectedAnnotation = value.id; save()
    }
    func replace(_ value: Annotation) {
        guard let index = snapshot.annotations.firstIndex(where: { $0.id == value.id }), snapshot.annotations[index] != value else { return }
        recordHistory(); snapshot.annotations[index] = value; loadSelectionStyle(); save()
    }
    private func loadSelectionStyle() {
        guard let value=snapshot.annotations.first(where:{$0.id==selectedAnnotation}) else { return }
        color=value.color;textValue=value.text ?? textValue;lineWidth=value.lineWidth
    }
    func styleSelection() {
        if var value = snapshot.annotations.first(where: { $0.id == selectedAnnotation }) {
            value.color = color; value.lineWidth = lineWidth; if value.kind == "text" { value.text = textValue }; replace(value)
        }
    }
    func deleteSelection() {
        guard let selectedAnnotation else { return }; recordHistory()
        snapshot.annotations.removeAll { $0.id == selectedAnnotation }; self.selectedAnnotation = nil; save()
    }
    private func recordHistory() { undoStack.append(snapshot.annotations); if undoStack.count > 50 { undoStack.removeFirst() }; redoStack.removeAll() }
    func undo() { guard let value = undoStack.popLast() else { return }; redoStack.append(snapshot.annotations); snapshot.annotations = value; loadSelectionStyle(); save() }
    func redo() { guard let value = redoStack.popLast() else { return }; undoStack.append(snapshot.annotations); snapshot.annotations = value; loadSelectionStyle(); save() }
    func addKeyframe(_ name: String) {
        guard let selectedVideoID else { return }
        snapshot.keyframes.append(Keyframe(videoID: selectedVideoID, time: metadata?.timeline.frames[frameIndex].presentationTime ?? MediaTime(seconds:time), name: name.isEmpty ? "关键帧" : name)); save()
    }
    func removeKeyframe(_ id: UUID) { snapshot.keyframes.removeAll { $0.id == id }; save() }
    func importFile(_ url: URL, timing: MediaMetadata? = nil) {
        guard !busy else { return }; busy = true; progress = 0; pause()
        importTask = Task { [weak self] in
            guard let self else { return }; defer { busy = false }
            do {
                let asset = try await repository.importVideo(url, into: session, timing: timing) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                selectedVideoID = asset.id; try Task.checkCancellation(); await reload()
            } catch is CancellationError { notice = "已取消导入。" }
            catch { issue = error.localizedDescription }
        }
    }
    private func makeThumbnails(_ asset: AVAsset, metadata: MediaMetadata, hash: String) {
        thumbnailTask?.cancel()
        let generation=loadGeneration
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            let provider=FrameProvider(asset:asset,metadata:metadata,maximumDimension:240,costLimit:4*1024*1024)
            do {
                let store=repository.thumbnails
                // First-frame resolution takes priority over background contact-sheet work.
                while frame == nil && !Task.isCancelled { try await Task.sleep(for:.milliseconds(20)) }
                for index in 0..<min(12,metadata.timeline.frames.count) {
                    try Task.checkCancellation()
                    let sample=index*max(1,metadata.timeline.frames.count-1)/max(1,min(12,metadata.timeline.frames.count)-1)
                    let image=try await store.image(contentHash:hash,frame:sample,provider:provider)
                    guard !Task.isCancelled,generation==loadGeneration else { return }
                    thumbnails.append(image)
                    try await Task.sleep(for:.milliseconds(15))
                }
            } catch {}
        }
    }
    deinit {
        thumbnailTask?.cancel(); endTask?.cancel(); importTask?.cancel(); poseTask?.cancel();prefetchTask?.cancel();scrubTask?.cancel()
        if let observer, let playback { playback.player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
