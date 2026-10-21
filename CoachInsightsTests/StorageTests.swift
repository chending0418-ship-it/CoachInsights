import AVFoundation
import SwiftData
import XCTest
@testable import CoachInsights

@MainActor final class StorageTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func fixture() async throws -> URL {
        let url = root.appendingPathComponent("original.mov")
        try await FixtureFactory.video(at: url, times: (0..<30).map { Double($0) / 30 }, duration: 1)
        return url
    }
    func testPersistentReopenAllEditorSettingsAndSharedMediaDeletion() async throws {
        let source = try await fixture()
        let originalBytes = try Data(contentsOf: source)
        let storeRoot = root.appendingPathComponent("Library")
        var repository: LibraryRepository? = try LibraryRepository(root: storeRoot)
        let first = try repository!.create(name: " 打击练习 ", sport: .batting, handedness: "右手", cameraAngle: "侧面")
        let second = try repository!.create(name: "另一份记录", sport: .pitching)
        let asset = try await repository!.importVideo(source, into: first)
        let duplicate = try await repository!.importVideo(source, into: second)
        XCTAssertEqual(asset.id, duplicate.id)
        var snapshot = try first.snapshot()
        let clip = ClipRange(start: MediaTime(seconds: 0.2), end: MediaTime(seconds: 0.8))
        snapshot.clips[asset.id.uuidString] = clip
        snapshot.views[asset.id.uuidString] = ViewSettings(zoom: 2, pan: UnitPointValue(x: 0.1, y: -0.1), mirrored: true)
        snapshot.playheads[asset.id.uuidString] = MediaTime(seconds: 0.4)
        snapshot.annotations = [Annotation(videoID: asset.id, kind: "line",
            points: [UnitPointValue(x: 0.1, y: 0.2), UnitPointValue(x: 0.5, y: 0.7)], range: clip)]
        snapshot.keyframes = [Keyframe(videoID: asset.id, time: MediaTime(seconds: 0.4), name: "触球")]
        snapshot.comparison = ComparisonSetup(leftVideoID: asset.id, rightVideoID: asset.id,
            leftAnchor: clip.start, rightAnchor: clip.start, leftClip: clip, rightClip: clip)
        snapshot.poseSettings.minimumConfidence = 0.5
        var configuration=PoseSettings();configuration.engine=MediaPipePoseEngine.identity;configuration.region=[0.1,0.1,0.7,0.8]
        snapshot.poseConfigurations[asset.id.uuidString]=configuration
        snapshot.playbackRates[asset.id.uuidString]=0.05
        snapshot.poseResults = [PoseResult(videoID: asset.id, contentHash: asset.contentHash,
            settings: snapshot.poseSettings, analyzedRange: clip, frames: [PoseFrame(time: clip.start, joints: [])])]
        try repository!.save(first, snapshot: snapshot)
        let firstID = first.id, secondID = second.id, assetPath = asset.relativePath
        repository = nil
        let reopened = try LibraryRepository(root: storeRoot)
        let records = try reopened.sessions()
        let restored = try XCTUnwrap(records.first { $0.id == firstID })
        XCTAssertEqual(restored.name, "打击练习")
        XCTAssertEqual(restored.handedness, "右手"); XCTAssertEqual(restored.cameraAngle, "侧面")
        XCTAssertEqual(try restored.snapshot(), snapshot)
        try await reopened.delete(restored)
        XCTAssertEqual(try reopened.assets().count, 1)
        let retainedURL = try await reopened.files.existingURL(assetPath)
        XCTAssertEqual(try Data(contentsOf: retainedURL), originalBytes)
        try await reopened.delete(try XCTUnwrap(records.first { $0.id == secondID }))
        XCTAssertTrue(try reopened.assets().isEmpty)
        do { _ = try await reopened.files.existingURL(assetPath); XCTFail("unreferenced copy remains") }
        catch { XCTAssertEqual(error as? StorageFailure, .missingMedia) }
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
    }
    func testLowStorageMissingMediaRelinkAndInterruptedWriteRecovery() async throws {
        let source = try await fixture()
        let low = try LibraryRepository(root: root.appendingPathComponent("Low"), availableBytes: { 0 })
        let session = try low.create(name: "低空间", sport: .batting)
        do { _ = try await low.importVideo(source, into: session); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? StorageFailure, .insufficientSpace) }
        XCTAssertTrue(try session.snapshot().videoIDs.isEmpty)
        let repository = try LibraryRepository(root: root.appendingPathComponent("Normal"))
        let record = try repository.create(name: "恢复测试", sport: .pitching)
        let asset = try await repository.importVideo(source, into: record)
        let url = try await repository.files.existingURL(asset.relativePath)
        try FileManager.default.removeItem(at: url)
        do { _ = try await repository.files.existingURL(asset.relativePath); XCTFail("must report missing") }
        catch { XCTAssertEqual(error as? StorageFailure, .missingMedia) }
        try await repository.relink(source, asset: asset)
        let restored = try await repository.files.existingURL(asset.relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.path))
        let fileRoot = root.appendingPathComponent("Normal/Files")
        let interrupted = fileRoot.appendingPathComponent("Staging/interrupted.partial")
        let orphan = fileRoot.appendingPathComponent("Media/orphan.mov")
        try Data([1,2,3]).write(to: interrupted); try Data([4]).write(to: orphan)
        try await repository.recover()
        XCTAssertFalse(FileManager.default.fileExists(atPath: interrupted.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.path))
    }
    func testRejectUnknownVersionAndInvalidReferencesWithoutOverwritingRecord() throws {
        let repository = try LibraryRepository(root: root.appendingPathComponent("Validation"))
        XCTAssertTrue(try root.appendingPathComponent("Validation").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let session = try repository.create(name: "记录", sport: .batting)
        let before = session.snapshotData
        var future = SessionSnapshot(); future.version = 2
        XCTAssertThrowsError(try repository.save(session, snapshot: future))
        var dangling = SessionSnapshot(); dangling.videoIDs = [UUID()]
        XCTAssertThrowsError(try repository.save(session, snapshot: dangling))
        XCTAssertEqual(session.snapshotData, before)
        let range = ClipRange(start: MediaTime(seconds: 0), end: MediaTime(seconds: 1))
        let result = PoseResult(videoID: UUID(), contentHash: "original", settings: .init(), analyzedRange: range, frames: [])
        XCTAssertTrue(result.isReusable(hash: "original", settings: .init(), range: range))
        XCTAssertFalse(result.isReusable(hash: "replacement", settings: .init(), range: range))
        XCTAssertFalse(result.isReusable(hash: "original", settings: .init(),
            range: ClipRange(start: range.start, end: MediaTime(seconds: 2))))
        var settings = PoseSettings(); settings.minimumConfidence = 0.9
        XCTAssertFalse(result.isReusable(hash: "original", settings: settings, range: range))
    }
    func testOldSnapshotMigrationAndInvalidGeometryCannotOverwriteSavedData() throws {
        let original=SessionSnapshot(),encoded=try JSONEncoder().encode(original)
        var dictionary=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        dictionary.removeValue(forKey:"poseConfigurations");dictionary.removeValue(forKey:"playbackRates")
        let restored=try JSONDecoder().decode(SessionSnapshot.self,from:JSONSerialization.data(withJSONObject:dictionary))
        XCTAssertTrue(restored.poseConfigurations.isEmpty);XCTAssertTrue(restored.playbackRates.isEmpty)
        let repository=try LibraryRepository(root:root.appendingPathComponent("Validation")),session=try repository.create(name:"安全",sport:.batting)
        let previous=session.snapshotData
        var invalid=restored;invalid.views["broken"]=ViewSettings(crop:[0,0,1])
        XCTAssertThrowsError(try repository.save(session,snapshot:invalid));XCTAssertEqual(previous,session.snapshotData)
        var settings=PoseSettings();settings.visible=false
        XCTAssertTrue(settings.matchesAnalysis(PoseSettings()),"Visibility does not change the inference cache key")
    }

}
