import XCTest
import UIKit
@testable import CoachInsights

final class PoseQualityTests:XCTestCase {
    struct Reference:Decodable { let samples:[Sample] }
    struct Sample:Decodable {
        let clip:String,sport:String,file:String
        let index:Int,width:Int,height:Int
        let region:[Double]
        let bodyHeight:Double
        let points:[Point]
    }
    struct Point:Codable { let name:String;let x:Double,y:Double;let visible:Bool }
    struct Measurement:Codable {
        let clip:String,sport:String,index:Int
        let visible:Int,detected:Int,correct:Int,wristVisible:Int,wristDetected:Int,wristCorrect:Int,elbowVisible:Int,elbowDetected:Int,elbowCorrect:Int
        let leftRightSuspicions:Int,highConfidenceErrors:Int,ambiguous:Bool
        let predicted:[PoseJoint]
    }
    func testOptionalHeldOutBaseballJointAccuracyReport() async throws {
        try await measure(modelPath:nil,outputName:"pose-quality-measurements")
    }
    func testOptionalHeavyModelComparisonReport() async throws {
        guard let path=Bundle(for:Self.self).path(forResource:"pose_landmarker_heavy",ofType:"task") else { throw XCTSkip("Optional research comparison; Heavy is not bundled in the App") }
        try await measure(modelPath:path,outputName:"pose-quality-heavy-measurements")
    }
    private func measure(modelPath:String?,outputName:String) async throws {
        let bundle=Bundle(for:Self.self)
        guard let url=bundle.url(forResource:"pose-quality-reference",withExtension:"json") else {
            throw XCTSkip("Run scripts/prepare_pose_quality.py for the optional public, human-labelled acceptance set")
        }
        let reference=try JSONDecoder().decode(Reference.self,from:Data(contentsOf:url))
        let engine=MediaPipePoseEngine(modelPath:modelPath);var measurements:[Measurement]=[]
        for sample in reference.samples {
            let imageURL=try XCTUnwrap(bundle.url(forResource:sample.file,withExtension:"png"))
            let image=try XCTUnwrap(UIImage(contentsOfFile:imageURL.path)?.cgImage)
            XCTAssertEqual(image.width,sample.width);XCTAssertEqual(image.height,sample.height)
            var settings=PoseSettings();settings.engine=MediaPipePoseEngine.identity;settings.region=sample.region
            let bodies=try await PoseAnalysis.candidates(image:image,engine:engine,settings:settings)
            let joints=bodies.count==1 ? bodies[0]:[]
            let mapped=Dictionary(uniqueKeysWithValues:joints.map { ($0.name,($0.position.x*Double(image.width),$0.position.y*Double(image.height),$0.confidence)) })
            var detected=0,correct=0,wv=0,wd=0,wc=0,ev=0,ed=0,ec=0,lr=0,hc=0
            let visible=sample.points.filter(\.visible)
            for p in visible {
                let wrist=p.name.contains("Wrist"),elbow=p.name.contains("Elbow")
                if wrist { wv+=1 };if elbow { ev+=1 }
                guard let joint=mapped[p.name] else { continue }
                detected+=1;if wrist { wd+=1 };if elbow { ed+=1 }
                let error=hypot(joint.0-p.x,joint.1-p.y)/sample.bodyHeight
                if error<=0.05 { correct+=1;if wrist { wc+=1 };if elbow { ec+=1 } }
                else {
                    if joint.2>=0.8 { hc+=1 }
                    let opposite=p.name.hasPrefix("left") ? p.name.replacingOccurrences(of:"left",with:"right"):p.name.replacingOccurrences(of:"right",with:"left")
                    if let other=visible.first(where:{$0.name==opposite}),hypot(joint.0-other.x,joint.1-other.y)<hypot(joint.0-p.x,joint.1-p.y) { lr+=1 }
                }
            }
            measurements.append(Measurement(clip:sample.clip,sport:sample.sport,index:sample.index,visible:visible.count,detected:detected,correct:correct,
                wristVisible:wv,wristDetected:wd,wristCorrect:wc,elbowVisible:ev,elbowDetected:ed,elbowCorrect:ec,leftRightSuspicions:lr,highConfidenceErrors:hc,ambiguous:bodies.count>1,
                predicted:joints))
        }
        XCTAssertEqual(measurements.filter{$0.sport=="baseball_pitch"}.count,30)
        XCTAssertEqual(measurements.filter{$0.sport=="baseball_swing"}.count,30)
        XCTAssertGreaterThan(measurements.map(\.detected).reduce(0,+),0)
        try JSONEncoder().encode(measurements).write(to:URL.documentsDirectory.appendingPathComponent(outputName+".json"))
        // Accuracy remains a reported reference; 1.0 presents pose as an auxiliary estimate.
    }
}
