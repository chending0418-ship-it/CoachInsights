import Foundation
import Vision
import ImageIO

@main struct VisionBenchmark {
    static func main() throws {
        let base=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let frameData=try Data(contentsOf:base.appendingPathComponent("frames.json"))
        let frames=try JSONSerialization.jsonObject(with:frameData) as! [[String:Any]]
        var result:[[String:Any]]=[]
        let configURL=base.appendingPathComponent("tracking_config.json")
        let config=FileManager.default.fileExists(atPath:configURL.path) ? try JSONSerialization.jsonObject(with:Data(contentsOf:configURL)) as? [String:Any] : nil
        let seeds=config?["seeds"] as? [[String:Any]] ?? []
        let requests=seeds.map { seed -> VNTrackObjectRequest in
            let rect=seed["rect"] as! [Double]
            let request=VNTrackObjectRequest(detectedObjectObservation:VNDetectedObjectObservation(boundingBox:CGRect(x:rect[0],y:1-rect[1]-rect[3],width:rect[2],height:rect[3])))
            request.trackingLevel = .accurate
            return request
        }
        let sequence=VNSequenceRequestHandler()
        let start=config?["startFrame"] as? Int ?? 0
        for frame in frames {
            try autoreleasepool {
                let index=frame["index"] as! Int
                let url=base.appendingPathComponent("frames").appendingPathComponent(frame["file"] as! String)
                let source=CGImageSourceCreateWithURL(url as CFURL,nil)!
                let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
                let handler=VNImageRequestHandler(cgImage:image,options:[:])
                let pose=VNDetectHumanBodyPoseRequest()
                let begin=CFAbsoluteTimeGetCurrent()
                try handler.perform([pose])
                let poseMS=(CFAbsoluteTimeGetCurrent()-begin)*1000
                var people:[Any]=[]
                for observation in pose.results ?? [] {
                    let points=try observation.recognizedPoints(.all)
                    people.append(Dictionary(uniqueKeysWithValues:points.map { key,value in
                        (key.rawValue.rawValue,["x":value.location.x,"y":1-value.location.y,"confidence":Double(value.confidence)])
                    }))
                }
                var tracks:[[String:Any]]=[]
                var trackMS=0.0
                if index >= start && !requests.isEmpty {
                    let beginTrack=CFAbsoluteTimeGetCurrent()
                    try sequence.perform(requests,on:image)
                    trackMS=(CFAbsoluteTimeGetCurrent()-beginTrack)*1000
                    for (i,request) in requests.enumerated() {
                        if let observation=request.results?.first as? VNDetectedObjectObservation {
                            let box=observation.boundingBox
                            tracks.append(["name":seeds[i]["name"] as! String,"rect":[box.minX,1-box.maxY,box.width,box.height],"confidence":Double(observation.confidence)])
                            request.inputObservation=observation
                        }
                    }
                }
                result.append(["index":index,"seconds":frame["seconds"]!,"poseMS":poseMS,"people":people,"tracks":tracks,"trackMS":trackMS])
                if index % 15 == 0 { print("Vision frame \(index)/\(frames.count), pose \(String(format:"%.1f",poseMS))ms") }
            }
        }
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("vision.json"))
    }
}
