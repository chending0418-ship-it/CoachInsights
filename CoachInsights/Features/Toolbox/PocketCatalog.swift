import Foundation

enum PocketScene: String, CaseIterable, Identifiable {
    case personal, team, quick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "私教"
        case .team: return "团训"
        case .quick: return "随手工具"
        }
    }

    var symbol: String {
        switch self {
        case .personal: return "viewfinder"
        case .team: return "person.2"
        case .quick: return "ruler"
        }
    }

    var summary: String {
        switch self {
        case .personal: return "观察动作，留下反馈"
        case .team: return "安排训练，讲解战术"
        case .quick: return "计时、训练记录、测距离"
        }
    }

    var tools: [PocketTool] { PocketTool.allCases.filter { $0.scene == self } }
}

enum PocketTool: String, CaseIterable, Identifiable {
    case videoAnalysis, motionComparison, personalPlan, coachNotes, homeworkCard
    case teamPlan, planTimer, battingLog, bullpenLog, gameCounter
    case stopwatch, countdown, tacticsBoard, distance

    var id: String { rawValue }

    var scene: PocketScene {
        switch self {
        case .videoAnalysis, .motionComparison, .personalPlan, .coachNotes, .homeworkCard: return .personal
        case .teamPlan, .planTimer, .gameCounter, .tacticsBoard: return .team
        case .stopwatch, .countdown, .battingLog, .bullpenLog, .distance: return .quick
        }
    }

    var title: String {
        switch self {
        case .videoAnalysis: return "视频分析"
        case .motionComparison: return "动作对比"
        case .personalPlan: return "个人训练计划"
        case .coachNotes: return "教练笔记"
        case .homeworkCard: return "课后练习卡"
        case .teamPlan: return "训练计划"
        case .planTimer: return "按计划计时"
        case .battingLog: return "打击记录"
        case .bullpenLog: return "投球记录"
        case .gameCounter: return "比赛计数器"
        case .stopwatch: return "秒表"
        case .countdown: return "倒计时"
        case .tacticsBoard: return "战术白板"
        case .distance: return "测距"
        }
    }

    var symbol: String {
        switch self {
        case .videoAnalysis: return "viewfinder"
        case .motionComparison: return "rectangle.split.2x1"
        case .personalPlan, .teamPlan: return "list.bullet.clipboard"
        case .coachNotes: return "square.and.pencil"
        case .homeworkCard: return "paperplane"
        case .planTimer: return "timer"
        case .battingLog: return "figure.baseball"
        case .bullpenLog: return "scope"
        case .gameCounter: return "number"
        case .stopwatch: return "stopwatch"
        case .countdown: return "hourglass"
        case .tacticsBoard: return "pencil.and.outline"
        case .distance: return "ruler"
        }
    }

    var summary: String {
        switch self {
        case .videoAnalysis: return "慢放、逐帧与画面标注"
        case .motionComparison: return "两段视频，同步观察"
        case .personalPlan: return "自己编写，分享训练安排"
        case .coachNotes: return "记录观察与教学重点"
        case .homeworkCard: return "快速填写，分享课后练习"
        case .teamPlan: return "安排项目、顺序与时长"
        case .planTimer: return "跟随训练项目分段计时"
        case .battingLog: return "滚地、高飞等简单计数"
        case .bullpenLog: return "牛棚好坏球、出局与总球数"
        case .gameCounter: return "当前好坏球与出局数"
        case .stopwatch: return "开始、暂停、分段计时"
        case .countdown: return "设定时长，即刻开始"
        case .tacticsBoard: return "棒球场底图，随手画"
        case .distance: return "测量训练点之间的距离"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .videoAnalysis, .motionComparison, .stopwatch, .countdown, .tacticsBoard, .distance,
             .battingLog, .bullpenLog, .gameCounter: return true
        default: return false
        }
    }
}

enum ToolboxRoute: Hashable {
    case scene(PocketScene)
    case tool(PocketTool)
    #if DEBUG
    case shareExample
    #endif
}

/// Existing video sessions stay in their original store. New tools can add their
/// own record adapters when their content and persistence have been designed.
struct PocketRecord: Identifiable {
    private struct Metadata: Decodable {
        let version: Int
        let comparison: ComparisonSetup?
    }
    let id: UUID
    let name: String
    let sport: Sport?
    let createdAt: Date
    let tool: PocketTool
    let summary: String?

    var scene: PocketScene { tool.scene }

    init(id: UUID, name: String, sport: Sport?, createdAt: Date, tool: PocketTool, summary: String?) {
        self.id = id; self.name = name; self.sport = sport; self.createdAt = createdAt
        self.tool = tool; self.summary = summary
    }

    init(session: AnalysisSession) {
        id = session.id
        name = session.name
        sport = session.sport
        createdAt = session.createdAt
        summary = nil
        // Listing records must not materialize every frame of saved pose results.
        let metadata = try? JSONDecoder().decode(Metadata.self, from: session.snapshotData)
        tool = session.version == 1 && metadata?.version == 1 && metadata?.comparison != nil
            ? .motionComparison : .videoAnalysis
    }

    init(board: TacticsDocument) {
        id = board.id; name = board.title; sport = nil; createdAt = board.updatedAt
        tool = .tacticsBoard; summary = "\(board.players.count) 位球员 · \(board.strokes.count) 笔手绘"
    }
    init(distance: DistanceRecord) {
        id = distance.id; name = distance.summary; sport = nil; createdAt = distance.createdAt
        tool = .distance; summary = "AR 估算距离 · 请复核"
    }
}

struct PocketRecordFilter {
    var scene: PocketScene?
    var tool: PocketTool?

    var tools: [PocketTool] { scene?.tools ?? PocketTool.allCases }

    mutating func selectScene(_ value: PocketScene?) {
        scene = value
        if let tool, let value, tool.scene != value { self.tool = nil }
    }

    func includes(_ record: PocketRecord) -> Bool {
        (scene == nil || scene == record.scene) && (tool == nil || tool == record.tool)
    }
}
