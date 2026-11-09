import UIKit
import ImageIO
import CryptoKit

enum LaunchScreenFailure: Error { case invalidConfiguration, invalidImage, invalidResponse, oversized }

struct LaunchBackgroundImage: Codable, Equatable {
    var path: String
    var sha256: String
    var mimeType: String
    var byteCount: Int
    var width: Int
    var height: Int

    func validate() throws {
        let suffix = mimeType == "image/png" ? "png" : "jpg"
        guard ["image/png", "image/jpeg"].contains(mimeType),
              sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              path == "/api/v3/app/drill-buddy/launch-assets/\(sha256).\(suffix)",
              byteCount > 0, byteCount <= 3 * 1024 * 1024,
              width > 0, width <= 4096, height > 0, height <= 8192,
              width * height <= 16_000_000 else { throw LaunchScreenFailure.invalidConfiguration }
    }
}

struct LaunchScreenConfiguration: Codable, Equatable {
    var schemaVersion = 1
    var revision = 0
    var updatedAt: Int64? = nil
    var enabled = true
    var message = ""
    var displayDurationMs = 800
    var startsAt: Int64? = nil
    var endsAt: Int64? = nil
    var backgroundImage: LaunchBackgroundImage? = nil
    static let bundled = LaunchScreenConfiguration()

    func validate() throws {
        guard schemaVersion == 1, revision >= 0, message.unicodeScalars.count <= 40,
              !message.unicodeScalars.contains(where: { ($0.value < 32 && $0.value != 10) || $0.value == 127 }),
              message.components(separatedBy: "\n").count <= 2,
              (300...2000).contains(displayDurationMs),
              [startsAt, endsAt, updatedAt].compactMap({ $0 }).allSatisfy({ (0...4_102_444_800_000).contains($0) })
        else { throw LaunchScreenFailure.invalidConfiguration }
        if let startsAt, let endsAt, endsAt <= startsAt {
            throw LaunchScreenFailure.invalidConfiguration
        }
        try backgroundImage?.validate()
    }

    func isInSchedule(at date: Date) -> Bool {
        let time = Int64(date.timeIntervalSince1970 * 1000)
        return (startsAt.map { time >= $0 } ?? true) && (endsAt.map { time < $0 } ?? true)
    }
}

struct LaunchScreenPresentation {
    var configuration: LaunchScreenConfiguration
    var image: UIImage?
    static var bundled: Self { .init(configuration: .bundled, image: nil) }
}

struct LaunchScreenDiskCache: Sendable {
    let directory: URL
    static var standard: Self {
        .init(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DrillBuddyLaunchScreen", isDirectory: true))
    }
    var manifest: URL { directory.appendingPathComponent("configuration.json") }
    func imageURL(_ image: LaunchBackgroundImage) -> URL { directory.appendingPathComponent(image.sha256 + ".image") }

    func configuration() throws -> LaunchScreenConfiguration {
        let data = try Self.read(manifest, limit: 16_384)
        let config = try JSONDecoder().decode(LaunchScreenConfiguration.self, from: data)
        try config.validate()
        return config
    }

    func presentation(at date: Date = Date()) -> LaunchScreenPresentation? {
        do {
            let config = try configuration()
            // Revision zero uses the built-in artwork.
            guard config.revision > 0 else { return .bundled }
            guard config.enabled else { return nil }
            guard config.isInSchedule(at: date) else { return .bundled }
            if let descriptor = config.backgroundImage {
                let data = try Self.read(imageURL(descriptor), limit: 3 * 1024 * 1024)
                return .init(configuration: config, image: try Self.decode(data, descriptor: descriptor))
            }
            return .init(configuration: config, image: nil)
        } catch { return .bundled }
    }

    static func read(_ url: URL, limit: Int) throws -> Data {
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size <= limit else { throw LaunchScreenFailure.oversized }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func decode(_ data: Data, descriptor: LaunchBackgroundImage) throws -> UIImage {
        try descriptor.validate()
        guard data.count == descriptor.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == descriptor.sha256,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              type == (descriptor.mimeType == "image/png" ? "public.png" : "public.jpeg"),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (info[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == descriptor.width,
              (info[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == descriptor.height,
              let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw LaunchScreenFailure.invalidImage }
        return UIImage(cgImage: decoded)
    }
}

protocol LaunchScreenTransport: Sendable {
    func configuration() async throws -> Data
    func image(_ descriptor: LaunchBackgroundImage) async throws -> Data
}

private final class LaunchScreenRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct LaunchScreenHTTPTransport: LaunchScreenTransport {
    static let productionURL = URL(string: "https://baseballmaster.cc/api/v3/app/drill-buddy/launch-screen")!
    let endpoint: URL
    private let session: URLSession
    init(endpoint: URL = productionURL) {
        self.endpoint = endpoint
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: LaunchScreenRedirectBlocker(), delegateQueue: nil)
    }
    func configuration() async throws -> Data { try await read(endpoint, limit: 16_384, mime: "application/json") }
    func image(_ descriptor: LaunchBackgroundImage) async throws -> Data {
        try descriptor.validate()
        guard let url = URL(string: descriptor.path, relativeTo: endpoint)?.absoluteURL,
              url.scheme == endpoint.scheme, url.host == endpoint.host, url.port == endpoint.port else { throw LaunchScreenFailure.invalidConfiguration }
        return try await read(url, limit: 3 * 1024 * 1024, mime: descriptor.mimeType)
    }
    private func read(_ url: URL, limit: Int, mime: String) async throws -> Data {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil else { throw LaunchScreenFailure.invalidConfiguration }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(mime, forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url,
              http.mimeType?.lowercased() == mime, http.expectedContentLength <= limit else { throw LaunchScreenFailure.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw LaunchScreenFailure.oversized }
            data.append(byte)
        }
        return data
    }
}

actor LaunchScreenRepository {
    let cache: LaunchScreenDiskCache
    let transport: any LaunchScreenTransport
    private var refreshing = false
    init(cache: LaunchScreenDiskCache, transport: any LaunchScreenTransport) { self.cache = cache; self.transport = transport }

    // Download and validate both pieces before atomically replacing the manifest.
    // This deliberately never changes a presentation already visible on screen.
    @discardableResult func refresh() async -> Bool {
        guard !refreshing else { return false }
        refreshing = true
        defer { refreshing = false }
        do {
            let config = try JSONDecoder().decode(LaunchScreenConfiguration.self, from: await transport.configuration())
            try config.validate()
            let previousImage = try? cache.configuration().backgroundImage
            try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
            if config.enabled, let descriptor = config.backgroundImage {
                let url = cache.imageURL(descriptor)
                let cached = try? LaunchScreenDiskCache.read(url, limit: 3 * 1024 * 1024)
                if cached.flatMap({ try? LaunchScreenDiskCache.decode($0, descriptor: descriptor) }) == nil {
                    let data = try await transport.image(descriptor)
                    _ = try LaunchScreenDiskCache.decode(data, descriptor: descriptor)
                    try data.write(to: url, options: .atomic)
                }
            }
            try JSONEncoder().encode(config).write(to: cache.manifest, options: .atomic)
            let keep = Set([config.backgroundImage?.sha256, previousImage?.sha256].compactMap { $0 }.map { $0 + ".image" })
            for url in (try? FileManager.default.contentsOfDirectory(at: cache.directory, includingPropertiesForKeys: nil)) ?? [] {
                if url.pathExtension == "image", !keep.contains(url.lastPathComponent) { try? FileManager.default.removeItem(at: url) }
            }
            return true
        } catch { return false }
    }
}
