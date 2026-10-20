import Foundation
import SwiftData

enum Sport: String, Codable, CaseIterable { case batting = "打击", pitching = "投球" }
struct UnitPointValue: Codable, Equatable { var x: Double; var y: Double }
struct ClipRange: Codable, Equatable { var start: MediaTime; var end: MediaTime }
struct ViewSettings: Codable, Equatable {
    var zoom: Double = 1
    var pan = UnitPointValue(x: 0, y: 0)
    var mirrored = false
    var quarterTurns = 0
    var crop = [0.0, 0.0, 1.0, 1.0]
}
struct Annotation: Codable, Equatable, Identifiable {
    var id = UUID()
    var version = 1
    var videoID: UUID
    var kind: String
    var points: [UnitPointValue]
    var color = "#722F37"
    var lineWidth: Double = 3
    var text: String?
    var range: ClipRange
}
struct Keyframe: Codable, Equatable, Identifiable {
    var id = UUID()
    var videoID: UUID
    var time: MediaTime
    var name: String
}
struct ComparisonSetup: Codable, Equatable {
    var version = 1
    var leftVideoID: UUID
    var rightVideoID: UUID
    var leftAnchor: MediaTime
    var rightAnchor: MediaTime
    var leftClip: ClipRange
    var rightClip: ClipRange
    var layout = "horizontal"
    var rate: Double = 1
    var leftView = ViewSettings()
    var rightView = ViewSettings()
}
struct PoseSettings: Codable, Equatable {
    var engine = "Apple Vision"
    var revision = 1
    var minimumConfidence: Float = 0.3
    var region = [0.0, 0.0, 1.0, 1.0]
    var visible = true
}
struct PoseJoint: Codable, Equatable {
    var name: String
    var position: UnitPointValue
    var confidence: Float
}
struct PoseResult: Codable, Equatable {
    var version = 1
    var videoID: UUID
    var contentHash: String
    var settings: PoseSettings
    var analyzedRange: ClipRange
    var frames: [PoseFrame]
    func isReusable(hash: String, settings: PoseSettings, range: ClipRange) -> Bool {
        version == 1 && contentHash == hash && self.settings == settings && analyzedRange == range
    }
}
struct PoseFrame: Codable, Equatable {
    var time: MediaTime
    var joints: [PoseJoint]
}
struct SessionSnapshot: Codable, Equatable {
    var version = 1
    var videoIDs: [UUID] = []
    var clips: [String: ClipRange] = [:]
    var views: [String: ViewSettings] = [:]
    var playheads: [String: MediaTime] = [:]
    var annotations: [Annotation] = []
    var keyframes: [Keyframe] = []
    var comparison: ComparisonSetup?
    var poseSettings = PoseSettings()
    var poseResults: [PoseResult] = []
    func validate() throws {
        guard version == 1, annotations.allSatisfy({ $0.version == 1 }),
              comparison == nil || comparison?.version == 1,
              poseResults.allSatisfy({ $0.version == 1 }) else {
            throw MediaFailure.unsupportedVersion
        }
        let ids = Set(videoIDs)
        guard ids.count == videoIDs.count,
              annotations.allSatisfy({ ids.contains($0.videoID) }),
              keyframes.allSatisfy({ ids.contains($0.videoID) }),
              poseResults.allSatisfy({ ids.contains($0.videoID) }) else {
            throw StorageFailure.invalidRecord
        }
        if let comparison {
            guard ids.contains(comparison.leftVideoID), ids.contains(comparison.rightVideoID) else {
                throw StorageFailure.invalidRecord
            }
        }
    }
}

@Model final class VideoAsset {
    @Attribute(.unique) var id: UUID
    var version: Int
    var relativePath: String
    var contentHash: String
    var originalName: String
    var createdAt: Date
    @Attribute(.externalStorage) var metadataData: Data
    init(id: UUID = UUID(), relativePath: String, contentHash: String, originalName: String,
         metadata: MediaMetadata) throws {
        self.id = id; version = 1; self.relativePath = relativePath
        self.contentHash = contentHash; self.originalName = originalName; createdAt = Date()
        metadataData = try JSONEncoder().encode(metadata)
    }
    func metadata() throws -> MediaMetadata {
        guard version == 1 else { throw MediaFailure.unsupportedVersion }
        let value = try JSONDecoder().decode(MediaMetadata.self, from: metadataData)
        try value.validateVersion()
        return value
    }
}

@Model final class AnalysisSession {
    @Attribute(.unique) var id: UUID
    var version: Int
    var name: String
    var sportValue: String
    var createdAt: Date
    var updatedAt: Date
    var handedness: String?
    var cameraAngle: String?
    @Attribute(.externalStorage) var snapshotData: Data
    init(name: String, sport: Sport, snapshot: SessionSnapshot = .init()) throws {
        id = UUID(); version = 1; self.name = name; sportValue = sport.rawValue
        let now = Date()
        createdAt = now; updatedAt = now
        snapshotData = try JSONEncoder().encode(snapshot)
    }
    var sport: Sport { Sport(rawValue: sportValue) ?? .batting }
    func snapshot() throws -> SessionSnapshot {
        guard version == 1 else { throw MediaFailure.unsupportedVersion }
        let value = try JSONDecoder().decode(SessionSnapshot.self, from: snapshotData)
        try value.validate()
        return value
    }
}

enum StorageFailure: LocalizedError, Equatable {
    case insufficientSpace, missingMedia, invalidRecord, unsafePath, contentMismatch, busy
    var errorDescription: String? {
        switch self {
        case .insufficientSpace: return "本机空间不足，请释放空间后重试。"
        case .missingMedia: return "素材文件缺失，请重新关联相同原片后重试。"
        case .invalidRecord: return "分析记录不完整，未覆盖已保存的数据。"
        case .unsafePath: return "素材路径无效。"
        case .contentMismatch: return "所选文件与原素材不同，请选择相同原片。"
        case .busy: return "素材正在写入，请稍后重试。"
        }
    }
}
