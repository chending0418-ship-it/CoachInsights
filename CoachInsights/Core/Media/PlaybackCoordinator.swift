import AVFoundation
import UIKit

@MainActor final class PlaybackCoordinator {
    let player: AVPlayer
    let timeline: MediaTimeMap
    private var generation: UInt64 = 0
    init(asset: AVAsset, timeline: MediaTimeMap) {
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        self.timeline = timeline
    }
    @discardableResult func seek(frame index: Int) async -> Bool {
        guard !Task.isCancelled else { return false }
        generation &+= 1
        let token = generation
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        let index = timeline.steppedIndex(from: index, by: 0)
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            if self?.generation == token { self?.player.currentItem?.cancelPendingSeeks() }
        }
        defer { timeout.cancel() }
        let completed = await withTaskCancellationHandler {
            await player.seek(to: timeline.frames[index].presentationTime.cmTime,
                              toleranceBefore: .zero, toleranceAfter: .zero)
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.generation == token { self?.player.currentItem?.cancelPendingSeeks() }
            }
        }
        return completed && token == generation && !Task.isCancelled
    }
}

struct ComparisonClock {
    let leftAnchor: Double, rightAnchor: Double
    let leftRange: ClosedRange<Double>, rightRange: ClosedRange<Double>
    var commonRange: ClosedRange<Double>? {
        let start = max(leftRange.lowerBound - leftAnchor, rightRange.lowerBound - rightAnchor)
        let end = min(leftRange.upperBound - leftAnchor, rightRange.upperBound - rightAnchor)
        return start < end ? start...end : nil
    }
    func times(at analysisTime: Double) -> (Double, Double)? {
        guard let range = commonRange else { return nil }
        let time = min(range.upperBound, max(range.lowerBound, analysisTime))
        return (time + leftAnchor, time + rightAnchor)
    }
}

@MainActor final class DualPlaybackCoordinator {
    let left: PlaybackCoordinator, right: PlaybackCoordinator
    let clock: ComparisonClock
    init(left: PlaybackCoordinator, right: PlaybackCoordinator, clock: ComparisonClock) {
        self.left = left; self.right = right; self.clock = clock
    }
    func frameIndices(at analysisTime:Double)->(Int,Int)? {
        guard let times=clock.times(at:analysisTime),let range=clock.commonRange else { return nil }
        let a=ClipRange(start:MediaTime(seconds:clock.leftRange.lowerBound),end:MediaTime(seconds:range.upperBound+clock.leftAnchor))
        let b=ClipRange(start:MediaTime(seconds:clock.rightRange.lowerBound),end:MediaTime(seconds:range.upperBound+clock.rightAnchor))
        guard let i=left.timeline.presentingFrame(at:MediaTime(seconds:times.0),in:a),let j=right.timeline.presentingFrame(at:MediaTime(seconds:times.1),in:b) else { return nil }
        return (i,j)
    }
    func prepare(at analysisTime: Double) async throws {
        guard clock.times(at: analysisTime) != nil else { throw MediaFailure.invalidTiming }
        try await waitUntilReady()
        // Preparation can complete separately; playback starts together on the shared host clock.
        guard let indices=frameIndices(at:analysisTime) else { throw MediaFailure.invalidTiming }
        let first = await left.seek(frame: indices.0)
        let second = await right.seek(frame: indices.1)
        guard first && second else { throw MediaFailure.readFailed }
    }
    func start(at analysisTime: Double, rate: Float) throws {
        guard let (a, b) = clock.times(at: analysisTime), rate.isFinite, rate > 0 else {
            throw MediaFailure.invalidTiming
        }
        guard let range=clock.commonRange else { throw MediaFailure.invalidTiming }
        left.player.currentItem?.forwardPlaybackEndTime=MediaTime(seconds:range.upperBound+clock.leftAnchor).cmTime
        right.player.currentItem?.forwardPlaybackEndTime=MediaTime(seconds:range.upperBound+clock.rightAnchor).cmTime
        let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(seconds: 0.15, preferredTimescale: 600_000))
        left.player.setRate(rate, time: MediaTime(seconds: a).cmTime, atHostTime: host)
        right.player.setRate(rate, time: MediaTime(seconds: b).cmTime, atHostTime: host)
    }
    func pause() { left.player.pause(); right.player.pause() }
    var drift: Double {
        abs((left.player.currentTime().seconds - clock.leftAnchor)
            - (right.player.currentTime().seconds - clock.rightAnchor))
    }
    func correctIfNeeded(tolerance: Double) async throws {
        guard drift > tolerance else { return }
        let time = left.player.currentTime().seconds - clock.leftAnchor
        let rate = left.player.rate
        pause()
        try await prepare(at: time)
        if rate > 0 { try start(at: time, rate: rate) }
    }
    private func waitUntilReady() async throws {
        for _ in 0..<100 {
            if left.player.currentItem?.status == .failed { throw left.player.currentItem?.error ?? MediaFailure.readFailed }
            if right.player.currentItem?.status == .failed { throw right.player.currentItem?.error ?? MediaFailure.readFailed }
            if left.player.currentItem?.status == .readyToPlay && right.player.currentItem?.status == .readyToPlay { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw MediaFailure.readFailed
    }
}

final class PlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
