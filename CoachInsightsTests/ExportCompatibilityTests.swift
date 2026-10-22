import XCTest
import AVFoundation
import VideoToolbox
@testable import CoachInsights

@MainActor final class ExportCompatibilityTests:XCTestCase {
    func testOriginalAudioAtOneSpeedAndSilentSlowMotion() async throws {
        let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let silent=root.appendingPathComponent("silent.mov")
        try await FixtureFactory.video(at:silent,times:(0..<30).map{Double($0)/30},duration:1)
        let tone=root.appendingPathComponent("tone.caf")
        let audioFile=try AVAudioFile(forWriting:tone,settings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:44100,AVNumberOfChannelsKey:1,
            AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false],commonFormat:.pcmFormatFloat32,interleaved:false)
        let buffer=try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:audioFile.processingFormat,frameCapacity:44100));buffer.frameLength=44100
        for i in 0..<44100 { buffer.floatChannelData![0][i]=Float(sin(Double(i)*2*Double.pi*440/44100)*0.2) };try audioFile.write(from:buffer)
        let composition=AVMutableComposition(),movieAsset=AVURLAsset(url:silent),audioAsset=AVURLAsset(url:tone)
        let movieTracks=try await movieAsset.loadTracks(withMediaType:.video),soundTracks=try await audioAsset.loadTracks(withMediaType:.audio)
        let movie=try XCTUnwrap(movieTracks.first),sound=try XCTUnwrap(soundTracks.first)
        let v=try XCTUnwrap(composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid))
        let a=try XCTUnwrap(composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid))
        let range=CMTimeRange(start:.zero,duration:MediaTime(seconds:1).cmTime)
        try v.insertTimeRange(range,of:movie,at:.zero);try a.insertTimeRange(range,of:sound,at:.zero)
        let source=root.appendingPathComponent("source.mov"),exporter=try XCTUnwrap(AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality))
        exporter.outputURL=source;exporter.outputFileType = .mov;await exporter.export();XCTAssertEqual(exporter.status,.completed,exporter.error?.localizedDescription ?? "")
        let repo=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repo.create(name:"声音规则",sport:.pitching)
        let asset=try await repo.importVideo(source,into:session)
        var snapshot=try session.snapshot();snapshot.clips[asset.id.uuidString]=ClipRange(start:MediaTime(seconds:0.2),end:MediaTime(seconds:0.7));try repo.save(session,snapshot:snapshot)
        let recipe=try await ExportBuilder.recipe(session:session,repository:repo,videoID:asset.id,compare:false,rate:1,pose:false,audio:true)
        let result=try await ExportService().video(recipe:recipe,directory:root.appendingPathComponent("Exports")){_ in}
        let output=AVURLAsset(url:result),outputAudio=try await output.loadTracks(withMediaType:.audio),duration=try await output.load(.duration)
        XCTAssertEqual(outputAudio.count,1);XCTAssertEqual(duration.seconds,0.5,accuracy:0.04)
        let slow=try await ExportBuilder.recipe(session:session,repository:repo,videoID:asset.id,compare:false,rate:0.5,pose:false,audio:true)
        let slowURL=try await ExportService().video(recipe:slow,directory:root.appendingPathComponent("Exports")){_ in}
        let slowAudio=try await AVURLAsset(url:slowURL).loadTracks(withMediaType:.audio);XCTAssertTrue(slowAudio.isEmpty)
    }
    func testHDRHLGSourceExportsEightBitRec709SDR() async throws {
        let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("hlg.mov")
        let writer=try AVAssetWriter(outputURL:source,fileType:.mov)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.hevc,AVVideoWidthKey:320,AVVideoHeightKey:180,
            AVVideoCompressionPropertiesKey:[AVVideoProfileLevelKey:kVTProfileLevel_HEVC_Main10_AutoLevel,AVVideoAllowFrameReorderingKey:false],
            AVVideoColorPropertiesKey:[AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_2020,AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_2100_HLG,AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_2020]])
        input.mediaTimeScale=600_000
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String:320,kCVPixelBufferHeightKey as String:180,kCVPixelBufferIOSurfacePropertiesKey as String:[:]])
        writer.add(input);XCTAssertTrue(writer.startWriting());writer.startSession(atSourceTime:.zero)
        for frame in 0..<6 {
            while !input.isReadyForMoreMediaData { if writer.status == .failed { throw writer.error! };try await Task.sleep(for:.milliseconds(2)) }
            var optional:CVPixelBuffer?;let pool=try XCTUnwrap(adaptor.pixelBufferPool)
            CVPixelBufferPoolCreatePixelBuffer(nil,pool,&optional);let pixel=try XCTUnwrap(optional)
            CVPixelBufferLockBaseAddress(pixel,[])
            for plane in 0..<2 {
                let base=CVPixelBufferGetBaseAddressOfPlane(pixel,plane)!.assumingMemoryBound(to:UInt16.self)
                let stride=CVPixelBufferGetBytesPerRowOfPlane(pixel,plane)/2
                for y in 0..<CVPixelBufferGetHeightOfPlane(pixel,plane) {
                    for x in 0..<stride { base[y*stride+x]=UInt16(plane==1 ? 512 : x<160 ? 128:800)<<6 }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixel,[])
            XCTAssertTrue(adaptor.append(pixel,withPresentationTime:CMTime(value:Int64(frame),timescale:30)))
        }
        input.markAsFinished();writer.endSession(atSourceTime:MediaTime(seconds:0.2).cmTime);await writer.finishWriting()
        XCTAssertEqual(writer.status,.completed,writer.error?.localizedDescription ?? "")
        let asset=AVURLAsset(url:source),tracks=try await asset.loadTracks(withMediaType:.video),formats=try await tracks[0].load(.formatDescriptions)
        let extensions=try XCTUnwrap(CMFormatDescriptionGetExtensions(formats[0])) as NSDictionary
        XCTAssertEqual(extensions[kCMFormatDescriptionExtension_TransferFunction] as? String,kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
        let repo=try LibraryRepository(root:root.appendingPathComponent("Library")),session=try repo.create(name:"HDR",sport:.batting),video=try await repo.importVideo(source,into:session)
        let recipe=try await ExportBuilder.recipe(session:session,repository:repo,videoID:video.id,compare:false,rate:1,pose:false,audio:false)
        let result=try await ExportService().video(recipe:recipe,directory:root.appendingPathComponent("Exports")){_ in}
        let output=AVURLAsset(url:result),outputTracks=try await output.loadTracks(withMediaType:.video),outputFormats=try await outputTracks[0].load(.formatDescriptions)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(outputFormats[0]),kCMVideoCodecType_H264)
        let color=try XCTUnwrap(CMFormatDescriptionGetExtensions(outputFormats[0])) as NSDictionary
        XCTAssertEqual(color[kCMFormatDescriptionExtension_TransferFunction] as? String,kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        let metadata=try await MediaInspector().inspect(url:result),frame=try await FrameProvider(asset:output,metadata:metadata,maximumDimension:320).frame(at:0)
        let dark=WorkflowTests.pixel(frame.image,x:80,y:90),bright=WorkflowTests.pixel(frame.image,x:240,y:90)
        XCTAssertGreaterThan(bright.0,dark.0+60,"HDR conversion should retain visible contrast in SDR")
    }
}
