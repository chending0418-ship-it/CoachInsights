import CoreMedia
import Foundation

struct MediaTime: Codable, Hashable, Comparable, Sendable {
    let value: Int64
    let timescale: Int32

    init(_ time: CMTime) {
        precondition(time.isNumeric && time.timescale > 0)
        value = time.value
        timescale = time.timescale
    }

    init(seconds: Double) {
        self.init(CMTime(seconds: seconds, preferredTimescale: 600_000))
    }

    private enum CodingKeys: String, CodingKey { case value, timescale }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        value = try values.decode(Int64.self, forKey: .value)
        timescale = try values.decode(Int32.self, forKey: .timescale)
        guard timescale > 0 else { throw MediaFailure.invalidTiming }
    }

    var cmTime: CMTime { CMTime(value: value, timescale: timescale) }
    var seconds: Double { cmTime.seconds }
    static func < (lhs: Self, rhs: Self) -> Bool { CMTimeCompare(lhs.cmTime, rhs.cmTime) < 0 }
    static func == (lhs: Self, rhs: Self) -> Bool { CMTimeCompare(lhs.cmTime, rhs.cmTime) == 0 }
    func hash(into hasher: inout Hasher) {
        let divisor = Self.gcd(value.magnitude, UInt64(timescale))
        hasher.combine(value / Int64(divisor))
        hasher.combine(Int64(timescale) / Int64(divisor))
    }
    private static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return max(x, 1)
    }
}

struct FrameSample: Codable, Equatable, Sendable {
    let presentationTime: MediaTime
    let duration: MediaTime
}

struct TimelineSegment: Codable, Equatable, Sendable {
    let sourceID: String
    let sourceStart: MediaTime
    let sourceDuration: MediaTime
    let presentationStart: MediaTime
    let presentationDuration: MediaTime

    var presentationEnd: Double { presentationStart.seconds + presentationDuration.seconds }
    func sourceTime(for presentation: Double) -> Double {
        sourceStart.seconds + (presentation - presentationStart.seconds)
            * sourceDuration.seconds / presentationDuration.seconds
    }
}

struct SourcePosition: Equatable, Sendable {
    let sourceID: String
    let seconds: Double
}

struct MediaTimeMap: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let version: Int
    let frames: [FrameSample]
    let segments: [TimelineSegment]
    let duration: MediaTime

    init(frames: [FrameSample], segments: [TimelineSegment], duration: MediaTime) throws {
        guard !frames.isEmpty, duration.seconds > 0, !segments.isEmpty else { throw MediaFailure.invalidTiming }
        guard frames.allSatisfy({ $0.presentationTime.seconds >= 0 && $0.duration.seconds > 0 }),
              zip(frames, frames.dropFirst()).allSatisfy({
                  $0.presentationTime < $1.presentationTime
              }), frames.last!.presentationTime < duration else { throw MediaFailure.invalidTiming }
        for (index, segment) in segments.enumerated() {
            guard segment.sourceDuration.seconds > 0, segment.presentationDuration.seconds > 0,
                  segment.presentationStart.seconds >= 0 else { throw MediaFailure.invalidTiming }
            if index > 0, segments[index - 1].presentationEnd > segment.presentationStart.seconds + 0.000_001 {
                throw MediaFailure.invalidTiming
            }
        }
        version = Self.schemaVersion
        self.frames = frames
        self.segments = segments
        self.duration = duration
    }

    func nearestFrame(to time: MediaTime) -> Int {
        var low = 0, high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].presentationTime < time { low = middle + 1 }
            else { high = middle }
        }
        if low == 0 { return 0 }
        if low == frames.count { return frames.count - 1 }
        let before = abs(frames[low - 1].presentationTime.seconds - time.seconds)
        let after = abs(frames[low].presentationTime.seconds - time.seconds)
        return before <= after ? low - 1 : low
    }

    // Playback holds a sample until the next PTS. Nearest-frame selection can show a future VFR frame early.
    func presentingFrame(at time:MediaTime)->Int {
        let target=time.seconds+0.000001 // Accommodate the app's 600000-tick seek-time quantisation.
        var lower=0,upper=frames.count
        while lower<upper {
            let middle=(lower+upper)/2
            if frames[middle].presentationTime.seconds<=target { lower=middle+1 } else { upper=middle }
        }
        return max(0,lower-1)
    }
    func presentingFrame(at time:MediaTime,in range:ClipRange)->Int? {
        guard let bounds=frameBounds(in:range) else { return nil }
        return min(bounds.upperBound,max(bounds.lowerBound,presentingFrame(at:time)))
    }
    func frameBounds(in range:ClipRange) -> ClosedRange<Int>? {
        var lower=nearestFrame(to:range.start),upper=nearestFrame(to:range.end)
        if frames[lower].presentationTime.seconds < range.start.seconds-0.000001 { lower+=1 }
        if frames[upper].presentationTime.seconds >= range.end.seconds-0.000001 { upper-=1 }
        guard lower<=upper,lower<frames.count,upper>=0 else { return nil }
        return lower...upper
    }
    func frameIndex(at time:MediaTime,in range:ClipRange)->Int? {
        guard let bounds=frameBounds(in:range) else { return nil }
        return min(bounds.upperBound,max(bounds.lowerBound,nearestFrame(to:time)))
    }
    func steppedIndex(from index: Int, by offset: Int) -> Int {
        let start = min(max(index, 0), frames.count - 1)
        if offset > 0 { return start + min(offset, frames.count - 1 - start) }
        return start + max(offset, -start)
    }

    func sourcePosition(at presentation: MediaTime) -> SourcePosition? {
        let time = presentation.seconds
        guard let segment = segments.enumerated().first(where: { index, value in
            time >= value.presentationStart.seconds
                && (time < value.presentationEnd
                    || (index == segments.count - 1 && abs(time - value.presentationEnd) < 0.000_001))
        })?.element else { return nil }
        return SourcePosition(sourceID: segment.sourceID, seconds: segment.sourceTime(for: time))
    }

    func presentationTimes(sourceID: String, sourceTime: MediaTime) -> [MediaTime] {
        segments.compactMap { segment in
            let offset = sourceTime.seconds - segment.sourceStart.seconds
            guard segment.sourceID == sourceID, offset >= 0,
                  offset < segment.sourceDuration.seconds else { return nil }
            return MediaTime(seconds: segment.presentationStart.seconds
                + offset * segment.presentationDuration.seconds / segment.sourceDuration.seconds)
        }
    }
}

enum MediaFailure: LocalizedError, Equatable {
    case noVideo, invalidTiming, readFailed, unsupportedVersion, invalidGeometry
    var errorDescription: String? {
        switch self {
        case .noVideo: return "这个文件中没有可读取的视频。"
        case .invalidTiming: return "视频的帧时间信息不完整，暂时无法逐帧分析。"
        case .readFailed: return "视频读取失败，请重试或重新导入。"
        case .unsupportedVersion: return "这份数据由较新的版本生成，请更新后打开。"
        case .invalidGeometry: return "画面尺寸或裁切区域无效。"
        }
    }
}
