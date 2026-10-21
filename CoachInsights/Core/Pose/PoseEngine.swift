import Vision
import CoreML
import UIKit
import MediaPipeTasksVision

protocol PoseEngine: Actor {
    func bodies(in image: CGImage) async throws -> [[PoseJoint]]
}

actor ApplePoseEngine: PoseEngine {
    func bodies(in image: CGImage) throws -> [[PoseJoint]] {
        let request = VNDetectHumanBodyPoseRequest(); request.revision = VNDetectHumanBodyPoseRequestRevision1
        #if targetEnvironment(simulator)
        for (stage,devices) in try request.supportedComputeStageDevices {
            if let cpu=devices.first(where:{if case .cpu = $0 { return true };return false}) { request.setComputeDevice(cpu,for:stage) }
        }
        #endif
        try VNImageRequestHandler(cgImage:image,orientation:.up).perform([request])
        let names: [(VNHumanBodyPoseObservation.JointName,String)] = [(.leftShoulder,"leftShoulder"),(.rightShoulder,"rightShoulder"),
            (.leftElbow,"leftElbow"),(.rightElbow,"rightElbow"),(.leftWrist,"leftWrist"),(.rightWrist,"rightWrist"),
            (.leftHip,"leftHip"),(.rightHip,"rightHip"),(.leftKnee,"leftKnee"),(.rightKnee,"rightKnee"),
            (.leftAnkle,"leftAnkle"),(.rightAnkle,"rightAnkle"),(.nose,"nose")]
        return try (request.results ?? []).map { body in
            let points=try body.recognizedPoints(.all)
            return names.compactMap { key,name in
                guard let point=points[key] else { return nil }
                return PoseJoint(name:name,position:UnitPointValue(x:point.x,y:1-point.y),confidence:point.confidence)
            }
        }
    }
}

actor MediaPipePoseEngine: PoseEngine {
    static let identity = "MediaPipe Full v1 · Tasks 1.1.1"
    private var landmarker: PoseLandmarker?
    private let modelPath:String?
    init(modelPath:String?=nil) { self.modelPath=modelPath }
    func bodies(in image: CGImage) throws -> [[PoseJoint]] {
        if landmarker == nil {
            guard let path=modelPath ?? Bundle.main.path(forResource:"pose_landmarker_full",ofType:"task") else { throw PoseFailure.modelMissing }
            let options=PoseLandmarkerOptions(); options.baseOptions.modelAssetPath=path
            options.runningMode = .image; options.numPoses=2
            options.minPoseDetectionConfidence=0.5; options.minPosePresenceConfidence=0.5
            landmarker=try PoseLandmarker(options:options)
        }
        let input=try MPImage(uiImage:UIImage(cgImage:image))
        guard let result=try landmarker?.detect(image:input) else { return [] }
        let indices:[(Int,String)] = [(0,"nose"),(11,"leftShoulder"),(12,"rightShoulder"),(13,"leftElbow"),(14,"rightElbow"),
                                     (15,"leftWrist"),(16,"rightWrist"),(23,"leftHip"),(24,"rightHip"),(25,"leftKnee"),(26,"rightKnee"),(27,"leftAnkle"),(28,"rightAnkle")]
        return result.landmarks.map { body in
            indices.compactMap { index,name in
                guard index<body.count else { return nil }; let point=body[index]
                let confidence=min(point.visibility?.floatValue ?? 0, point.presence?.floatValue ?? 0)
                guard point.x >= 0,point.x <= 1,point.y >= 0,point.y <= 1 else { return nil }
                return PoseJoint(name:name,position:UnitPointValue(x:Double(point.x),y:Double(point.y)),confidence:confidence)
            }
        }
    }
}

enum PoseFailure: LocalizedError {
    case modelMissing, invalidRegion
    var errorDescription:String? {
        switch self { case .modelMissing:return "本机姿态模型缺失，请重新构建应用后重试。"
        case .invalidRegion:return "分析区域无效，请重新选定包含完整人体的区域。" }
    }
}

enum PoseAnalysis {
    static func candidates(image:CGImage,engine:any PoseEngine,settings:PoseSettings) async throws -> [[PoseJoint]] {
        let r=settings.region
        guard r.count==4,r.allSatisfy(\.isFinite),r[2]>0,r[3]>0 else { throw PoseFailure.invalidRegion }
        let subject=CGRect(x:r[0]*Double(image.width),y:r[1]*Double(image.height),width:r[2]*Double(image.width),height:r[3]*Double(image.height))
        // Give the detector body context while keeping subject selection inside the user's region.
        let context=subject.insetBy(dx:-subject.width*0.2,dy:-subject.height*0.2).integral
            .intersection(CGRect(x:0,y:0,width:image.width,height:image.height))
        guard let cropped=image.cropping(to:context) else { throw PoseFailure.invalidRegion }
        let bodies=try await engine.bodies(in:cropped)
        var candidates:[[PoseJoint]]=[]
        for raw in bodies {
            var mapped:[PoseJoint]=[]
            for joint in raw where joint.confidence>=settings.minimumConfidence {
                var value=joint
                value.position.x=(Double(context.minX)+joint.position.x*Double(context.width))/Double(image.width)
                value.position.y=(Double(context.minY)+joint.position.y*Double(context.height))/Double(image.height)
                mapped.append(value)
            }
            let centers=mapped.filter{["leftHip","rightHip","leftShoulder","rightShoulder"].contains($0.name)}
            guard mapped.count>=4,centers.count>=2 else { continue }
            let sumX=centers.map(\.position.x).reduce(0.0,+),sumY=centers.map(\.position.y).reduce(0.0,+)
            let x=sumX/Double(centers.count)*Double(image.width),y=sumY/Double(centers.count)*Double(image.height)
            if subject.contains(CGPoint(x:x,y:y)) { candidates.append(mapped) }
        }
        return candidates
    }
    static func analyze(provider:FrameProvider,metadata:MediaMetadata,videoID:UUID,hash:String,settings:PoseSettings,
                        range:ClipRange, progress:@escaping @Sendable (Double)->Void) async throws -> PoseResult {
        let region=settings.region
        guard region.count==4,region.allSatisfy(\.isFinite),region[0]>=0,region[1]>=0,region[2]>0,region[3]>0,
              region[0]+region[2]<=1.00001,region[1]+region[3]<=1.00001 else { throw PoseFailure.invalidRegion }
        let engine:any PoseEngine = settings.engine == "Apple Vision" ? ApplePoseEngine() : MediaPipePoseEngine()
        let indices=metadata.timeline.frames.indices.filter { metadata.timeline.frames[$0].presentationTime >= range.start && metadata.timeline.frames[$0].presentationTime < range.end }
        var frames:[PoseFrame]=[]
        var previous:CGPoint?
        for (position,index) in indices.enumerated() {
            try Task.checkCancellation()
            let decoded=try await provider.frame(at:index)
            let bodies=try await candidates(image:decoded.image,engine:engine,settings:settings)
            var joints:[PoseJoint]=[]
            // Multiple subjects or a large subject jump are intentionally left unmeasured.
            if bodies.count==1 {
                let body=bodies[0].filter { $0.confidence>=settings.minimumConfidence }
                let centers=body.filter { ["leftHip","rightHip","leftShoulder","rightShoulder"].contains($0.name) }
                if centers.count>=2 {
                    let center=CGPoint(x:centers.map(\.position.x).reduce(0,+)/Double(centers.count),y:centers.map(\.position.y).reduce(0,+)/Double(centers.count))
                    if previous == nil || hypot((center.x-previous!.x)/region[2],(center.y-previous!.y)/region[3])<0.25 {
                        joints=body
                        previous=center
                    }
                }
            }
            frames.append(PoseFrame(time:decoded.requestedTime,joints:joints))
            progress(Double(position+1)/Double(max(1,indices.count)))
        }
        return PoseResult(videoID:videoID,contentHash:hash,settings:settings,analyzedRange:range,frames:frames)
    }
}

extension AnalysisWorkspace {
    func analyzePose(force:Bool=false) {
        guard !poseBusy,let provider,let metadata,let asset=selectedAsset else { return }
        pause(); save()
        let settings=poseSettings, range=clip
        if !force, snapshot.poseResults.contains(where: { $0.videoID==asset.id && $0.isReusable(hash:asset.contentHash,settings:settings,range:range) }) {
            notice="已复用本机姿态结果。"; return
        }
        poseBusy=true; poseProgress=0
        poseTask=Task { [weak self] in
            guard let self else { return }; defer { poseBusy=false }
            do {
                var actual=settings
                #if targetEnvironment(simulator)
                // The supported simulator runtime lacks Vision's weights and may stall during setup.
                if actual.engine == "Apple Vision" {
                    actual.engine=MediaPipePoseEngine.identity
                    notice="模拟器使用已打包的本机 MediaPipe Full 模型。"
                }
                #endif
                var result:PoseResult
                do {
                    result=try await PoseAnalysis.analyze(provider:provider,metadata:metadata,videoID:asset.id,hash:asset.contentHash,settings:actual,range:range) { [weak self] p in Task { @MainActor in self?.poseProgress=p } }
                } catch {
                    guard actual.engine == "Apple Vision",!(error is CancellationError) else { throw error }
                    actual.engine=MediaPipePoseEngine.identity
                    notice="当前系统的 Vision 不可用，已切换至本机 MediaPipe Full。"
                    result=try await PoseAnalysis.analyze(provider:provider,metadata:metadata,videoID:asset.id,hash:asset.contentHash,settings:actual,range:range) { [weak self] p in Task { @MainActor in self?.poseProgress=p } }
                }
                try Task.checkCancellation()
                guard selectedVideoID==asset.id,poseSettings.matchesAnalysis(settings) else { return }
                actual.visible=poseSettings.visible
                poseSettings=actual; snapshot.poseResults.removeAll { $0.videoID==asset.id }; snapshot.poseResults.append(result); save()
                let usable=result.frames.filter { !$0.joints.isEmpty }.count
                notice="分析完成（辅助估算）：\(usable) / \(result.frames.count) 帧有可用关节。请人工复核点位；空缺帧请调整区域或检查遮挡。"; issue=nil
            } catch is CancellationError { notice="已取消姿态分析，原有结果保留。" }
            catch { issue=error.localizedDescription }
        }
    }
}
