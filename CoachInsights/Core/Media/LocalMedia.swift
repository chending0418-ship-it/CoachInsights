import AVFoundation

/// Recreates Photos' presentation timing from the original immutable local movie.
enum LocalMedia {
    static func asset(url: URL, metadata: MediaMetadata) async throws -> AVAsset {
        let source = AVURLAsset(url: url)
        let segments = metadata.timeline.segments
        guard segments.count > 1 || segments.contains(where: {
            abs($0.sourceDuration.seconds - $0.presentationDuration.seconds) > 0.00001
                || abs($0.sourceStart.seconds - $0.presentationStart.seconds) > 0.00001
        }) else { return source }
        let composition = AVMutableComposition()
        for type in [AVMediaType.video, .audio] {
            guard let input = try await source.loadTracks(withMediaType: type).first,
                  let output = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            output.preferredTransform = try await input.load(.preferredTransform)
            for segment in segments {
                let sourceRange = CMTimeRange(start: segment.sourceStart.cmTime, duration: segment.sourceDuration.cmTime)
                try output.insertTimeRange(sourceRange, of: input, at: segment.presentationStart.cmTime)
                output.scaleTimeRange(CMTimeRange(start: segment.presentationStart.cmTime, duration: segment.sourceDuration.cmTime),
                                      toDuration: segment.presentationDuration.cmTime)
            }
        }
        return composition
    }
}
