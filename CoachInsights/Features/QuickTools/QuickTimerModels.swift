import Foundation

struct StopwatchLap: Codable, Identifiable, Equatable {
    var id = UUID()
    let number: Int
    let duration: TimeInterval
    let total: TimeInterval
}

/// Persist control changes, not display ticks. A reference date also survives
/// suspension, navigation, and process termination without a background timer.
struct PocketStopwatch: Codable, Equatable {
    var accumulated: TimeInterval = 0
    var startedAt: Date?
    var laps: [StopwatchLap] = []
    var isRunning: Bool { startedAt != nil }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + max(0, startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }
    mutating func start(at now: Date) {
        guard !isRunning else { return }
        startedAt = now
    }
    mutating func pause(at now: Date) {
        accumulated = elapsed(at: now)
        startedAt = nil
    }
    mutating func lap(at now: Date) {
        guard isRunning else { return }
        let total = elapsed(at: now)
        laps.append(StopwatchLap(number: laps.count + 1,
            duration: max(0, total - (laps.last?.total ?? 0)), total: total))
    }
    mutating func reset() { self = PocketStopwatch() }
}

struct PocketCountdown: Codable, Equatable {
    var duration: TimeInterval = 60
    var pausedRemaining: TimeInterval?
    var deadline: Date?
    var runID = UUID()
    var isRunning: Bool { deadline != nil }
    var isConfigured: Bool { deadline == nil && pausedRemaining == nil }

    func remaining(at now: Date) -> TimeInterval {
        max(0, deadline.map { $0.timeIntervalSince(now) } ?? pausedRemaining ?? duration)
    }
    func isFinished(at now: Date) -> Bool {
        !isConfigured && remaining(at: now) <= 0
    }
    mutating func start(at now: Date) {
        guard !isRunning else { return }
        let value = pausedRemaining ?? duration
        guard value > 0 else { return }
        runID = UUID()
        deadline = now.addingTimeInterval(value)
        pausedRemaining = nil
    }
    mutating func pause(at now: Date) {
        guard isRunning else { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
    }
    mutating func cancel() {
        deadline = nil
        pausedRemaining = nil
        runID = UUID()
    }
    mutating func finish(at now: Date) {
        guard isRunning, remaining(at: now) <= 0 else { return }
        deadline = nil
        pausedRemaining = 0
    }
}

enum PocketTimeFormat {
    static func stopwatch(_ seconds: TimeInterval) -> String {
        let ticks = Int(max(0, seconds) * 100)
        let minutes = ticks / 6000
        return String(format: "%02d:%02d.%02d", minutes, (ticks / 100) % 60, ticks % 100)
    }
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(max(0, seconds)))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60) }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
