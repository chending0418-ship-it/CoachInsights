import CryptoKit
import Foundation

struct StoredMedia: Sendable { let relativePath: String; let hash: String; let originalName: String }

actor LocalFileStore {
    let root: URL
    private let availableBytes: (@Sendable () throws -> Int64)?
    init(root: URL, availableBytes: (@Sendable () throws -> Int64)? = nil) throws {
        self.root = root
        self.availableBytes = availableBytes
        for directory in ["Media", "Staging", "Cache"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory),
                                                   withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = root
        try root.setResourceValues(values)
    }
    func mediaURL(_ relativePath: String) throws -> URL {
        guard relativePath.hasPrefix("Media/"), !relativePath.contains(".."),
              relativePath.split(separator: "/").count == 2 else { throw StorageFailure.unsafePath }
        return root.appendingPathComponent(relativePath)
    }
    func existingURL(_ relativePath: String) throws -> URL {
        let url = try mediaURL(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw StorageFailure.missingMedia }
        return url
    }
    func importCopy(from source: URL) throws -> StoredMedia {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let free = try availableBytes?() ?? root.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard free > Int64(size) + 32 * 1024 * 1024 else { throw StorageFailure.insufficientSpace }
        let stage = root.appendingPathComponent("Staging/\(UUID().uuidString).partial")
        defer { try? FileManager.default.removeItem(at: stage) }
        // Copy first, then hash the immutable local snapshot. Never modify the provider's original.
        try FileManager.default.copyItem(at: source, to: stage)
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: stage)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            digest.update(data: data)
        }
        let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let suffix = source.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        let relative = "Media/\(hash).\(suffix.isEmpty ? "mov" : suffix)"
        let destination = try mediaURL(relative)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: stage, to: destination)
        }
        return StoredMedia(relativePath: relative, hash: hash, originalName: source.lastPathComponent)
    }
    // Call only with a complete, successfully fetched database reference set.
    func reconcile(referencedPaths: Set<String>) throws {
        for path in referencedPaths { _ = try mediaURL(path) }
        let fm = FileManager.default
        for file in try fm.contentsOfDirectory(at: root.appendingPathComponent("Staging"),
                                               includingPropertiesForKeys: nil) {
            try fm.removeItem(at: file)
        }
        for file in try fm.contentsOfDirectory(at: root.appendingPathComponent("Media"),
                                               includingPropertiesForKeys: nil) {
            if !referencedPaths.contains("Media/" + file.lastPathComponent) { try fm.removeItem(at: file) }
        }
    }
    func clearCaches() throws {
        let directory = root.appendingPathComponent("Cache")
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
