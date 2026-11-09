import Foundation

enum FieldLogKind: String, Codable, CaseIterable {
    case batting, bullpen, game
    var tool: PocketTool {
        switch self { case .batting: return .battingLog; case .bullpen: return .bullpenLog; case .game: return .gameCounter }
    }
}

enum BattingContact: String, Codable, CaseIterable {
    case ground, line, fly, miss
    var title: String {
        switch self { case .ground: return "滚地"; case .line: return "平飞"; case .fly: return "高飞"; case .miss: return "挥空" }
    }
}

enum PitchZone: String, Codable, CaseIterable {
    case upperLeft, upperMiddle, upperRight, middleLeft, center, middleRight, lowerLeft, lowerMiddle, lowerRight
    case high, low, left, right
    static let grid: [PitchZone] = Array(allCases.prefix(9))
    var isStrikeZone: Bool { Self.grid.contains(self) }
    var title: String {
        switch self {
        case .upperLeft: return "左上"; case .upperMiddle: return "中上"; case .upperRight: return "右上"
        case .middleLeft: return "左中"; case .center: return "正中"; case .middleRight: return "右中"
        case .lowerLeft: return "左下"; case .lowerMiddle: return "中下"; case .lowerRight: return "右下"
        case .high: return "偏高"; case .low: return "偏低"; case .left: return "偏左"; case .right: return "偏右"
        }
    }
}

struct PitchMark: Codable, Equatable {
    var zone: PitchZone
    var isStrike: Bool
    var location: FieldPoint?
    var point: FieldPoint { location ?? zone.point }
    init(point: FieldPoint) { zone = .at(point); isStrike = zone.isStrikeZone; location = point }
    init(zone: PitchZone) { self.zone = zone; isStrike = zone.isStrikeZone }
}

enum GameAction: String, Codable {
    case strike, ball, out, clearBatter, awayRun, homeRun

    var title: String {
        switch self {
        case .strike: return "好球 +1"
        case .ball: return "坏球 +1"
        case .out: return "出局 +1"
        case .clearBatter: return "下一位打者"
        case .awayRun: return "客队得分 +1"
        case .homeRun: return "主队得分 +1"
        }
    }
}
enum FieldEvent: Codable, Equatable {
    case batting(BattingContact)
    case pitch(PitchMark)
    case bullpenOut
    case game(GameAction)
    case gameCorrection(GameCountCorrection)
}

enum FieldUndo: Codable, Equatable {
    case removeLast
    case restore([FieldEvent])
    case replace(Int, FieldEvent)
}

struct GameCountCorrection: Codable, Equatable {
    let awayRuns: Int
    let homeRuns: Int
    let strikes: Int
    let balls: Int
    let outs: Int

    var isValid: Bool {
        awayRuns >= 0 && homeRuns >= 0
            && (0...2).contains(strikes) && (0...3).contains(balls) && (0...2).contains(outs)
    }
}

struct GameCount: Equatable {
    var strikes = 0, balls = 0, outs = 0, sides = 0
    var awayRuns = 0, homeRuns = 0
    var notice: String?
    mutating func apply(_ action: GameAction) {
        if action != .awayRun && action != .homeRun { notice = nil }
        switch action {
        case .strike:
            strikes += 1
            if strikes == 3 { strikes = 0; balls = 0; addOut(); notice = outs == 0 ? "三振，三出局，换边" : "三振出局" }
        case .ball:
            balls += 1
            if balls == 4 { balls = 0; strikes = 0; notice = "四坏保送，下一位打者" }
        case .out:
            balls = 0; strikes = 0; addOut(); notice = outs == 0 ? "三出局，换边" : "出局，下一位打者"
        case .clearBatter: balls = 0; strikes = 0; notice = "下一位打者"
        case .awayRun: if awayRuns < Int.max { awayRuns += 1 }
        case .homeRun: if homeRuns < Int.max { homeRuns += 1 }
        }
    }
    var correction: GameCountCorrection {
        .init(awayRuns: awayRuns, homeRuns: homeRuns, strikes: strikes, balls: balls, outs: outs)
    }

    mutating func apply(_ correction: GameCountCorrection) {
        guard correction.isValid else { return }
        awayRuns = correction.awayRuns
        homeRuns = correction.homeRuns
        strikes = correction.strikes
        balls = correction.balls
        outs = correction.outs
        notice = nil
    }

    private mutating func addOut() {
        outs += 1
        if outs == 3 { outs = 0; balls = 0; strikes = 0; sides += 1 }
    }
}

struct FieldLog: Codable, Identifiable, Equatable {
    var id = UUID()
    let kind: FieldLogKind
    var name = ""
    var createdAt = Date()
    var updatedAt = Date()
    var events: [FieldEvent] = []
    var undoHistory: [FieldUndo] = []
    var ended = false
    static let eventLimit = 10000

    var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.tool.title : name }
    var pitches: [PitchMark] { events.compactMap { if case .pitch(let mark) = $0 { return mark }; return nil } }
    var strikeCount: Int { pitches.filter(\.isStrike).count }
    var outCount: Int { events.filter { $0 == .bullpenOut }.count }
    func count(_ contact: BattingContact) -> Int { events.filter { $0 == .batting(contact) }.count }
    var gameCount: GameCount {
        var result = GameCount()
        for event in events {
            switch event {
            case .game(let action): result.apply(action)
            case .gameCorrection(let correction): result.apply(correction)
            default: break
            }
        }
        return result
    }
    var summary: String {
        switch kind {
        case .batting: return BattingContact.allCases.map { "\($0.title) \(count($0))" }.joined(separator: " · ")
        case .bullpen: return "总球数 \(pitches.count) · 好球 \(strikeCount) · 坏球 \(pitches.count - strikeCount) · 出局 \(outCount)"
        case .game:
            let count = gameCount
            return "客 \(count.awayRuns) 比 \(count.homeRuns) 主 · 好球 \(count.strikes) · 坏球 \(count.balls) · 出局 \(count.outs) · 已换边 \(count.sides) 次"
        }
    }
    mutating func append(_ event: FieldEvent) {
        guard !ended, events.count < Self.eventLimit else { return }
        switch (kind, event) {
        case (.batting, .batting), (.bullpen, .pitch), (.bullpen, .bullpenOut), (.game, .game):
            checkpoint(.removeLast); events.append(event)
        case (.game, .gameCorrection(let correction)) where correction.isValid && correction != gameCount.correction:
            checkpoint(.removeLast); events.append(event)
        default: break
        }
    }
    /// Corrections replace the same pitch, preserving the pitch total and order.
    mutating func correctPitch(at index: Int, zone: PitchZone? = nil, isStrike: Bool? = nil, location: FieldPoint? = nil) {
        guard !ended, events.indices.contains(index), case .pitch(var mark) = events[index] else { return }
        let before = mark
        if let zone { mark.zone = zone; mark.location = nil }
        if let location { mark.location = location; mark.zone = .at(location) }
        if let isStrike { mark.isStrike = isStrike }
        if before != mark { checkpoint(.replace(index, .pitch(before))); events[index] = .pitch(mark) }
    }
    mutating func clear() {
        guard !ended, !events.isEmpty else { return }
        checkpoint(.restore(events)); events.removeAll()
    }
    mutating func undo() {
        guard !ended else { return }
        guard let action = undoHistory.popLast() else { return }
        switch action {
        case .removeLast: if !events.isEmpty { events.removeLast() }
        case .restore(let previous): events = previous
        case .replace(let index, let event): if events.indices.contains(index) { events[index] = event }
        }
    }
    private mutating func checkpoint(_ action: FieldUndo) {
        undoHistory.append(action)
        if undoHistory.count > 100 { undoHistory.removeFirst() }
    }
}

extension PocketRecord {
    init(fieldLog: FieldLog) {
        self.init(id: fieldLog.id, name: fieldLog.title, sport: nil, createdAt: fieldLog.updatedAt,
                  tool: fieldLog.kind.tool, summary: fieldLog.summary)
    }
}

extension PitchZone {
    static let strikeRect = CGRect(x: 0.28, y: 0.23, width: 0.44, height: 0.52)
    var point: FieldPoint {
        let rect = Self.strikeRect
        if let index = Self.grid.firstIndex(of: self) {
            return FieldPoint(x: rect.minX + rect.width * (Double(index % 3) + 0.5) / 3,
                              y: rect.minY + rect.height * (Double(index / 3) + 0.5) / 3)
        }
        switch self {
        case .high: return FieldPoint(x: 0.5, y: 0.12)
        case .low: return FieldPoint(x: 0.5, y: 0.85)
        case .left: return FieldPoint(x: 0.14, y: 0.49)
        default: return FieldPoint(x: 0.86, y: 0.49)
        }
    }
    static func at(_ point: FieldPoint) -> PitchZone {
        let rect = Self.strikeRect
        let x = (point.x - rect.minX) / rect.width, y = (point.y - rect.minY) / rect.height
        if x >= 0, x <= 1, y >= 0, y <= 1 {
            return grid[min(2, Int(y * 3)) * 3 + min(2, Int(x * 3))]
        }
        let deviations: [(Double, PitchZone)] = [(-y, .high), (y - 1, .low), (-x, .left), (x - 1, .right)]
        return deviations.max { $0.0 < $1.0 }!.1
    }
}
