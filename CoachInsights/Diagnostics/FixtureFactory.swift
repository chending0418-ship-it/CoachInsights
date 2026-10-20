#if DEBUG
import AVFoundation
import UIKit

enum FixtureFactory {
    static func video(at url: URL, times: [Double], duration: Double,
                      size: CGSize = CGSize(width: 320, height: 180),
                      transform: CGAffineTransform = .identity) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
        input.transform = transform
        input.mediaTimeScale = 600_000
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? MediaFailure.readFailed }
        writer.startSession(atSourceTime: .zero)
        for (index, time) in times.enumerated() {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? MediaFailure.readFailed }
                try await Task.sleep(for: .milliseconds(2))
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw MediaFailure.readFailed }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width),
                height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            context.setFillColor(UIColor(hue: CGFloat(index % 12) / 12, saturation: 0.6, brightness: 0.6, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: CGFloat(index % 30) / 30 * (size.width - 30), y: 50, width: 25, height: 60))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: MediaTime(seconds: time).cmTime) else {
                throw writer.error ?? MediaFailure.readFailed
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: MediaTime(seconds: duration).cmTime)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? MediaFailure.readFailed }
    }
}
#endif
