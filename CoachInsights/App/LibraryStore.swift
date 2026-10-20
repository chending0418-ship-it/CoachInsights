import Foundation
import SwiftUI

@MainActor final class LibraryStore: ObservableObject {
    @Published var sessions: [AnalysisSession] = []
    @Published var issue: String?
    @Published var busy = false
    private(set) var repository: LibraryRepository?
    init() {
        do {
            var root = URL.applicationSupportDirectory.appendingPathComponent("CoachInsights")
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                root = URL.applicationSupportDirectory.appendingPathComponent("UITesting")
                if ProcessInfo.processInfo.arguments.contains("--reset-library") {
                    try? FileManager.default.removeItem(at: root)
                }
            }
            #endif
            repository = try LibraryRepository(root: root)
            reload()
        } catch { issue = "本机资料库未能打开：\(error.localizedDescription)。可重试，已有文件会保留。" }
    }
    func reload() {
        do { sessions = try repository?.sessions() ?? [] }
        catch { issue = error.localizedDescription }
    }
    func retry() async {
        if repository == nil {
            do {
                repository = try LibraryRepository(root: URL.applicationSupportDirectory.appendingPathComponent("CoachInsights"))
            } catch { issue = error.localizedDescription; return }
        }
        do { try await repository?.recover(); issue = nil; reload() }
        catch { issue = error.localizedDescription }
    }
    func create(name: String, sport: Sport, handedness: String?, angle: String?) -> AnalysisSession? {
        do {
            let session = try repository?.create(name: name, sport: sport, handedness: handedness, cameraAngle: angle)
            reload(); return session
        } catch { issue = error.localizedDescription; return nil }
    }
    func rename(_ session: AnalysisSession, name: String) {
        do { try repository?.rename(session, to: name); reload() }
        catch { issue = error.localizedDescription }
    }
    func remove(_ session: AnalysisSession) async {
        busy = true; defer { busy = false }
        do { try await repository?.delete(session); reload() }
        catch { issue = error.localizedDescription; reload() }
    }
    func save(_ session: AnalysisSession, snapshot: SessionSnapshot) {
        do { try repository?.save(session, snapshot: snapshot); reload() }
        catch { issue = error.localizedDescription }
    }
}
