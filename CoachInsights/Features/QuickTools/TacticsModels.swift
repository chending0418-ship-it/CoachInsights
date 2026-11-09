import Foundation

struct FieldPoint: Codable, Equatable {
    var x: Double
    var y: Double
    init(x: Double, y: Double) {
        self.x = min(1, max(0, x)); self.y = min(1, max(0, y))
    }
}

enum BoardInk: String, Codable, CaseIterable {
    case burgundy, white, yellow, red, blue
}

struct BoardStroke: Codable, Identifiable, Equatable {
    var id = UUID()
    var points: [FieldPoint]
    var ink: BoardInk
    var isArrow: Bool? = nil
}

struct FieldPlayer: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var position: FieldPoint
    var isRunner = false

    static var defense: [FieldPlayer] {
        [player("投", 0.5, 0.65), player("捕", 0.5, 0.94),
         player("一", 0.72, 0.62), player("二", 0.62, 0.46),
         player("三", 0.28, 0.62), player("游", 0.38, 0.46),
         player("左", 0.23, 0.26), player("中", 0.5, 0.16), player("右", 0.77, 0.26)]
    }
    static func player(_ label: String, _ x: Double, _ y: Double) -> FieldPlayer {
        FieldPlayer(label: label, position: FieldPoint(x: x, y: y))
    }
    static func runner(base: Int) -> FieldPlayer {
        let positions = [FieldPoint(x: 0.70, y: 0.66), FieldPoint(x: 0.5, y: 0.44), FieldPoint(x: 0.30, y: 0.66)]
        return FieldPlayer(label: "跑\(base)", position: positions[min(2, max(0, base - 1))], isRunner: true)
    }
}

struct TacticsDocument: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = "战术白板"
    var updatedAt = Date()
    var strokes: [BoardStroke] = []
    var players = FieldPlayer.defense
}

/// Full snapshots make undo cover drawing, placement, movement and deletion alike.
struct BoardHistory {
    private(set) var undoStack: [TacticsDocument] = []
    private(set) var redoStack: [TacticsDocument] = []
    mutating func checkpoint(_ document: TacticsDocument) {
        undoStack.append(document)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    mutating func undo(_ document: inout TacticsDocument) {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document); document = previous
    }
    mutating func redo(_ document: inout TacticsDocument) {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document); document = next
    }
}

struct DistanceRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    let meters: Double
    var summary: String { String(format: "%.2f 米", meters) }
}
