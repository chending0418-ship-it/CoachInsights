import AVFoundation
import Photos

struct PhotoVideoSource {
    struct Selection {
        let analysisAsset: AVAsset
        let sourceAsset: AVAsset
        let preservesPhotoTiming: Bool
        let notice: String?
    }
    // Requires the caller's Photos authorization. This adapter does not export/re-encode frames.
    func load(_ photo: PHAsset) async throws -> Selection {
        let original = try await request(photo, version: .original)
        let current = try await request(photo, version: .current)
        return try await select(original: original, current: current)
    }
    func select(original: AVAsset, current: AVAsset) async throws -> Selection {
        let source = try await MediaInspector().inspect(asset: original)
        let displayed = try? await MediaInspector().inspect(asset: current)
        // Only adopt the adjusted timeline when it still exposes every original analysis frame.
        if let displayed, displayed.timeline.frames.count == source.timeline.frames.count,
           current is AVComposition {
            return Selection(analysisAsset: current, sourceAsset: original, preservesPhotoTiming: true, notice: nil)
        }
        let sameTiming = displayed?.timeline.frames == source.timeline.frames
        return Selection(analysisAsset: original, sourceAsset: original,
                         preservesPhotoTiming: sameTiming,
                         notice: sameTiming ? nil : "保留原始高帧率素材；相册慢动作调整无法完整还原，按原片时间分析。")
    }
    private func request(_ photo: PHAsset, version: PHVideoRequestOptionsVersion) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.version = version; options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        let manager = PHImageManager.default()
        let box = PhotoRequestBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.set(manager.requestAVAsset(forVideo: photo, options: options) { asset, _, info in
                    if let asset { continuation.resume(returning: asset) }
                    else { continuation.resume(throwing: info?[PHImageErrorKey] as? Error ?? MediaFailure.readFailed) }
                }, manager: manager)
            }
        } onCancel: { box.cancel(manager: manager) }
    }
}

private final class PhotoRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var id: PHImageRequestID?
    private var cancelled = false
    func set(_ id: PHImageRequestID, manager: PHImageManager) {
        lock.lock()
        self.id = id
        let cancel = cancelled
        lock.unlock()
        if cancel { manager.cancelImageRequest(id) }
    }
    func cancel(manager: PHImageManager) {
        lock.lock()
        cancelled = true
        let id = id
        lock.unlock()
        if let id { manager.cancelImageRequest(id) }
    }
}
