import AVFoundation
import UIKit
import Photos

struct ExportSource {
    let id:UUID
    let asset:AVAsset
    let metadata:MediaMetadata
    let settings:ViewSettings
    let annotations:[Annotation]
    let pose:PoseResult?
    let confidence:Float
    var clip:ClipRange? = nil
    func frameIndex(at time:Double)->Int {
        let value=MediaTime(seconds:time)
        return clip.flatMap { metadata.timeline.presentingFrame(at:value,in:$0) } ?? metadata.timeline.presentingFrame(at:value)
    }
    func pose(at time:Double)->PoseFrame? {
        guard let frame=pose?.frames.min(by:{abs($0.time.seconds-time)<abs($1.time.seconds-time)}),
              abs(frame.time.seconds-time)<0.001 else { return nil };return frame
    }
    func annotations(at time:Double)->[Annotation] { annotations.filter { AnalysisRenderer.visible($0,at:time,tolerance:0.00001) } }
}
struct ExportRecipe {
    let left:ExportSource
    var right:ExportSource?
    var clock:ComparisonClock?
    var horizontal=true
    var start:Double
    var end:Double
    var rate:Double
    var audio=false
    var size:CGSize {
        if right != nil { return horizontal ? CGSize(width:1920,height:1080):CGSize(width:1080,height:1920) }
        let rotated=left.settings.geometry(image:left.metadata.displaySize,viewport:CGSize(width:1920,height:1080)).rotatedSize
        let ratio=rotated.width/rotated.height
        let limit = ratio >= 1 ? CGSize(width:1920,height:1080) : CGSize(width:1080,height:1920)
        let scale = min(limit.width/rotated.width,limit.height/rotated.height)
        return CGSize(width:max(2,Double(Int(rotated.width*scale/2))*2),height:max(2,Double(Int(rotated.height*scale/2))*2))
    }
}

enum ExportFailure:LocalizedError {
    case invalidRange, encoding, unavailable, space
    var errorDescription:String? {
        switch self {
        case .invalidRange:return "导出片段或共同区间无效，请调整后重试。"
        case .encoding:return "视频编码失败，请释放本机空间后重试。"
        case .unavailable:return "没有可导出的本机素材。"
        case .space:return "本机空间不足以完成导出，请释放空间后重试。"
        }
    }
}

actor ExportService {
    func screenshot(source:ExportSource,time:Double,size:CGSize,directory:URL) async throws -> URL {
        let provider=FrameProvider(asset:source.asset,metadata:source.metadata,maximumDimension:1920,costLimit:16*1024*1024)
        let frame=try await provider.frame(at:source.frameIndex(at:time))
        try Task.checkCancellation()
        let image=AnalysisRenderer.render(image:frame.image,size:size,settings:source.settings,
                                         annotations:source.annotations(at:frame.requestedTime.seconds),pose:source.pose(at:frame.requestedTime.seconds),confidence:source.confidence)
        guard let data=image.pngData() else { throw ExportFailure.encoding }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let url=directory.appendingPathComponent("CoachInsights-\(UUID().uuidString).png")
        try data.write(to:url,options:.atomic);return url
    }
    func video(recipe:ExportRecipe,directory:URL,progress:@escaping @Sendable (Double)->Void) async throws -> URL {
        guard recipe.rate.isFinite,recipe.rate>0,recipe.end>recipe.start else { throw ExportFailure.invalidRange }
        let duration=(recipe.end-recipe.start)/recipe.rate
        let count=Int(ceil(duration*30))
        guard count>0,recipe.size.width>=2,recipe.size.height>=2 else { throw ExportFailure.invalidRange }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let free=(try directory.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey])).volumeAvailableCapacityForImportantUsage ?? 0
        guard free>Int64(duration*1_500_000)+32*1024*1024 else { throw ExportFailure.space }
        let url=directory.appendingPathComponent("CoachInsights-\(UUID().uuidString).mp4")
        var completed=false
        defer { if !completed { try? FileManager.default.removeItem(at:url) } }
        let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,
            AVVideoWidthKey:Int(recipe.size.width),AVVideoHeightKey:Int(recipe.size.height),
            AVVideoColorPropertiesKey:[AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_709_2,AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:8_000_000,AVVideoAllowFrameReorderingKey:false,AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel]])
        input.expectsMediaDataInRealTime=false
        input.mediaTimeScale=600_000
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
            kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String:Int(recipe.size.width),kCVPixelBufferHeightKey as String:Int(recipe.size.height),
            kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        guard writer.canAdd(input) else { throw ExportFailure.encoding };writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportFailure.encoding };writer.startSession(atSourceTime:.zero)
        let left=FrameProvider(asset:recipe.left.asset,metadata:recipe.left.metadata,maximumDimension:1920,costLimit:32*1024*1024)
        let right=recipe.right.map { FrameProvider(asset:$0.asset,metadata:$0.metadata,maximumDimension:1920,costLimit:32*1024*1024) }
        do {
            for index in 0..<count {
                try Task.checkCancellation()
                let time=min(recipe.end-0.000001,recipe.start+Double(index)/30*recipe.rate)
                let times=recipe.clock?.times(at:time) ?? (time,time)
                let a=try await left.frame(at:recipe.left.frameIndex(at:times.0))
                let b:ResolvedFrame?
                if let right,let source=recipe.right { b=try await right.frame(at:source.frameIndex(at:times.1)) } else { b=nil }
                var waited=0
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation();guard writer.status == .writing,waited<10_000 else { throw writer.error ?? ExportFailure.encoding }
                    try await Task.sleep(for:.milliseconds(2));waited+=2
                }
                guard let pool=adaptor.pixelBufferPool else { throw ExportFailure.encoding }
                var pixel:CVPixelBuffer?;CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixel)
                guard let pixel else { throw ExportFailure.encoding }
                try autoreleasepool {
                    CVPixelBufferLockBaseAddress(pixel,[]);defer { CVPixelBufferUnlockBaseAddress(pixel,[]) }
                    guard let context=CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:Int(recipe.size.width),height:Int(recipe.size.height),
                        bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpace(name:CGColorSpace.sRGB)!,
                        bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw ExportFailure.encoding }
                    context.translateBy(x:0,y:recipe.size.height);context.scaleBy(x:1,y:-1)
                    UIGraphicsPushContext(context);defer { UIGraphicsPopContext() }
                    let firstRect:CGRect,secondRect:CGRect
                    if recipe.right != nil {
                        if recipe.horizontal { firstRect=CGRect(x:0,y:0,width:recipe.size.width/2,height:recipe.size.height);secondRect=firstRect.offsetBy(dx:firstRect.width,dy:0) }
                        else { firstRect=CGRect(x:0,y:0,width:recipe.size.width,height:recipe.size.height/2);secondRect=firstRect.offsetBy(dx:0,dy:firstRect.height) }
                    } else { firstRect=CGRect(origin:.zero,size:recipe.size);secondRect = .zero }
                    Self.draw(source:recipe.left,frame:a,context:context,rect:firstRect)
                    if let b,let source=recipe.right { Self.draw(source:source,frame:b,context:context,rect:secondRect) }
                }
                guard adaptor.append(pixel,withPresentationTime:CMTime(value:Int64(index),timescale:30)) else { throw writer.error ?? ExportFailure.encoding }
                progress(Double(index+1)/Double(count)*0.95)
            }
            input.markAsFinished();writer.endSession(atSourceTime:CMTime(seconds:duration,preferredTimescale:600_000))
            await writer.finishWriting();try Task.checkCancellation()
            guard writer.status == .completed else { throw writer.error ?? ExportFailure.encoding }
            if recipe.audio,recipe.right == nil,abs(recipe.rate-1)<0.00001 { try await muxAudio(video:url,source:recipe.left.asset,start:recipe.start,duration:recipe.end-recipe.start) }
            try Task.checkCancellation();progress(1);completed=true;return url
        } catch { writer.cancelWriting();if Task.isCancelled { throw CancellationError() };throw error }
    }
    private static func draw(source:ExportSource,frame:ResolvedFrame,context:CGContext,rect:CGRect) {
        context.saveGState();defer { context.restoreGState() };context.translateBy(x:rect.minX,y:rect.minY);context.clip(to:CGRect(origin:.zero,size:rect.size))
        AnalysisRenderer.draw(image:frame.image,in:context,size:rect.size,settings:source.settings,
                              annotations:source.annotations(at:frame.requestedTime.seconds),pose:source.pose(at:frame.requestedTime.seconds),confidence:source.confidence)
    }
    private func muxAudio(video:URL,source:AVAsset,start:Double,duration:Double) async throws {
        guard let audio=try await source.loadTracks(withMediaType:.audio).first else { return }
        let rendered=AVURLAsset(url:video),composition=AVMutableComposition()
        guard let movie=try await rendered.loadTracks(withMediaType:.video).first,
              let v=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid),
              let a=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) else { throw ExportFailure.encoding }
        try v.insertTimeRange(CMTimeRange(start:.zero,duration:MediaTime(seconds:duration).cmTime),of:movie,at:.zero)
        try a.insertTimeRange(CMTimeRange(start:MediaTime(seconds:start).cmTime,duration:MediaTime(seconds:duration).cmTime),of:audio,at:.zero)
        guard let exporter=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetPassthrough) else { throw ExportFailure.encoding }
        let muxed=video.deletingLastPathComponent().appendingPathComponent("Audio-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at:muxed) }
        exporter.outputURL=muxed;exporter.outputFileType = .mp4
        let cancellation=ExportCancellation(exporter)
        await withTaskCancellationHandler { await exporter.export() } onCancel: { cancellation.cancel() }
        try Task.checkCancellation();guard exporter.status == .completed else { throw exporter.error ?? ExportFailure.encoding }
        _=try FileManager.default.replaceItemAt(video,withItemAt:muxed)
    }
}

@MainActor enum ExportBuilder {
    static func source(asset:VideoAsset,repository:LibraryRepository,snapshot:SessionSnapshot,settings:ViewSettings?=nil,pose:Bool=true,annotations:Bool=true) async throws -> ExportSource {
        let metadata=try asset.metadata(),url=try await repository.files.existingURL(asset.relativePath)
        let local=try await LocalMedia.asset(url:url,metadata:metadata)
        let overlaysVisible=snapshot.overlayVisibility[asset.id.uuidString] ?? true
        let configuration=snapshot.poseConfigurations[asset.id.uuidString] ?? snapshot.poseSettings
        let result=snapshot.poseResults.first { $0.videoID==asset.id && $0.contentHash==asset.contentHash && $0.settings.engine==configuration.engine
            && $0.settings.revision==configuration.revision && $0.settings.region==configuration.region && $0.settings.minimumConfidence==configuration.minimumConfidence }
        return ExportSource(id:asset.id,asset:local,metadata:metadata,settings:settings ?? snapshot.views[asset.id.uuidString] ?? ViewSettings(),
                            annotations:annotations && overlaysVisible ? snapshot.annotations.filter{$0.videoID==asset.id}:[],pose:pose && configuration.visible && overlaysVisible ? result:nil,confidence:configuration.minimumConfidence)
    }
    static func recipe(session:AnalysisSession,repository:LibraryRepository,videoID:UUID?,compare:Bool,rate:Double,pose:Bool,audio:Bool,annotations:Bool=true) async throws -> ExportRecipe {
        let snapshot=try session.snapshot(),assets=try repository.assets().filter{snapshot.videoIDs.contains($0.id)}
        if compare {
            guard let setup=snapshot.comparison,let a=assets.first(where:{$0.id==setup.leftVideoID}),let b=assets.first(where:{$0.id==setup.rightVideoID}) else { throw ExportFailure.unavailable }
            let clock=ComparisonClock(leftAnchor:setup.leftAnchor.seconds,rightAnchor:setup.rightAnchor.seconds,leftRange:setup.leftClip.start.seconds...setup.leftClip.end.seconds,rightRange:setup.rightClip.start.seconds...setup.rightClip.end.seconds)
            guard let range=clock.commonRange,range.upperBound>range.lowerBound else { throw ExportFailure.invalidRange }
            var left=try await source(asset:a,repository:repository,snapshot:snapshot,settings:setup.leftView,pose:pose,annotations:annotations)
            var right=try await source(asset:b,repository:repository,snapshot:snapshot,settings:setup.rightView,pose:pose,annotations:annotations)
            left.clip=setup.leftClip;right.clip=setup.rightClip
            return ExportRecipe(left:left,right:right,clock:clock,horizontal:setup.layout=="horizontal",start:range.lowerBound,end:range.upperBound,rate:setup.rate)
        }
        guard let asset=assets.first(where:{$0.id==videoID}) ?? assets.first else { throw ExportFailure.unavailable }
        var source=try await source(asset:asset,repository:repository,snapshot:snapshot,pose:pose,annotations:annotations)
        let clip=snapshot.clips[asset.id.uuidString] ?? ClipRange(start:source.metadata.timeline.frames[0].presentationTime,end:source.metadata.timeline.duration)
        source.clip=clip
        return ExportRecipe(left:source,start:clip.start.seconds,end:clip.end.seconds,rate:rate,audio:audio)
    }
}

// AVAssetExportSession supports cancellation from another queue; keep that exception local.
private final class ExportCancellation:@unchecked Sendable {
    let session:AVAssetExportSession
    init(_ session:AVAssetExportSession) { self.session=session }
    func cancel() { session.cancelExport() }
}
