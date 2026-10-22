@testable import CoachInsights
import AVFoundation
import UIKit
import XCTest
import SwiftData

enum BenchmarkFixture {
    @MainActor static func cleanAfterHostWork(_ test:XCTestCase,root:URL,repository:LibraryRepository) {
        test.addTeardownBlock { @MainActor [weak context=repository.context,weak container=repository.container] in
            // Never unlink a live SwiftData store. Wait for cancelled work and the
            // detached SwiftUI view graph to release their owners after the test body.
            for _ in 0..<200 {
                if context == nil && container == nil { break }
                try await Task.sleep(for:.milliseconds(20))
            }
            guard context == nil && container == nil else { XCTFail("Temporary model store remained live after shutdown");return }
            if FileManager.default.fileExists(atPath:root.path) { try FileManager.default.removeItem(at:root) }
        }
    }
    static var poseJoints:[PoseJoint] {
        [("leftShoulder",0.4,0.25),("rightShoulder",0.6,0.25),("leftElbow",0.35,0.4),("rightElbow",0.65,0.4),("leftWrist",0.3,0.55),("rightWrist",0.7,0.55),("leftHip",0.43,0.5),("rightHip",0.57,0.5),("leftKnee",0.45,0.7),("rightKnee",0.55,0.7),("leftAnkle",0.4,0.9),("rightAnkle",0.6,0.9)].map{PoseJoint(name:$0.0,position:.init(x:$0.1,y:$0.2),confidence:0.9)}
    }
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
