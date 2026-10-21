import AVFoundation
import UIKit

struct ResolvedFrame {
    let image: CGImage
    let index: Int
    let requestedTime: MediaTime
    let actualTime: MediaTime
}

actor FrameProvider {
    private let asset: AVAsset
    private let metadata: MediaMetadata
    private let maximumDimension: CGFloat
    private var cache: LRUCache<Int, ResolvedFrame>
    private var pressureTask: Task<Void, Never>?
    private var cacheEpoch: UInt64 = 0

    init(asset: AVAsset, metadata: MediaMetadata, maximumDimension: CGFloat = 1280,
         costLimit: Int = 64 * 1024 * 1024) {
        self.asset = asset; self.metadata = metadata
        self.maximumDimension = maximumDimension
        cache = LRUCache(costLimit: costLimit)
    }

    func frame(at index: Int) async throws -> ResolvedFrame {
        try Task.checkCancellation()
        if pressureTask == nil {
            pressureTask = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                    await self?.clear()
                }
            }
        }
        let index = metadata.timeline.steppedIndex(from: index, by: 0)
        if let cached = cache.value(for: index) { return cached }
        try Task.checkCancellation()
        let epoch = cacheEpoch
        // A generator per outstanding request keeps cancellation local to that request.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if #available(iOS 18, *) { generator.dynamicRangePolicy = .forceSDR }
        generator.maximumSize = CGSize(width: maximumDimension, height: maximumDimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = metadata.timeline.frames[index].presentationTime
        let (image, actual) = try await withTaskCancellationHandler {
            try await generator.image(at: time.cmTime)
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
        try Task.checkCancellation()
        let result = ResolvedFrame(image: image, index: index, requestedTime: time,
                                   actualTime: MediaTime(actual))
        if epoch == cacheEpoch { cache.insert(result, for: index, cost: image.bytesPerRow * image.height) }
        return result
    }

    func prefetch(around index: Int, radius: Int = 2) async {
        let center = metadata.timeline.steppedIndex(from: index, by: 0)
        let boundedRadius = min(max(0, radius), metadata.timeline.frames.count - 1)
        let lower = max(0, center - boundedRadius)
        let upper = min(metadata.timeline.frames.count - 1, center + boundedRadius)
        for frameIndex in lower...upper {
            if Task.isCancelled { return }
            _ = try? await frame(at: frameIndex)
        }
    }
    func clear() { cacheEpoch &+= 1; cache.removeAll() }
    var cachedByteCount: Int { cache.totalCost }
    deinit { pressureTask?.cancel() }
}

@MainActor
final class LatestTaskRunner<Value> {
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    func submit(operation: @escaping () async throws -> Value,
                result: @escaping (Result<Value, Error>) -> Void) {
        cancel()
        let token = generation
        task = Task {
            do {
                let value = try await operation()
                guard !Task.isCancelled, token == generation else { return }
                result(.success(value))
            } catch {
                guard !Task.isCancelled, token == generation else { return }
                result(.failure(error))
            }
        }
    }
    func cancel() { generation &+= 1; task?.cancel(); task = nil }
}
