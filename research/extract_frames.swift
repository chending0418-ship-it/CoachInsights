import Foundation
import AVFoundation
import CoreImage
import AppKit

@main struct ExtractFrames {
    static func main() async throws {
        let asset = AVURLAsset(url:URL(fileURLWithPath:CommandLine.arguments[1]))
        let out=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let track=try await asset.loadTracks(withMediaType:.video).first!
        let transform=try await track.load(.preferredTransform)
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData=false; reader.add(output); reader.startReading()
        let context=CIContext(options:[.cacheIntermediates:false])
        var frames:[[String:Any]]=[]
        while let sample=output.copyNextSampleBuffer() {
            try autoreleasepool {
                let pixel=CMSampleBufferGetImageBuffer(sample)!
                var image=CIImage(cvPixelBuffer:pixel).transformed(by:transform)
                image=image.transformed(by:CGAffineTransform(translationX:-image.extent.minX,y:-image.extent.minY))
                let scale=1280.0/max(image.extent.width,image.extent.height)
                image=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
                let cg=context.createCGImage(image,from:image.extent)!
                let name=String(format:"%04d.jpg",frames.count)
                let bitmap=NSBitmapImageRep(cgImage:cg)
                try bitmap.representation(using:.jpeg,properties:[.compressionFactor:0.97])!.write(to:out.appendingPathComponent(name))
                let time=CMSampleBufferGetPresentationTimeStamp(sample)
                frames.append(["index":frames.count,"file":name,"seconds":time.seconds,"ptsValue":time.value,"ptsTimescale":time.timescale,"width":cg.width,"height":cg.height])
            }
        }
        guard reader.status == .completed else { throw reader.error ?? NSError(domain:"Reader",code:1) }
        try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.deletingLastPathComponent().appendingPathComponent("frames.json"))
        print("Extracted \(frames.count) frames")
    }
}
