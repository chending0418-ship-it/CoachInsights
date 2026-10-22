import XCTest
import UIKit
@testable import CoachInsights

@MainActor final class RenderingTests:XCTestCase {
    func testCrowdedPoseLabelsStaySeparateAndInsideVisibleImage() {
        let geometry=VideoGeometry(imageSize:CGSize(width:1920,height:1080),viewportSize:CGSize(width:320,height:240))
        let angles=["左肘","左膝","右肘","右膝","躯干"].map{PoseMetrics.Angle(name:$0,degrees:90,point:CGPoint(x:0.5,y:0.5))}
        let labels=AnalysisRenderer.poseAngleLabels(angles,geometry:geometry)
        XCTAssertEqual(labels.count,5)
        for i in labels.indices {
            XCTAssertTrue(CGRect(x:0,y:30,width:320,height:180).contains(labels[i].box))
            for j in labels.indices where j>i { XCTAssertFalse(labels[i].box.intersects(labels[j].box)) }
        }
        XCTAssertEqual(Set(labels.map{$0.text}),Set(angles.map{"\($0.name) 90°"}))
    }

    func testPoseEstimateNoticeSurvivesLetterboxAndIsAbsentWithoutVisibleJoints() throws {
        let size=CGSize(width:400,height:400)
        let image=UIGraphicsImageRenderer(size:CGSize(width:400,height:200)).image { c in
            UIColor.black.setFill();c.fill(CGRect(x:0,y:0,width:400,height:200))
        }.cgImage!
        let joint=PoseJoint(name:"leftShoulder",position:.init(x:0.5,y:0.25),confidence:0.9)
        let pose=PoseFrame(time:MediaTime(seconds:0),joints:[joint])
        func brightPixels(_ frame:PoseFrame?,confidence:Float=0.3)->Int {
            let result=AnalysisRenderer.render(image:image,size:size,settings:ViewSettings(),annotations:[],pose:frame,confidence:confidence).cgImage!
            var data=[UInt8](repeating:0,count:400*400*4)
            let context=CGContext(data:&data,width:400,height:400,bitsPerComponent:8,bytesPerRow:1600,
                                  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(result,in:CGRect(origin:.zero,size:size))
            return (320..<396).reduce(0) { sum,y in sum+(4..<396).filter { x in
                let index=(y*400+x)*4
                return data[index]>150 && data[index+1]>150 && data[index+2]>150
            }.count }
        }
        // The letterbox below y=300 has no source pixels or skeleton; only the shared notice can appear here.
        XCTAssertGreaterThan(brightPixels(pose),100)
        XCTAssertEqual(brightPixels(nil),0)
        XCTAssertEqual(brightPixels(PoseFrame(time:MediaTime(seconds:0),joints:[])),0)
        XCTAssertEqual(brightPixels(pose,confidence:0.95),0)
    }
    func testAllVectorToolsAndPoseShareRotatedExportGeometry() throws {
        let image=UIGraphicsImageRenderer(size:CGSize(width:400,height:200)).image { c in
            UIColor.darkGray.setFill();c.fill(CGRect(x:0,y:0,width:400,height:200))
        }.cgImage!
        let videoID=UUID(),range=ClipRange(start:MediaTime(seconds:0),end:MediaTime(seconds:1))
        let kinds=["line","arrow","ellipse","freehand","text","angle"]
        for (i,kind) in kinds.enumerated() {
            let points:[UnitPointValue]=kind=="text" ? [.init(x:0.25,y:0.4)] : kind=="angle" ? [.init(x:0.2,y:0.3),.init(x:0.5,y:0.5),.init(x:0.8,y:0.3)] : [.init(x:0.2,y:0.3),.init(x:0.8,y:0.7)]
            let annotation=Annotation(videoID:videoID,kind:kind,points:points,color:"#FFFFFF",lineWidth:4,text:"发现 \(i)",range:range)
            let rendered=AnalysisRenderer.render(image:image,size:CGSize(width:400,height:200),settings:ViewSettings(),annotations:[annotation])
            XCTAssertNotNil(rendered.pngData());XCTAssertNotEqual(rendered.pngData(),UIImage(cgImage:image).pngData())
        }
        let line=Annotation(videoID:videoID,kind:"line",points:[.init(x:0.2,y:0.4),.init(x:0.8,y:0.4)],color:"#FFFFFF",lineWidth:4,range:range)
        for turn in 0..<4 {
            var settings=ViewSettings();settings.quarterTurns=turn;settings.mirrored=true;settings.zoom=1.3;settings.pan = .init(x:0.02,y:-0.04)
            let size=CGSize(width:500,height:500),geometry=settings.geometry(image:CGSize(width:400,height:200),viewport:size)
            let output=AnalysisRenderer.render(image:image,size:size,settings:settings,annotations:[line]).cgImage!
            let point=geometry.viewPoint(from:CGPoint(x:0.5,y:0.4))
            let pixel=WorkflowTests.pixel(output,x:Int(point.x),y:Int(point.y))
            XCTAssertGreaterThan(pixel.0,220);XCTAssertGreaterThan(pixel.1,220);XCTAssertGreaterThan(pixel.2,220)
        }
        let joints=[PoseJoint(name:"leftShoulder",position:.init(x:0.2,y:0.2),confidence:1),PoseJoint(name:"leftElbow",position:.init(x:0.5,y:0.2),confidence:1),PoseJoint(name:"leftWrist",position:.init(x:0.5,y:0.8),confidence:1)]
        let pose=PoseFrame(time:MediaTime(seconds:0),joints:joints)
        let output=AnalysisRenderer.render(image:image,size:CGSize(width:400,height:200),settings:ViewSettings(),annotations:[],pose:pose).cgImage!
        let cyan=WorkflowTests.pixel(output,x:140,y:40);XCTAssertGreaterThan(cyan.1,100);XCTAssertGreaterThan(cyan.2,100)
        let angles=PoseMetrics.angles(joints:Dictionary(uniqueKeysWithValues:joints.map{($0.name,$0.position.cgPoint)}),size:CGSize(width:400,height:200))
        XCTAssertEqual(try XCTUnwrap(angles.first).degrees,90,accuracy:0.001)
    }
    func testCameraOrientationAndTrunkReferenceFollowDisplayedRotation() throws {
        XCTAssertEqual(CameraOrientation.angle(device:.landscapeLeft,interface:.portrait),0)
        XCTAssertEqual(CameraOrientation.angle(device:.landscapeRight,interface:.portrait),180)
        XCTAssertEqual(CameraOrientation.angle(device:.portraitUpsideDown,interface:.portrait),270)
        XCTAssertEqual(CameraOrientation.angle(device:.faceUp,interface:.landscapeRight),0)
        XCTAssertEqual(CameraOrientation.angle(device:.unknown,interface:.landscapeLeft),180)
        let points:[String:CGPoint]=["leftShoulder":CGPoint(x:0.3,y:0.2),"rightShoulder":CGPoint(x:0.7,y:0.2),"leftHip":CGPoint(x:0.4,y:0.8),"rightHip":CGPoint(x:0.6,y:0.8)]
        let size=CGSize(width:400,height:200)
        let upright=try XCTUnwrap(PoseMetrics.angles(joints:points,size:size).first(where:{$0.name=="躯干"}))
        let rotated=try XCTUnwrap(PoseMetrics.angles(joints:points,size:size,quarterTurns:1).first(where:{$0.name=="躯干"}))
        XCTAssertEqual(upright.degrees,0,accuracy:0.001);XCTAssertEqual(rotated.degrees,90,accuracy:0.001)
    }

}
