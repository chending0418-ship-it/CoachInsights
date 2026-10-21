import Foundation
import SwiftData

@MainActor final class LibraryRepository {
    let container: ModelContainer
    let context: ModelContext
    let files: LocalFileStore
    private let inspector = MediaInspector()
    private var importingSessions: Set<UUID> = []
    init(root: URL, inMemory: Bool = false, availableBytes: (@Sendable () throws -> Int64)? = nil) throws {
        files = try LocalFileStore(root: root.appendingPathComponent("Files"), availableBytes: availableBytes)
        var localRoot = root
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try localRoot.setResourceValues(resourceValues)
        let schema = Schema([VideoAsset.self, AnalysisSession.self])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("Library.store"),
                                               cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }
    func sessions() throws -> [AnalysisSession] {
        try context.fetch(FetchDescriptor<AnalysisSession>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }
    func assets() throws -> [VideoAsset] { try context.fetch(FetchDescriptor<VideoAsset>()) }
    func create(name: String, sport: Sport, handedness: String? = nil, cameraAngle: String? = nil) throws -> AnalysisSession {
        let session = try AnalysisSession(name: cleanName(name), sport: sport)
        session.handedness = handedness; session.cameraAngle = cameraAngle
        context.insert(session)
        do { try context.save(); return session }
        catch { context.rollback(); throw error }
    }
    func save(_ session: AnalysisSession, snapshot: SessionSnapshot) throws {
        try snapshot.validate()
        let known = Set(try assets().map(\.id))
        guard Set(snapshot.videoIDs).isSubset(of: known) else { throw StorageFailure.invalidRecord }
        let encoded = try JSONEncoder().encode(snapshot)
        session.snapshotData = encoded; session.updatedAt = Date()
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func rename(_ session: AnalysisSession, to name: String) throws {
        session.name = cleanName(name); session.updatedAt = Date()
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func importVideo(_ source: URL, into session: AnalysisSession, timing: MediaMetadata? = nil,
                     progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> VideoAsset {
        guard !importingSessions.contains(session.id) else { throw StorageFailure.busy }
        importingSessions.insert(session.id)
        defer { importingSessions.remove(session.id) }
        let stored = try await files.importCopy(from: source, progress: progress)
        let url = try await files.existingURL(stored.relativePath)
        // Failed inspection leaves an unreferenced immutable file; recovery removes it safely.
        let original = try await inspector.inspect(url: url)
        let metadata = timing ?? original
        try metadata.validateVersion()
        try Task.checkCancellation()
        var snapshot = try session.snapshot()
        let asset: VideoAsset
        if let existing = try assets().first(where: { $0.contentHash == stored.hash && (try? $0.metadata()) == metadata }) { asset = existing }
        else {
            asset = try VideoAsset(relativePath: stored.relativePath, contentHash: stored.hash,
                                  originalName: stored.originalName, metadata: metadata)
            context.insert(asset)
        }
        if !snapshot.videoIDs.contains(asset.id) { snapshot.videoIDs.append(asset.id) }
        if snapshot.clips[asset.id.uuidString] == nil { snapshot.clips[asset.id.uuidString] = ClipRange(start: metadata.timeline.frames[0].presentationTime, end: metadata.timeline.duration) }
        do { try save(session, snapshot: snapshot); return asset }
        catch { context.rollback(); throw error }
    }
    func delete(_ session: AnalysisSession) async throws {
        guard !importingSessions.contains(session.id) else { throw StorageFailure.busy }
        // Decode every retained record before mutation. Unknown versions never trigger media deletion.
        let retained = try sessions().filter { $0.id != session.id }
        let referenced = try Set(retained.flatMap { try $0.snapshot().videoIDs })
        let candidates = try assets().filter { !referenced.contains($0.id) }
        context.delete(session)
        for asset in candidates { context.delete(asset) }
        do { try context.save() } catch { context.rollback(); throw error }
        try await recover()
    }
    func recover() async throws {
        guard importingSessions.isEmpty else { return }
        let allSessions = try sessions()
        let ids = try Set(allSessions.flatMap { try $0.snapshot().videoIDs })
        let allAssets = try assets()
        guard allAssets.allSatisfy({ $0.version == 1 }) else { throw MediaFailure.unsupportedVersion }
        guard ids.isSubset(of: Set(allAssets.map(\.id))) else { throw StorageFailure.invalidRecord }
        // Stale assets with no session reference are removed after database commit.
        for asset in allAssets where !ids.contains(asset.id) { context.delete(asset) }
        do { try context.save() } catch { context.rollback(); throw error }
        let paths = Set(allAssets.filter { ids.contains($0.id) }.map(\.relativePath))
        try await files.reconcile(referencedPaths: paths)
    }
    func relink(_ source: URL, asset: VideoAsset) async throws {
        let stored = try await files.importCopy(from: source)
        guard stored.hash == asset.contentHash else { throw StorageFailure.contentMismatch }
        asset.relativePath = stored.relativePath
        do { try context.save() } catch { context.rollback(); throw error }
    }
    private func cleanName(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未命名分析" : String(value.prefix(120))
    }
}
