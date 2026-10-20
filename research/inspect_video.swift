import Foundation
import AVFoundation
import AppKit

@main struct InspectVideo {
    static func main() async throws {
        let input = CommandLine.arguments[1]
        let out = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: URL(fileURLWithPath: input))
        let duration = try await asset.load(.duration)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = try await track.load(.nominalFrameRate)
        let minDuration = try await track.load(.minFrameDuration)
        let meta: [String: Any] = ["duration":duration.seconds, "width":size.width, "height":size.height,
            "nominalFPS":fps, "minFrameDuration":minDuration.seconds,
            "preferredTransform":[transform.a,transform.b,transform.c,transform.d,transform.tx,transform.ty]]
        let data = try JSONSerialization.data(withJSONObject:meta,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:out.appendingPathComponent("metadata.json"))
        print(String(data:data,encoding:.utf8)!)
        let generator = AVAssetImageGenerator(asset:asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width:1280,height:1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for i in 0..<13 {
            let seconds = min(Double(i) * 0.2, duration.seconds - 0.02)
            let (cg, actual) = try await generator.image(at:CMTime(seconds:seconds,preferredTimescale:60000))
            let bitmap = NSBitmapImageRep(cgImage:cg)
            try bitmap.representation(using:.jpeg,properties:[.compressionFactor:0.9])!.write(to:out.appendingPathComponent(String(format:"sample_%02d_%.3f.jpg",i,actual.seconds)))
        }
    }
}
