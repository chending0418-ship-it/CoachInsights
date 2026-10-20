import Foundation
import Vision
import ImageIO

func imageAt(_ url:URL) -> CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!
}

func flow(_ previous:CGImage,_ current:CGImage) throws -> CVPixelBuffer {
    let request=VNGenerateOpticalFlowRequest(targetedCGImage:current,options:[:])
    request.revision = VNGenerateOpticalFlowRequestRevision1
    request.computationAccuracy = .high
    request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
    let handler=VNImageRequestHandler(cgImage:previous,options:[:])
    try handler.perform([request])
    return request.results!.first!.pixelBuffer
}

func displacement(_ buffer:CVPixelBuffer,_ point:CGPoint) -> CGPoint {
    CVPixelBufferLockBaseAddress(buffer,.readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
    let width=CVPixelBufferGetWidth(buffer), height=CVPixelBufferGetHeight(buffer)
    let x=Int(point.x.rounded()), y=Int(point.y.rounded())
    if x<0 || y<0 || x>=width || y>=height { return CGPoint(x:Double.nan,y:Double.nan) }
    let stride=CVPixelBufferGetBytesPerRow(buffer)/MemoryLayout<Float>.size
    let data=CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:Float.self)
    var dx:[Float]=[],dy:[Float]=[]
    for yy in max(0,y-2)...min(height-1,y+2) {
        for xx in max(0,x-2)...min(width-1,x+2) {
            dx.append(data[yy*stride+xx*2]);dy.append(data[yy*stride+xx*2+1])
        }
    }
    dx.sort();dy.sort()
    return CGPoint(x:Double(dx[dx.count/2]),y:Double(dy[dy.count/2]))
}

@main struct FlowBenchmark {
    static func main() throws {
        setbuf(stdout,nil)
        let base=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        if CommandLine.arguments.count>3 && CommandLine.arguments[2]=="--sanity" {
            let a=imageAt(base.appendingPathComponent("sanity_a.png")),b=imageAt(base.appendingPathComponent("sanity_b.png"))
            let field=try flow(a,b)
            print("Field dimensions: \(CVPixelBufferGetWidth(field))x\(CVPixelBufferGetHeight(field))")
            var dx:[Double]=[],dy:[Double]=[]
            for y in stride(from:40,through:200,by:40) { for x in stride(from:40,through:280,by:40) {
                let d=displacement(field,CGPoint(x:x,y:y));dx.append(d.x);dy.append(d.y)
            } }
            dx.sort();dy.sort();let x=dx[dx.count/2],y=dy[dy.count/2]
            print("Synthetic translation median: dx=\(x), dy=\(y), expected (10,5)")
            guard abs(x-10)<2 && abs(y-5)<2 else { throw NSError(domain:"Flow coordinate sanity failed",code:1) }
            return
        }
        let frames=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("frames.json"))) as! [[String:Any]]
        let config=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("tracking_config.json"))) as! [String:Any]
        let seeds=config["seeds"] as! [[String:Any]]
        var points=seeds.map { s -> CGPoint in let p=s["point"] as! [Double];return CGPoint(x:p[0],y:p[1]) }
        var previous=imageAt(base.appendingPathComponent("frames").appendingPathComponent(frames[0]["file"] as! String))
        var results:[[String:Any]]=[]
        for frame in frames {
            try autoreleasepool {
                let index=frame["index"] as! Int
                let current=imageAt(base.appendingPathComponent("frames").appendingPathComponent(frame["file"] as! String))
                var ms=0.0
                if index>0 {
                    let begin=CFAbsoluteTimeGetCurrent();let field=try flow(previous,current)
                    for i in points.indices {
                        let d=displacement(field,points[i])
                        if d.x.isFinite && d.y.isFinite { points[i].x += d.x;points[i].y += d.y }
                    }
                    ms=(CFAbsoluteTimeGetCurrent()-begin)*1000
                }
                results.append(["index":index,"seconds":frame["seconds"]!,"trackMS":ms,"points":points.map { [Double($0.x),Double($0.y)] }])
                previous=current
                if index%15==0 {print("Dense flow frame \(index), \(String(format:"%.1f",ms))ms")}
            }
        }
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("vision_flow.json"))
    }
}
