import UIKit

actor ThumbnailStore {
    private let directory: URL
    private let byteLimit: Int
    init(directory: URL, byteLimit: Int = 24 * 1024 * 1024) throws {
        self.directory = directory; self.byteLimit = byteLimit
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func image(contentHash: String, frame: Int, provider: FrameProvider) async throws -> UIImage {
        guard contentHash.count == 64, contentHash.allSatisfy({ $0.isHexDigit }), frame >= 0 else {
            throw StorageFailure.unsafePath
        }
        // Version + content hash + frame prevents stale cache reuse after source/schema changes.
        let url = directory.appendingPathComponent("v1-\(contentHash)-\(frame).jpg")
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return image
        }
        let resolved = try await provider.frame(at: frame)
        let image = UIImage(cgImage: resolved.image)
        let ratio = min(1, 240 / max(image.size.width, image.size.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: image.size.width * ratio,
                                                           height: image.size.height * ratio), format: format).image {
            _ in image.draw(in: CGRect(origin: .zero, size: CGSize(width: image.size.width * ratio,
                                                                  height: image.size.height * ratio)))
        }
        if let data = thumbnail.jpegData(compressionQuality: 0.7), data.count <= byteLimit {
            try data.write(to: url, options: .atomic)
            try trim()
        }
        return thumbnail
    }
    private func trim() throws {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            .map { ($0, try $0.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])) }
            .sorted { ($0.1.contentModificationDate ?? .distantPast) < ($1.1.contentModificationDate ?? .distantPast) }
        var total = files.reduce(0) { $0 + ($1.1.fileSize ?? 0) }
        for (url, values) in files where total > byteLimit {
            try fm.removeItem(at: url); total -= values.fileSize ?? 0
        }
    }
    func clear() throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
