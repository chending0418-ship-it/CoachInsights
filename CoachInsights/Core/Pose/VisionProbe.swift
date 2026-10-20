import Foundation
import CoreML
import Vision

actor VisionProbe {
    func analyze(_ image: CGImage, time: MediaTime) throws -> PoseFrame {
        let request = VNDetectHumanBodyPoseRequest()
        request.revision = VNDetectHumanBodyPoseRequestRevision1
        #if targetEnvironment(simulator)
        // Simulator inference uses CPU stages explicitly; accelerator availability differs from iOS.
        for (stage, devices) in try request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        #endif
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        // Capability probe samples the strongest observation; H will require explicit subject/region selection.
        guard let body = request.results?.max(by: { $0.confidence < $1.confidence }) else {
            return PoseFrame(time: time, joints: [])
        }
        let points = try body.recognizedPoints(.all)
        return PoseFrame(time: time, joints: points.map { name, point in
            PoseJoint(name: name.rawValue.rawValue,
                      position: UnitPointValue(x: point.x, y: 1 - point.y), confidence: point.confidence)
        }.sorted { $0.name < $1.name })
    }
}
