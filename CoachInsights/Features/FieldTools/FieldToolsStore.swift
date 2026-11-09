import SwiftUI

struct FieldToolsState: Codable {
    var version = 1
    var drafts = FieldLogKind.allCases.map { FieldLog(kind: $0) }
    var records: [FieldLog] = []
}

/// Separate from both the legacy video library and quick-tools-v1.json.
/// Publish only after an atomic write succeeds, so the UI never reports a failed
/// save as completed. Unreadable or newer stores are retained without overwrite.
@MainActor final class FieldToolsStore: ObservableObject {
    @Published private(set) var state = FieldToolsState()
    @Published private(set) var issue: String?
    private let file: URL
    private var readFailed = false

    init(root: URL? = nil) {
        var directory = root ?? URL.applicationSupportDirectory.appendingPathComponent("CoachInsights")
        #if DEBUG
        if root == nil && ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            directory = URL.applicationSupportDirectory.appendingPathComponent("UITestingFieldTools")
            if ProcessInfo.processInfo.arguments.contains("--reset-library") { try? FileManager.default.removeItem(at: directory) }
        }
        #endif
        file = directory.appendingPathComponent("field-tools-v1.json")
        reload()
    }
    func reload() {
        do {
            let value = FileManager.default.fileExists(atPath: file.path)
                ? try JSONDecoder().decode(FieldToolsState.self, from: Data(contentsOf: file)) : FieldToolsState()
            guard value.version == 1, value.drafts.count == FieldLogKind.allCases.count,
                  Set(value.drafts.map(\.kind)).count == FieldLogKind.allCases.count else { throw CocoaError(.fileReadCorruptFile) }
            state = value; readFailed = false; issue = nil
        } catch { readFailed = true; issue = "训练记录未能读取，原文件已保留。修复文件后可重试读取：" + error.localizedDescription }
    }
    func log(kind: FieldLogKind, id: UUID?) -> FieldLog? {
        if let id { return state.records.first { $0.id == id && $0.kind == kind } }
        return state.drafts.first { $0.kind == kind }
    }
    @discardableResult func update(_ log: FieldLog) -> Bool {
        guard !log.ended else { return false }
        var value = log; value.updatedAt = Date()
        return commit { state in
            if let index = state.drafts.firstIndex(where: { $0.id == value.id }) { state.drafts[index] = value }
            if let index = state.records.firstIndex(where: { $0.id == value.id }) { state.records[index] = value }
        }
    }
    @discardableResult func save(_ log: FieldLog, ending: Bool = false) -> Bool {
        guard !log.events.isEmpty else { return false }
        var value = log; value.updatedAt = Date(); value.ended = ending || log.ended
        return commit { state in
            if let index = state.records.firstIndex(where: { $0.id == value.id }) { state.records[index] = value }
            else { state.records.insert(value, at: 0) }
            if let index = state.drafts.firstIndex(where: { $0.id == value.id }) {
                state.drafts[index] = ending ? FieldLog(kind: value.kind) : value
            }
        }
    }
    @discardableResult func remove(_ id: UUID) -> Bool {
        commit { state in
            state.records.removeAll { $0.id == id }
            if let index = state.drafts.firstIndex(where: { $0.id == id }) { state.drafts[index] = FieldLog(kind: state.drafts[index].kind) }
        }
    }
    private func commit(_ change: (inout FieldToolsState) -> Void) -> Bool {
        guard !readFailed else { return false }
        var next = state; change(&next)
        do {
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory, attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
            try url.setResourceValues(attributes)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            state = next; issue = nil; return true
        } catch { issue = "本次操作未保存，请重试：" + error.localizedDescription; return false }
    }
}
