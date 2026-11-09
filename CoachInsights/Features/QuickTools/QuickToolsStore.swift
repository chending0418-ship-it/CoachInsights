import SwiftUI
import UserNotifications

struct QuickToolsState: Codable {
    var version = 1
    var stopwatch = PocketStopwatch()
    var countdown = PocketCountdown()
    var boards: [TacticsDocument] = []
    var distances: [DistanceRecord] = []
}

@MainActor final class QuickToolsStore: ObservableObject {
    @Published var state = QuickToolsState()
    @Published var issue: String?
    @Published var notificationHint: String?
    private let file: URL
    private let notices = CountdownNotice()
    private var readFailed = false

    init(root: URL? = nil) {
        var directory = root ?? URL.applicationSupportDirectory.appendingPathComponent("CoachInsights")
        #if DEBUG
        if root == nil && ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            directory = URL.applicationSupportDirectory.appendingPathComponent("UITestingQuickTools")
            if ProcessInfo.processInfo.arguments.contains("--reset-library") {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        #endif
        file = directory.appendingPathComponent("quick-tools-v1.json")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                state = try JSONDecoder().decode(QuickToolsState.self, from: Data(contentsOf: file))
                guard state.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            }
            notices.restore(state.countdown)
        } catch { readFailed = true; issue = "随手工具资料未能读取，原文件已保留：" + error.localizedDescription }
    }

    func persist() {
        // Never overwrite an unreadable store with a fresh empty state.
        guard !readFailed else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var directory = file.deletingLastPathComponent(), values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try JSONEncoder().encode(state).write(to: file, options: .atomic)
            issue = nil
        } catch { issue = "保存失败：" + error.localizedDescription }
    }
    func retrySave() { persist() }
    func completeCountdown() { state.countdown.finish(at: Date()); persist() }

    func updateStopwatch(_ change: (inout PocketStopwatch) -> Void) {
        change(&state.stopwatch); persist()
    }
    func updateCountdown(_ change: (inout PocketCountdown) -> Void, requestNotification: Bool = false) {
        change(&state.countdown); persist()
        notices.synchronize(state.countdown, requestPermission: requestNotification) { [weak self] hint in
            self?.notificationHint = hint
        }
    }
    func saveBoard(_ document: TacticsDocument) {
        var value = document; value.updatedAt = Date()
        if let index = state.boards.firstIndex(where: { $0.id == value.id }) { state.boards[index] = value }
        else { state.boards.insert(value, at: 0) }
        persist()
    }
    func saveDistance(_ value: DistanceRecord) {
        guard value.meters.isFinite, value.meters > 0,
              !state.distances.contains(where: { $0.id == value.id }) else { return }
        state.distances.insert(value, at: 0); persist()
    }
    func removeRecord(_ id: UUID) {
        state.boards.removeAll { $0.id == id }
        state.distances.removeAll { $0.id == id }
        persist()
    }
}

/// Each run has its own notification ID: a late authorization/add completion
/// from a cancelled run can never remove the new run's notification.
@MainActor private final class CountdownNotice {
    private var task: Task<Void, Never>?
    private var pendingID: String?

    func restore(_ countdown: PocketCountdown) {
        if countdown.deadline != nil { pendingID = "coach-pocket.countdown." + countdown.runID.uuidString }
    }

    func synchronize(_ countdown: PocketCountdown, requestPermission: Bool, hint: @escaping (String?) -> Void) {
        task?.cancel()
        let center = UNUserNotificationCenter.current()
        if let pendingID {
            center.removePendingNotificationRequests(withIdentifiers: [pendingID])
            center.removeDeliveredNotifications(withIdentifiers: [pendingID])
        }
        pendingID = nil
        guard let deadline = countdown.deadline, deadline > Date() else { hint(nil); return }
        let identifier = "coach-pocket.countdown." + countdown.runID.uuidString
        pendingID = identifier
        task = Task {
            do {
                var status = await center.notificationSettings().authorizationStatus
                if status == .notDetermined && requestPermission {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                    status = await center.notificationSettings().authorizationStatus
                }
                guard !Task.isCancelled else { return }
                guard status == .authorized || status == .provisional || status == .ephemeral else {
                    hint("通知未开启，离开 App 后不会响铃；可在系统设置中开启。")
                    return
                }
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { return }
                let content = UNMutableNotificationContent()
                content.title = "倒计时结束"; content.body = "棒球训练助手：设定的时间已到。"; content.sound = .default
                let request = UNNotificationRequest(identifier: identifier, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false))
                try await center.add(request)
                if Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
                else { hint(nil) }
            } catch {
                if !Task.isCancelled { hint("结束提醒未能设置：" + error.localizedDescription) }
            }
        }
    }
}
