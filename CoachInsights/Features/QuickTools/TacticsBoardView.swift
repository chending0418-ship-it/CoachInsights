import SwiftUI
import Photos

extension BoardInk {
    var color: Color {
        switch self {
        case .burgundy: return Theme.burgundy
        case .white: return .white
        case .yellow: return Color(red: 0.85, green: 0.61, blue: 0.16)
        case .red: return Color(red: 0.74, green: 0.27, blue: 0.32)
        case .blue: return Color(red: 0.25, green: 0.50, blue: 0.62)
        }
    }
    var title: String {
        switch self {
        case .burgundy: return "酒红"
        case .white: return "白色"
        case .yellow: return "黄色"
        case .red: return "红色"
        case .blue: return "蓝色"
        }
    }
}

struct TacticsBoardView: View {
    private enum Mode { case select, draw, route }
    @EnvironmentObject private var tools: QuickToolsStore
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID?
    @State private var document = TacticsDocument()
    @State private var history = BoardHistory()
    @State private var ink = BoardInk.burgundy
    @State private var mode = Mode.select
    @State private var points: [FieldPoint] = []
    @State private var selectedPlayer: UUID?
    @State private var moveOrigin: TacticsDocument?
    @State private var clearConfirmation = false
    @State private var notice: String?
    @State private var saving = false
    @State private var initialized = false

    var body: some View {
        GeometryReader { bounds in
            let rotate = bounds.size.height > bounds.size.width
            boardContent
                .frame(width: rotate ? bounds.size.height : bounds.size.width,
                       height: rotate ? bounds.size.width : bounds.size.height)
                .rotationEffect(.degrees(rotate ? 90 : 0))
                .frame(width: bounds.size.width, height: bounds.size.height)
        }
        .background(Theme.paper)
        .background(LandscapeToolOrientation().frame(width: 0, height: 0))
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .statusBarHidden().preferredColorScheme(.light)
        .onAppear {
            guard !initialized else { return }; initialized = true
            if let recordID, let existing = tools.state.boards.first(where: { $0.id == recordID }) { document = existing }
            else if recordID == nil, let recent = tools.state.boards.max(by: { $0.updatedAt < $1.updatedAt }) { document = recent }
        }
        .onChange(of: mode) { _, _ in points = []; moveOrigin = nil }
        .confirmationDialog("清空手绘和所有球员？", isPresented: $clearConfirmation, titleVisibility: .visible) {
            Button("清空白板", role: .destructive) {
                history.checkpoint(document); document.strokes.removeAll(); document.players.removeAll(); selectedPlayer = nil; save()
            }
        }
    }

    private var boardContent: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let width = min(geometry.size.width, geometry.size.height * 1.6)
                let height = width / 1.6
                ZStack {
                    field(width: width, height: height)
                        .frame(width: width, height: height)
                        .accessibilityElement(children: .contain).accessibilityIdentifier("tacticsField")
                        .accessibilityValue("横屏棒球场 · " + (mode == .select ? "选择球员" : mode == .draw ? "画笔" : "路线"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack {
                        topBar
                        Spacer(minLength: 0)
                    }
                    HStack {
                        toolRail(compact: geometry.size.height < 480)
                        Spacer(minLength: 0)
                    }.padding(.leading, 10)
                }
            }
            bottomBar
            if let notice {
                Text(notice).font(.caption).foregroundStyle(Theme.burgundy).padding(5)
                    .frame(maxWidth: .infinity).accessibilityIdentifier("boardNotice")
            }
            QuickSaveIssueView()
        }.background(Theme.paper)
    }

    private func field(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            BoardArtwork(document: document, draft: BoardStroke(points: points, ink: ink, isArrow: mode == .route))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = FieldPoint(x: value.location.x / width, y: value.location.y / height)
                        if mode == .route {
                            if let start = points.first { points = [start, point] } else { points = [point] }
                        } else if points.count < 6000 { points.append(point) }
                    }
                    .onEnded { _ in
                        guard !points.isEmpty else { return }
                        history.checkpoint(document)
                        document.strokes.append(BoardStroke(points: points, ink: ink, isArrow: mode == .route))
                        points = []; save()
                    }, including: mode == .select ? .none : .all)
            ForEach(document.players) { player in playerHandle(player, width: width, height: height) }
        }.coordinateSpace(name: "tacticsFieldCoordinates")
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("返回").accessibilityIdentifier("boardBack")
            Text("战术白板").font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Button { export() } label: {
                if saving { ProgressView().frame(width: 104, height: 44) }
                else { Label("保存图片", systemImage: "square.and.arrow.down").font(.subheadline).padding(.horizontal, 12).frame(height: 44).contentShape(Rectangle()) }
            }.disabled(saving).accessibilityIdentifier("boardSaveImage")
                .background(.white.opacity(0.92), in: Capsule())
                .overlay { Capsule().stroke(Theme.burgundy.opacity(0.10)) }
        }.foregroundStyle(Theme.burgundy).buttonStyle(.plain).padding(.horizontal, 8)
    }

    private func toolRail(compact: Bool) -> some View {
        VStack(spacing: 2) {
            railButton("选择", symbol: "cursorarrow", selected: mode == .select, id: "boardSelect", compact: compact) { mode = .select }
            railButton("画笔", symbol: "pencil.tip", selected: mode == .draw, id: "boardDraw", compact: compact) { mode = .draw }
            railButton("撤销", symbol: "arrow.uturn.backward", id: "boardUndo", compact: compact) {
                history.undo(&document); selectedPlayer = nil; save()
            }.disabled(history.undoStack.isEmpty)
            railButton("清除", symbol: "eraser", id: "boardClear", compact: compact) { clearConfirmation = true }
        }
        .padding(4).background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.burgundy.opacity(0.13), lineWidth: 1) }
    }

    private func railButton(_ title: String, symbol: String, selected: Bool = false, id: String, compact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: compact ? 2 : 6) {
                Image(systemName: symbol).font(.system(size: compact ? 18 : 22))
                Text(title).font(.system(size: compact ? 10 : 12))
            }.frame(width: compact ? 44 : 52, height: compact ? 44 : 58)
                .foregroundStyle(selected ? Theme.burgundy : Theme.burgundy.opacity(0.65))
                .background(selected ? Theme.rose.opacity(0.48) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Menu {
                Button("放置全体防守队员") {
                    history.checkpoint(document)
                    document.players.removeAll { !$0.isRunner }; document.players += FieldPlayer.defense
                    mode = .select; save()
                }
                ForEach(FieldPlayer.defense, id: \.label) { player in Button("防守 · " + player.label) { add(player) } }
            } label: { Label("防守阵容", systemImage: "person.3").frame(minHeight: 44).padding(.horizontal, 8).contentShape(Rectangle()) }
                .accessibilityIdentifier("boardDefense")
            Menu {
                ForEach(1...3, id: \.self) { base in Button("\(base) 垒跑者") { add(FieldPlayer.runner(base: base)) } }
            } label: { Label("跑者", systemImage: "figure.run").frame(minHeight: 44).padding(.horizontal, 8).contentShape(Rectangle()) }
                .accessibilityIdentifier("boardRunners")
            Button { mode = .route } label: {
                Label("路线", systemImage: "arrow.up.right").frame(minHeight: 44).padding(.horizontal, 8)
                    .background(mode == .route ? Theme.rose.opacity(0.48) : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
            }.accessibilityIdentifier("boardRoute")
            if mode != .select {
                Menu {
                    ForEach(BoardInk.allCases, id: \.self) { value in Button(value.title) { ink = value } }
                } label: { Circle().fill(ink.color).frame(width: 18, height: 18).overlay { Circle().stroke(Theme.burgundy.opacity(0.20)) }.frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("画笔颜色").accessibilityIdentifier("boardInk")
            }
            if selectedPlayer != nil && mode == .select {
                Button {
                    history.checkpoint(document); document.players.removeAll { $0.id == selectedPlayer }; selectedPlayer = nil; save()
                } label: { Image(systemName: "person.fill.xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("移除选中球员").accessibilityIdentifier("boardRemovePlayer")
            }
            Spacer(minLength: 0)
            Button { history.redo(&document); save() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .disabled(history.redoStack.isEmpty).accessibilityLabel("重做").accessibilityIdentifier("boardRedo")
            Menu {
                Button("清空白板", role: .destructive) { clearConfirmation = true }
                Button("新建白板") {
                    document = TacticsDocument(); history = BoardHistory(); selectedPlayer = nil; notice = nil; save()
                }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("白板选项").accessibilityIdentifier("boardOptions")
        }.font(.subheadline).foregroundStyle(Theme.burgundy).buttonStyle(.plain)
            .padding(.horizontal, 10).frame(height: 50).background(.white.opacity(0.62))
            .overlay(alignment: .top) { Divider().overlay(Theme.burgundy.opacity(0.08)) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("boardTools")
    }

    private func playerHandle(_ player: FieldPlayer, width: CGFloat, height: CGFloat) -> some View {
        let radius = max(11, height * 0.038)
        let outline: Color = selectedPlayer == player.id && mode == .select ? Theme.burgundy.opacity(0.55) : .clear
        let drag = DragGesture(minimumDistance: 2, coordinateSpace: .named("tacticsFieldCoordinates"))
            .onChanged { value in movePlayer(player.id, translation: value.translation, width: width, height: height) }
            .onEnded { value in
                movePlayer(player.id, translation: value.translation, width: width, height: height)
                finishPlayerMove()
            }
        return Circle().stroke(outline, lineWidth: 1.5)
            .frame(width: max(44, radius * 2 + 8), height: max(44, radius * 2 + 8)).contentShape(Circle())
            .position(x: CGFloat(player.position.x) * width, y: CGFloat(player.position.y) * height)
            .onTapGesture { selectedPlayer = player.id }
            .highPriorityGesture(drag)
            .allowsHitTesting(mode == .select)
            .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
            .accessibilityLabel((player.isRunner ? "跑者 " : "防守 ") + player.label).accessibilityIdentifier("boardPlayer_" + player.label)
    }
    private func finishPlayerMove() {
        if let original = moveOrigin { history.checkpoint(original) }
        moveOrigin = nil
        save()
    }
    private func movePlayer(_ id: UUID, translation: CGSize, width: CGFloat, height: CGFloat) {
        if moveOrigin == nil { moveOrigin = document }
        selectedPlayer = id
        guard let original = moveOrigin?.players.first(where: { $0.id == id }),
              let index = document.players.firstIndex(where: { $0.id == id }) else { return }
        let x = original.position.x + Double(translation.width / width)
        let y = original.position.y + Double(translation.height / height)
        document.players[index].position = FieldPoint(x: x, y: y)
    }
    private func add(_ player: FieldPlayer) {
        guard !document.players.contains(where: { $0.label == player.label && $0.isRunner == player.isRunner }) else {
            mode = .select; selectedPlayer = document.players.first(where: { $0.label == player.label })?.id; return
        }
        history.checkpoint(document); document.players.append(player); selectedPlayer = player.id; mode = .select; save()
    }
    private func save() { notice = nil; tools.saveBoard(document) }
    private func export() {
        save(); saving = true
        let renderer = ImageRenderer(content: BoardArtwork(document: document).frame(width: 1600, height: 1000))
        renderer.scale = 1
        guard let image = renderer.uiImage else { saving = false; notice = "图片生成失败，请重试。"; return }
        Task {
            do { try await BoardPhotos.save(image); notice = "已保存到相册" }
            catch { notice = error.localizedDescription }
            saving = false
        }
    }
}

struct BoardArtwork: View {
    let document: TacticsDocument
    var draft: BoardStroke?
    var body: some View {
        Canvas { context, size in
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
            let home = p(0.5, 0.88), first = p(0.70, 0.66), second = p(0.5, 0.44), third = p(0.30, 0.66)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.paper))
            // Project one circular outfield through the same axes as the
            // diamond, so both foul lines pass through their corner bases.
            let fenceScale = 2.4
            let radiusX = (first.x - home.x) * fenceScale * sqrt(2)
            let radiusY = (home.y - first.y) * fenceScale * sqrt(2)
            let fencePoints = (0...64).map { step in
                let angle = -Double.pi / 4 + Double(step) / 64 * Double.pi / 2
                return CGPoint(x: home.x + radiusX * sin(angle), y: home.y - radiusY * cos(angle))
            }
            let fence = Path { path in path.addLines(fencePoints) }
            var field = Path(); field.move(to: home)
            for point in fencePoints { field.addLine(to: point) }
            field.closeSubpath()
            context.fill(field, with: .color(Theme.rose.opacity(0.08)))
            let lineColor = Theme.burgundy.opacity(0.30)
            let lineWidth = max(1, size.height * 0.0018)
            context.stroke(fence, with: .color(lineColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            let foulLines = Path { path in
                for base in [third, first] {
                    path.move(to: home)
                    path.addLine(to: CGPoint(x: home.x + (base.x - home.x) * 2.45, y: home.y + (base.y - home.y) * 2.45))
                }
            }
            context.stroke(foulLines, with: .color(lineColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            let diamond = Path { path in path.addLines([home, first, second, third]); path.closeSubpath() }
            context.fill(diamond, with: .color(Theme.rose.opacity(0.16)))
            // Home-to-first/third are already part of the foul lines.
            let innerBaseLines = Path { path in path.addLines([first, second, third]) }
            context.stroke(innerBaseLines, with: .color(lineColor), lineWidth: lineWidth)
            var centerLine = Path(); centerLine.move(to: second); centerLine.addLine(to: home)
            context.stroke(centerLine, with: .color(Theme.burgundy.opacity(0.12)), style: StrokeStyle(lineWidth: lineWidth, dash: [5, 5]))
            let radius = size.height * 0.028
            context.stroke(Path(ellipseIn: CGRect(x: size.width * 0.5 - radius, y: size.height * 0.65 - radius, width: radius * 2, height: radius * 2)), with: .color(lineColor), lineWidth: lineWidth)
            for base in [first, second, third] {
                let r = size.height * 0.011
                let shape = Path { path in
                    path.addLines([CGPoint(x: base.x, y: base.y - r), CGPoint(x: base.x + r, y: base.y), CGPoint(x: base.x, y: base.y + r), CGPoint(x: base.x - r, y: base.y)])
                    path.closeSubpath()
                }
                context.fill(shape, with: .color(Theme.burgundy.opacity(0.38)))
            }
            let plate = Path { path in
                let r = size.height * 0.015
                path.move(to: CGPoint(x: home.x - r, y: home.y - r)); path.addLine(to: CGPoint(x: home.x + r, y: home.y - r))
                path.addLine(to: CGPoint(x: home.x + r, y: home.y)); path.addLine(to: CGPoint(x: home.x, y: home.y + r)); path.addLine(to: CGPoint(x: home.x - r, y: home.y)); path.closeSubpath()
            }
            context.fill(plate, with: .color(Theme.burgundy.opacity(0.42)))
            for stroke in document.strokes + (draft.map { [$0] } ?? []) {
                guard let start = stroke.points.first else { continue }
                var path = Path(); path.move(to: p(start.x, start.y))
                for point in stroke.points.dropFirst() { path.addLine(to: p(point.x, point.y)) }
                if stroke.points.count == 1 { path.addLine(to: p(start.x + 0.001, start.y + 0.001)) }
                let width = max(1.5, size.height * 0.004)
                // A faint outline keeps legacy white strokes visible on paper.
                if stroke.ink == .white { context.stroke(path, with: .color(Theme.burgundy.opacity(0.18)), style: StrokeStyle(lineWidth: width + 2, lineCap: .round, lineJoin: .round)) }
                context.stroke(path, with: .color(stroke.ink.color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                if stroke.isArrow == true, stroke.points.count >= 2 {
                    let end = stroke.points.last!, before = stroke.points[stroke.points.count - 2]
                    let a = p(before.x, before.y), b = p(end.x, end.y), angle = atan2(b.y - a.y, b.x - a.x)
                    if hypot(b.x - a.x, b.y - a.y) > 1 {
                        let length = size.height * 0.025
                        var head = Path(); head.move(to: CGPoint(x: b.x - cos(angle - 0.5) * length, y: b.y - sin(angle - 0.5) * length))
                        head.addLine(to: b); head.addLine(to: CGPoint(x: b.x - cos(angle + 0.5) * length, y: b.y - sin(angle + 0.5) * length))
                        if stroke.ink == .white { context.stroke(head, with: .color(Theme.burgundy.opacity(0.18)), style: StrokeStyle(lineWidth: width + 2, lineCap: .round, lineJoin: .round)) }
                        context.stroke(head, with: .color(stroke.ink.color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            for player in document.players {
                let center = p(player.position.x, player.position.y), r = max(11, size.height * 0.038)
                let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                context.fill(circle, with: .color(player.isRunner ? Theme.paper : Theme.burgundy.opacity(0.88)))
                context.stroke(circle, with: .color(player.isRunner ? Theme.burgundy.opacity(0.68) : Theme.paper), lineWidth: max(1.5, size.height * 0.0025))
                context.draw(Text(player.label).font(.system(size: max(11, r * (player.isRunner ? 0.72 : 0.95)), weight: .medium)).foregroundColor(player.isRunner ? Theme.burgundy : .white), at: center)
            }
            context.draw(Text("棒球训练助手 · 战术白板").font(.system(size: max(9, size.height * 0.018))).foregroundColor(Theme.burgundy.opacity(0.45)), at: p(0.82, 0.96))
        }
    }
}

enum BoardPhotos {
    enum Failure: LocalizedError {
        case permission
        var errorDescription: String? { "未获相册写入权限，请在系统设置中允许棒球训练助手添加照片。" }
    }
    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.permission }
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
    }
}
