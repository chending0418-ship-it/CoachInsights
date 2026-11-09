import CryptoKit
import UIKit
import XCTest
@testable import CoachInsights

private struct LaunchTransportFixture: LaunchScreenTransport {
    let config: LaunchScreenConfiguration
    var picture = Data()
    var offline = false

    func configuration() throws -> Data {
        if offline { throw URLError(.notConnectedToInternet) }
        return try JSONEncoder().encode(config)
    }

    func image(_ descriptor: LaunchBackgroundImage) -> Data { picture }
}

final class LaunchScreenTests: XCTestCase {
    private func makeCache() throws -> LaunchScreenDiskCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return LaunchScreenDiskCache(directory: directory)
    }

    func testNoPublishedConfigurationUsesTrainingAppArtwork() async throws {
        let cache = try makeCache()
        XCTAssertEqual(cache.presentation()?.configuration, .bundled)
        let scorekeeperDefault = LaunchScreenConfiguration(message: "每一球 都有迹可循")
        let repository = LaunchScreenRepository(cache: cache, transport: LaunchTransportFixture(config: scorekeeperDefault))
        let saved = await repository.refresh()
        XCTAssertTrue(saved)
        XCTAssertEqual(cache.presentation()?.configuration, .bundled)
    }

    func testPublishedConfigurationHonorsScheduleAndDisable() throws {
        let cache = try makeCache()
        var config = LaunchScreenConfiguration(revision: 1, message: "今天的训练",
                                               displayDurationMs: 1200, startsAt: 1_000, endsAt: 2_000)
        try JSONEncoder().encode(config).write(to: cache.manifest)
        XCTAssertEqual(cache.presentation(at: Date(timeIntervalSince1970: 0))?.configuration, .bundled)
        XCTAssertEqual(cache.presentation(at: Date(timeIntervalSince1970: 1))?.configuration, config)
        XCTAssertEqual(cache.presentation(at: Date(timeIntervalSince1970: 2))?.configuration, .bundled)

        config.enabled = false
        try JSONEncoder().encode(config).write(to: cache.manifest)
        XCTAssertNil(cache.presentation(at: Date(timeIntervalSince1970: 1)))
    }

    func testVerifiedImageAndConfigurationAreAdoptedTogether() async throws {
        let cache = try makeCache()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = try XCTUnwrap(UIGraphicsImageRenderer(
            size: CGSize(width: 16, height: 32),
            format: format
        ).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 32))
        }.pngData())
        let hash = SHA256.hash(data: picture).map { String(format: "%02x", $0) }.joined()
        let descriptor = LaunchBackgroundImage(path: "/api/v3/app/drill-buddy/launch-assets/\(hash).png", sha256: hash,
                                               mimeType: "image/png", byteCount: picture.count, width: 16, height: 32)
        let config = LaunchScreenConfiguration(revision: 1, message: "新开屏", backgroundImage: descriptor)
        let visible = cache.presentation()
        let repository = LaunchScreenRepository(cache: cache, transport: LaunchTransportFixture(config: config, picture: picture))
        let saved = await repository.refresh()
        XCTAssertTrue(saved)
        XCTAssertEqual(visible?.configuration, .bundled)
        XCTAssertEqual(cache.presentation()?.configuration, config)
        XCTAssertNotNil(cache.presentation()?.image)

        try Data("corrupt image".utf8).write(to: cache.imageURL(descriptor))
        XCTAssertEqual(cache.presentation()?.configuration, .bundled)
    }

    func testOfflineAndInvalidImagePreserveLastPublishedConfiguration() async throws {
        let cache = try makeCache()
        let previous = LaunchScreenConfiguration(revision: 1, message: "离线可用")
        try JSONEncoder().encode(previous).write(to: cache.manifest)
        let hash = String(repeating: "a", count: 64)
        let descriptor = LaunchBackgroundImage(path: "/api/v3/app/drill-buddy/launch-assets/\(hash).png", sha256: hash,
                                               mimeType: "image/png", byteCount: 3, width: 1, height: 1)
        let candidate = LaunchScreenConfiguration(revision: 2, message: "更新", backgroundImage: descriptor)
        for fixture in [LaunchTransportFixture(config: candidate, offline: true),
                        LaunchTransportFixture(config: candidate, picture: Data("bad".utf8))] {
            let updated = await LaunchScreenRepository(cache: cache, transport: fixture).refresh()
            XCTAssertFalse(updated)
            XCTAssertEqual(cache.presentation()?.configuration, previous)
        }
    }
}
