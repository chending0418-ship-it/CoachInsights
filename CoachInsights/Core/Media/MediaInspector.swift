import AVFoundation
import Foundation

struct AffineValues: Codable, Equatable, Sendable {
    let a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
    init(_ transform: CGAffineTransform) {
        a = transform.a; b = transform.b; c = transform.c
        d = transform.d; tx = transform.tx; ty = transform.ty
    }
    var cgAffineTransform: CGAffineTransform { .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}

struct MediaMetadata: Codable, Equatable, Sendable {
    let version: Int
    let width: Double
    let height: Double
    let displayWidth: Double
    let displayHeight: Double
    let preferredTransform: AffineValues
    let codec: String
    let nominalFrameRate: Double
    let timeline: MediaTimeMap

    var displaySize: CGSize { CGSize(width: displayWidth, height: displayHeight) }
    func validateVersion() throws {
        guard version == 1, timeline.version == MediaTimeMap.schemaVersion,
              timeline.frames.allSatisfy({
                  $0.presentationTime.timescale > 0 && $0.duration.timescale > 0
              }) else { throw MediaFailure.unsupportedVersion }
        guard width > 0, height > 0, displayWidth > 0, displayHeight > 0 else {
            throw MediaFailure.invalidGeometry
        }
        _ = try MediaTimeMap(frames: timeline.frames, segments: timeline.segments, duration: timeline.duration)
    }
}

actor MediaInspector {
    func inspect(url: URL) async throws -> MediaMetadata {
        try await inspect(asset: AVURLAsset(url: url))
    }

    func inspect(asset: AVAsset) async throws -> MediaMetadata {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaFailure.noVideo
        }
        async let sizeLoad = track.load(.naturalSize)
        async let transformLoad = track.load(.preferredTransform)
        async let rateLoad = track.load(.nominalFrameRate)
        async let formatLoad = track.load(.formatDescriptions)
        async let durationLoad = asset.load(.duration)
        let (size, transform, rate, formats, duration) =
            try await (sizeLoad, transformLoad, rateLoad, formatLoad, durationLoad)
        guard duration.isNumeric, duration.seconds > 0 else { throw MediaFailure.invalidTiming }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MediaFailure.readFailed }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MediaFailure.readFailed }
        var times: [(CMTime, CMTime)] = []
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            // AVAssetReader may return zero-sample boundary markers with an invalid PTS.
            guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard time.isNumeric else { reader.cancelReading(); throw MediaFailure.invalidTiming }
            times.append((time, CMSampleBufferGetDuration(sample)))
        }
        guard reader.status == .completed else { throw reader.error ?? MediaFailure.readFailed }
        times.sort { CMTimeCompare($0.0, $1.0) < 0 }
        let frames = times.enumerated().map { index, entry -> FrameSample in
            let length: CMTime
            if index + 1 < times.count { length = CMTimeSubtract(times[index + 1].0, entry.0) }
            else if entry.1.isNumeric && entry.1.seconds > 0 { length = entry.1 }
            else { length = CMTimeSubtract(duration, entry.0) }
            return FrameSample(presentationTime: MediaTime(entry.0),
                               duration: MediaTime(length.isNumeric && length.seconds > 0
                                   ? length : CMTime(value: 1, timescale: 600_000)))
        }
        var segments: [TimelineSegment] = []
        if let compositionTrack = track as? AVCompositionTrack {
            segments = compositionTrack.segments.filter { !$0.isEmpty }.map { segment in
                let mapping = segment.timeMapping
                return TimelineSegment(
                    sourceID: segment.sourceURL?.lastPathComponent ?? "source",
                    sourceStart: MediaTime(mapping.source.start),
                    sourceDuration: MediaTime(mapping.source.duration),
                    presentationStart: MediaTime(mapping.target.start),
                    presentationDuration: MediaTime(mapping.target.duration))
            }.sorted { $0.presentationStart < $1.presentationStart }
        } else {
            let sourceID = (asset as? AVURLAsset)?.url.lastPathComponent ?? "source"
            segments = [TimelineSegment(sourceID: sourceID, sourceStart: MediaTime(.zero),
                sourceDuration: MediaTime(duration), presentationStart: MediaTime(.zero),
                presentationDuration: MediaTime(duration))]
        }
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let subtype = formats.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
        let bytes = [24, 16, 8, 0].map { UInt8((subtype >> $0) & 255) }
        let codec = String(bytes: bytes, encoding: .ascii) ?? "unknown"
        return MediaMetadata(version: 1, width: size.width, height: size.height,
            displayWidth: abs(bounds.width), displayHeight: abs(bounds.height),
            preferredTransform: AffineValues(transform), codec: codec,
            nominalFrameRate: Double(rate),
            timeline: try MediaTimeMap(frames: frames, segments: segments, duration: MediaTime(duration)))
    }
}
