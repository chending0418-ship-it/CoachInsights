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
    func matchesAnalysis(_ other:PoseSettings)->Bool {
        engine==other.engine && revision==other.revision && minimumConfidence==other.minimumConfidence && region==other.region
    }
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
        version == 1 && contentHash == hash && self.settings.matchesAnalysis(settings) && analyzedRange == range
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
    var playbackRates: [String: Double] = [:]
    var overlayVisibility:[String:Bool]=[:]
    var annotations: [Annotation] = []
    var keyframes: [Keyframe] = []
    var comparison: ComparisonSetup?
    var poseSettings = PoseSettings()
    var poseConfigurations: [String: PoseSettings] = [:]
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
        func valid(_ range:ClipRange)->Bool { range.start.seconds>=0 && range.end>range.start }
        func validView(_ view:ViewSettings)->Bool {
            view.crop.count==4 && view.crop.allSatisfy(\.isFinite) && view.crop[0]>=0 && view.crop[1]>=0
                && view.crop[2]>0 && view.crop[3]>0 && view.crop[0]+view.crop[2]<=1.00001 && view.crop[1]+view.crop[3]<=1.00001
                && view.zoom.isFinite && view.zoom>=1 && view.zoom<=8 && view.pan.x.isFinite && view.pan.y.isFinite
        }
        guard clips.values.allSatisfy(valid),views.values.allSatisfy(validView),
              playbackRates.values.allSatisfy({$0.isFinite && $0>=0.05 && $0<=1}),
              annotations.allSatisfy({ value in
                  let count=value.points.count
                  let validCount=value.kind=="text" ? count==1 : value.kind=="angle" ? count==3 : count>=2
                  return validCount && ["line","arrow","ellipse","freehand","text","angle"].contains(value.kind)
                      && value.points.allSatisfy({$0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)})
                      && value.lineWidth.isFinite && (1...20).contains(value.lineWidth) && valid(value.range)
              }) else { throw StorageFailure.invalidRecord }
        if let c=comparison {
            guard valid(c.leftClip),valid(c.rightClip),validView(c.leftView),validView(c.rightView),
                  c.rate.isFinite,c.rate>=0.05,c.rate<=1,["horizontal","vertical"].contains(c.layout) else { throw StorageFailure.invalidRecord }
        }
        func validSettings(_ settings:PoseSettings)->Bool {
            let region=settings.region
            return region.count==4 && region.allSatisfy(\.isFinite) && region[0]>=0 && region[1]>=0 && region[2]>0 && region[3]>0
                && region[0]+region[2]<=1.00001 && region[1]+region[3]<=1.00001
                && settings.minimumConfidence.isFinite && (0...1).contains(settings.minimumConfidence)
        }
        guard validSettings(poseSettings),poseConfigurations.values.allSatisfy(validSettings) else { throw StorageFailure.invalidRecord }
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

// Version 1 records created before playback preferences remain readable.
extension SessionSnapshot {
    private enum CodingKeys:String,CodingKey {
        case version,videoIDs,clips,views,playheads,playbackRates,overlayVisibility,annotations,keyframes,comparison,poseSettings,poseConfigurations,poseResults
    }
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        version=try c.decode(Int.self,forKey:.version)
        videoIDs=try c.decode([UUID].self,forKey:.videoIDs)
        clips=try c.decode([String:ClipRange].self,forKey:.clips)
        views=try c.decode([String:ViewSettings].self,forKey:.views)
        playheads=try c.decode([String:MediaTime].self,forKey:.playheads)
        playbackRates=try c.decodeIfPresent([String:Double].self,forKey:.playbackRates) ?? [:]
        overlayVisibility=try c.decodeIfPresent([String:Bool].self,forKey:.overlayVisibility) ?? [:]
        annotations=try c.decode([Annotation].self,forKey:.annotations)
        keyframes=try c.decode([Keyframe].self,forKey:.keyframes)
        comparison=try c.decodeIfPresent(ComparisonSetup.self,forKey:.comparison)
        poseSettings=try c.decode(PoseSettings.self,forKey:.poseSettings)
        poseConfigurations=try c.decodeIfPresent([String:PoseSettings].self,forKey:.poseConfigurations) ?? [:]
        poseResults=try c.decode([PoseResult].self,forKey:.poseResults)
    }
}
