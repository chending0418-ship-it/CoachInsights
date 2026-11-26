import SwiftUI

struct FieldLogView: View {
    @EnvironmentObject private var store: FieldToolsStore
    let kind: FieldLogKind
    var recordID: UUID? = nil
    @State private var reset = false
    @State private var ending = false
    @State private var notice: String?
    @AppStorage("bullpen.viewpoint") private var viewpoint = PitchViewpoint.catcher
    @State private var reviewingPitches = false
    @State private var correction: PitchSelection?
    @State private var editingGameCount = false
    @State private var visibleEventLimit = 30
    @State private var showsProcess = false
    @State private var name = ""
    @FocusState private var editingName: Bool
    @State private var history = false
    private struct PitchSelection: Identifiable { let id: Int; let mark: PitchMark; let number: Int }
    private var log: FieldLog? { store.log(kind: kind, id: recordID) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let log {
                    scorebook(log, width: geometry.size.width, height: geometry.size.height)
                } else {
                    ContentUnavailableView("记录已不存在", systemImage: "folder.badge.questionmark")
                }
            }
            .scrollDismissesKeyboard(kind == .batting ? .interactively : .automatic)
        }
        .background(Theme.paper).navigationTitle(kind.tool.title).navigationBarTitleDisplayMode(.inline)
        .task(id: log?.id) {
            name = log?.name ?? ""
            showsProcess = false
            visibleEventLimit = 30
        }
        .onChange(of: name) { _, value in
            let limited = String(value.prefix(100))
            if limited != value { name = limited; return }
            if let log, log.name != value { change { $0.name = value } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let issue = store.issue {
                VStack(spacing: 8) {
                    Text(issue).font(.callout).foregroundStyle(.red).accessibilityIdentifier("fieldIssue")
                    Button("重试读取") { store.reload() }
                }.padding(12).frame(maxWidth: .infinity).background(Theme.paper)
                }
            }
        }
        .confirmationDialog("清零本轮计数？可撤销恢复。", isPresented: $reset, titleVisibility: .visible) {
            Button("清零本轮", role: .destructive) { change { $0.clear() } }
        }
        .confirmationDialog("保存本轮并开始新的一轮？", isPresented: $ending, titleVisibility: .visible) {
            Button("保存并结束本轮") {
                if let log, save(log, ending: true) { notice = "本轮已保存到记录" }
            }
        }
        .sheet(isPresented: $history) {
            NavigationStack {
                List {
                    let rounds = store.state.records.filter { $0.kind == kind }
                    if rounds.isEmpty { Text("已加入记录的轮次会显示在这里。").foregroundStyle(.secondary) }
                    ForEach(rounds) { round in
                        NavigationLink(value: round.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(round.title).font(.headline)
                                Text(round.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.notebookForm().navigationTitle("历史轮次")
                    .navigationDestination(for: UUID.self) { id in FieldLogView(kind: kind, recordID: id) }
                    .toolbar { Button("完成") { history = false } }
            }
        }
        .sheet(isPresented: $editingGameCount) {
            if let log {
                GameCountEditor(count: log.gameCount.correction) { correction in
                    change { $0.append(.gameCorrection(correction)) }
                }
            }
        }
        .navigationDestination(isPresented: $reviewingPitches) {
            if let log { PitchReviewView(pitches: log.pitches, viewpoint: $viewpoint, roundName: log.name, ended: log.ended) }
        }
        .notebookDestination(item: $correction) { selection in
            PitchCorrectionView(mark: selection.mark, context: log?.pitches ?? [], number: selection.number, viewpoint: $viewpoint) { mark in
                change { $0.correctPitch(at: selection.id, zone: mark.zone, isStrike: mark.isStrike, location: mark.location) }
            }
        }
    }

    private func scorebook(_ log: FieldLog, width: CGFloat, height: CGFloat) -> some View {
        let wide = width >= 700
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    let placeholder = kind == .game ? "队内模拟赛" : kind == .bullpen ? "牛棚投球" : "前抛打击练习"
                    TextField(placeholder, text: $name, prompt: Text(placeholder).foregroundStyle(Notebook.ink))
                        .font(.system(size: wide ? 32 : 25, weight: .bold)).textFieldStyle(.plain)
                        .focused($editingName).submitLabel(.done).onSubmit { editingName = false }
                        .disabled(log.ended).accessibilityIdentifier("fieldName")
                    Text(log.createdAt.formatted(.dateTime.month().day()) + " · 本机记录")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Circle().fill(Notebook.fieldGreen).frame(width: 6, height: 6)
                    Text(log.ended ? "已结束" : store.state.records.contains(where: { $0.id == log.id }) ? "已加入记录" : log.events.isEmpty && name.isEmpty ? "新一轮" : "草稿已保存")
                }.font(.caption).foregroundStyle(Notebook.fieldGreen).padding(.top, 10)
                if kind == .bullpen && wide { metrics(log).frame(width: min(480, width * 0.46)) }
                Menu {
                    Button("修改名称", systemImage: "pencil") { editingName = true }.disabled(log.ended)
                    Button("清零本轮", systemImage: "arrow.counterclockwise", role: .destructive) { reset = true }.disabled(log.ended || log.events.isEmpty)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 36, height: 36)
                        .overlay { Circle().strokeBorder(Notebook.rule) }.frame(width: 44, height: 44)
                }.accessibilityLabel("本轮选项").accessibilityIdentifier("fieldOptions")
            }
            if kind == .bullpen && !wide { metrics(log) }
            if wide {
                HStack(alignment: .top, spacing: 22) {
                    playArea(log, wide: true, height: height).frame(maxWidth: .infinity)
                    roundProcess(log, wide: true).frame(width: min(350, width * 0.32))
                }
            } else {
                playArea(log, wide: false, height: height)
                roundProcess(log, wide: false)
            }
        }.padding(.horizontal, width >= 650 ? 26 : 14).padding(.vertical, 16)
            .frame(maxWidth: 1120).frame(maxWidth: .infinity).foregroundStyle(Notebook.ink)
    }

    private func metrics(_ log: FieldLog) -> some View {
                HStack(spacing: 0) {
                    pitchMetric("总球数", value: "\(log.pitches.count)", color: Notebook.ink, total: true)
                    pitchMetric("好球", value: "\(log.strikeCount)", color: Theme.burgundy)
                    pitchMetric("坏球", value: "\(log.pitches.count - log.strikeCount)", color: Notebook.fieldGreen)
                    pitchMetric("好球率", value: log.strikeRateText, color: Theme.burgundy)
                    pitchMetric("出局", value: "\(log.outCount)", color: Notebook.ink)
                }.padding(.vertical, 8).overlay(alignment: .top) { Divider() }.overlay(alignment: .bottom) { Divider() }
    }

    private func playArea(_ log: FieldLog, wide: Bool, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch kind {
            case .batting: battingControls(log, wide: wide)
            case .game: gameControls(log)
            case .bullpen: pitchControls(log, height: height, wide: wide)
            }
            if log.ended {
                Button("继续编辑") {
                    var draft = log
                    draft.ended = false
                    if store.update(draft) { notice = nil }
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("fieldResume")
            } else {
                HStack(spacing: 8) {
                    Button { undo(log) } label: {
                        Label("撤销", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 44)
                            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Notebook.rule) }
                    }.disabled(log.undoHistory.isEmpty).accessibilityIdentifier("fieldUndo")
                    if kind == .bullpen {
                        Button { change { $0.append(.bullpenOut) } } label: {
                            Text("出局 +1").frame(maxWidth: .infinity, minHeight: 44)
                                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Notebook.rule) }
                        }.accessibilityIdentifier("bullpenOut").disabled(log.events.count >= FieldLog.eventLimit)
                    }
                    Button { if save(log) { notice = "已保存到记录" } } label: {
                        Label("加入记录", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 12).foregroundStyle(.white)
                            .background(Theme.burgundy, in: RoundedRectangle(cornerRadius: 7))
                    }.disabled(log.events.isEmpty).accessibilityIdentifier("fieldSave")
                }.font(.subheadline.bold()).buttonStyle(.plain)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(Notebook.fieldGreen).accessibilityIdentifier("fieldNotice") }
        }
    }

    private func roundProcess(_ log: FieldLog, wide: Bool) -> some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                let heading = HStack {
                    Text(kind == .bullpen ? "本轮球序" : "本轮过程").font(.headline).accessibilityIdentifier("fieldProcess")
                    Spacer()
                    Text("\(log.events.count) 条").foregroundStyle(.secondary)
                    if !wide { Image(systemName: showsProcess ? "chevron.down" : "arrow.right").foregroundStyle(.secondary) }
                }.font(.subheadline).padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
                if wide { heading } else { Button { showsProcess.toggle() } label: { heading }.buttonStyle(.plain) }
                if wide || showsProcess {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) { recentEvents(log) }.padding(.horizontal, 12)
                }
            }.background(Notebook.paper, in: RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Notebook.rule) }
            if kind == .bullpen && !log.pitches.isEmpty {
                Button("逐球回看", systemImage: "play") { reviewingPitches = true }
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("pitchReplay")
            }
            Divider()
            HStack(spacing: 8) {
                Button { history = true } label: { Label("历史轮次", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity, minHeight: 44) }
                if !log.ended {
                    Button { ending = true } label: { Label("结束本轮", systemImage: "flag").frame(maxWidth: .infinity, minHeight: 44) }
                        .disabled(log.events.isEmpty).accessibilityIdentifier("fieldEnd")
                }
            }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.burgundy).buttonStyle(.plain)
        }
    }

    private func pitchControls(_ log: FieldLog, height: CGFloat, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading("投球落点", detail: log.ended ? "本轮已结束" : "点图记一球")
            PitchLocationMap(pitches: log.pitches, viewpoint: viewpoint, ratio: wide ? 1.18 : 1.23) { point in
                change { $0.append(.pitch(PitchMark(point: point))) }
            }
            .frame(maxWidth: wide ? 520 : 440)
            .frame(maxWidth: .infinity)
            .disabled(log.ended || log.events.count >= FieldLog.eventLimit)
            HStack(spacing: 12) {
                Label("好球", systemImage: "circle.fill").foregroundStyle(PitchLocationMap.strikeColor)
                Label("坏球", systemImage: "circle").foregroundStyle(PitchLocationMap.ballColor)
                Spacer()
                if let last = log.pitches.last { Text("第 \(log.pitches.count) 球 · " + viewpoint.title(for: last.zone)) }
            }.font(.caption)
            PitchViewpointPicker(viewpoint: $viewpoint).accessibilityIdentifier("pitchViewpoint")
        }
    }

    private func battingControls(_ log: FieldLog, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text("总挥棒数").font(.headline)
                Spacer()
                Text("\(log.events.count)").font(.system(size: 44, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.burgundy)
                Text("次").font(.subheadline).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("battingTotal")
            Divider()
            sectionHeading("击球结果", detail: log.ended ? "本轮已结束" : "点选一次，记录一棒")
            VStack(spacing: 9) {
                HStack(spacing: 9) {
                    contactCard(.ground, log: log, wide: wide)
                    contactCard(.line, log: log, wide: wide)
                }
                HStack(spacing: 9) {
                    contactCard(.fly, log: log, wide: wide)
                    contactCard(.miss, log: log, wide: wide)
                }
            }.disabled(log.ended || log.events.count >= FieldLog.eventLimit)
        }
    }

    private func contactCard(_ contact: BattingContact, log: FieldLog, wide: Bool) -> some View {
        Button { change { $0.append(.batting(contact)) } } label: {
            GeometryReader { geometry in
                ZStack(alignment: .bottomTrailing) {
                    BattingContactIcon(contact: contact)
                        .frame(width: geometry.size.width * 0.59).padding(.trailing, 7).padding(.bottom, 10)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(contact.title).font(.headline)
                            Spacer()
                            Image(systemName: "plus").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(log.count(contact))").font(.system(size: 31, weight: .semibold, design: .monospaced))
                    }.padding(12)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(height: wide ? 143 : 116)
                .background(Color(red: 0.965, green: 0.957, blue: 0.918), in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Notebook.rule) }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(contact.title).accessibilityValue("\(log.count(contact))")
            .accessibilityIdentifier("batting_" + contact.rawValue)
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 4)
    }

    private func gameControls(_ log: FieldLog) -> some View {
        let count = log.gameCount
        return VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                HStack {
                    Text("队内比分"); Spacer()
                    Text("第 \(count.sides / 2 + 1) 局" + (count.sides.isMultiple(of: 2) ? "上" : "下"))
                        .accessibilityLabel("已换边 \(count.sides) 次").accessibilityIdentifier("gameSides")
                }.font(.subheadline.weight(.medium)).padding(.horizontal, 13).padding(.vertical, 9)
                Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
                HStack(spacing: 0) {
                    scoreTile("客队", value: count.awayRuns, add: .awayRun, subtract: .removeAwayRun)
                    Text(":").font(.system(size: 32, design: .monospaced)).foregroundStyle(.white.opacity(0.72))
                    scoreTile("主队", value: count.homeRuns, add: .homeRun, subtract: .removeHomeRun)
                }.padding(.vertical, 13)
            }.foregroundStyle(.white).background(Color(red: 61/255, green: 81/255, blue: 72/255), in: RoundedRectangle(cornerRadius: 9))
            sectionHeading("当前打席", detail: log.ended ? "本轮已结束" : "点选项目 +1")
            HStack(spacing: 7) {
                gameButton("B 坏球", value: count.balls, maximum: 3, action: .ball)
                gameButton("S 好球", value: count.strikes, maximum: 2, action: .strike)
                gameButton("O 出局", value: count.outs, maximum: 2, action: .out)
            }.accessibilityElement(children: .contain).accessibilityIdentifier("gameCount")
            HStack {
                Button { editingGameCount = true } label: { Label("修正计数", systemImage: "pencil").frame(maxWidth: .infinity, minHeight: 44) }
                    .accessibilityIdentifier("gameEditCount")
                Button { change { $0.append(.game(.clearBatter)) } } label: { Label("下一位打者", systemImage: "forward.end").frame(maxWidth: .infinity, minHeight: 44) }
                    .accessibilityIdentifier("gameNextBatter")
            }.font(.subheadline.bold()).foregroundStyle(Theme.burgundy).buttonStyle(.plain)
            if let notice = count.notice { Text(notice).font(.caption.weight(.semibold)).foregroundStyle(Theme.burgundy).accessibilityIdentifier("gameBoundary") }
        }.disabled(log.ended || log.events.count >= FieldLog.eventLimit)
    }

    private func scoreTile(_ title: String, value: Int, add: GameAction, subtract: GameAction) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Button { change { $0.append(.game(subtract)) } } label: {
                Image(systemName: "minus.circle").font(.caption).frame(width: 35, height: 44).contentShape(Rectangle())
            }.disabled(value == 0).opacity(value == 0 ? 0.25 : 0.7)
                .accessibilityLabel(subtract.title).accessibilityIdentifier("game_" + subtract.rawValue)
            Button { change { $0.append(.game(add)) } } label: {
                HStack(alignment: .bottom, spacing: 2) {
                    VStack(spacing: 2) {
                        Text(title).font(.subheadline)
                        Text(String(format: "%02ld", value)).font(.system(size: 51, weight: .medium, design: .monospaced))
                            .minimumScaleFactor(0.4).lineLimit(1)
                    }.frame(maxWidth: .infinity)
                    Image(systemName: "plus.circle").font(.body).padding(.bottom, 5)
                }.padding(.trailing, 7).contentShape(Rectangle())
            }.accessibilityLabel(add.title).accessibilityValue("\(value)").accessibilityIdentifier("game_" + add.rawValue)
        }.buttonStyle(.plain)
    }

    private func gameButton(_ title: String, value: Int, maximum: Int, action: GameAction) -> some View {
        Button { change { $0.append(.game(action)) } } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(value)").font(.system(size: 31, weight: .semibold, design: .monospaced))
                HStack(spacing: 4) {
                    ForEach(0..<maximum, id: \.self) { index in
                        Circle().fill(index < value ? (action == .strike ? Theme.burgundy : Notebook.fieldGreen) : Color.clear)
                            .overlay { Circle().strokeBorder(index < value ? Color.clear : .secondary) }.frame(width: 7, height: 7)
                    }
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Notebook.inset, in: RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Notebook.rule) }
        }.buttonStyle(.plain).accessibilityLabel(action.title).accessibilityValue("\(value)").accessibilityIdentifier("game_" + action.rawValue)
    }

    private func pitchMetric(_ title: String, value: String, color: Color, total: Bool = false) -> some View {
        VStack(spacing: 6) {
            if total {
                Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(color)
                    .accessibilityLabel(value + " 球").accessibilityIdentifier("bullpenTotal")
            } else { Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(color) }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private func recentEvents(_ log: FieldLog) -> some View {
        if log.events.isEmpty { Text("从上方按钮开始记录").foregroundStyle(.secondary).padding(.vertical, 20) }
        ForEach(Array(log.events.indices.suffix(visibleEventLimit).reversed()), id: \.self) { index in
            let event = log.events[index]
            HStack {
                if case .pitch(let mark) = event {
                    let number = log.events.prefix(index + 1).filter { if case .pitch = $0 { return true }; return false }.count
                    Text("\(number)").font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(mark.isStrike ? PitchLocationMap.strikeColor : PitchLocationMap.ballColor, in: Circle())
                    Button {
                        correction = PitchSelection(id: index, mark: mark, number: number)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mark.isStrike ? "好球" : "坏球").font(.headline)
                                Text(viewpoint.title(for: mark.zone)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "pencil.circle")
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.disabled(log.ended).accessibilityIdentifier("pitchEvent_\(index)")
                } else {
                    if kind != .bullpen { Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36) }
                    Text(eventTitle(event)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            Divider()
        }
        if log.events.count > visibleEventLimit {
            Button("显示更早的记录") { visibleEventLimit += 30 }.accessibilityIdentifier("fieldEarlierEvents")
        }
    }

    private func eventTitle(_ event: FieldEvent) -> String {
        switch event {
        case .batting(let contact): return contact.title
        case .bullpenOut: return "出局 +1"
        case .pitch(let mark): return viewpoint.title(for: mark.zone)
        case .game(let action): return action.title
        case .gameCorrection(let count):
            return "修正计数 · 客 \(count.awayRuns) 比 \(count.homeRuns) 主 · 好球 \(count.strikes) · 坏球 \(count.balls) · 出局 \(count.outs)"
        }
    }
    @discardableResult private func change(_ mutate: (inout FieldLog) -> Void) -> Bool {
        guard let old = log, !old.ended else { return false }
        var next = old; next.name = name; mutate(&next)
        guard next != old else { return true }
        guard store.update(next) else { return false }
        notice = nil; return true
    }
    private func undo(_ log: FieldLog) {
        var next = log; next.name = name
        next.undo()
        if store.update(next) { notice = "已撤销" }
    }
    private func save(_ log: FieldLog, ending: Bool = false) -> Bool {
        var next = log; next.name = name
        return store.save(next, ending: ending)
    }
}

private struct PitchCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State var mark: PitchMark
    @State private var issue: String?
    var context: [PitchMark] = []
    let number: Int
    @Binding var viewpoint: PitchViewpoint
    let save: (PitchMark) -> Bool
    private var displayed: [PitchMark] {
        var result = context
        guard result.indices.contains(number - 1) else { return [mark] }
        result[number - 1] = mark
        return result
    }
    var body: some View {
        Group {
            ScrollView {
                VStack(spacing: 20) {
                    NotebookHeading(title: "修正第 \(number) 球", detail: "本轮共 \(displayed.count) 球")
                    NotebookColumns {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("投球落点", value: "点图移动此球")
                            PitchLocationMap(pitches: displayed, viewpoint: viewpoint, correcting: true, sequence: number, selectedIndex: displayed.count == 1 ? 0 : number - 1, ratio: 1.25) { point in
                                mark.location = point; mark.zone = .at(point)
                            }
                            PitchViewpointPicker(viewpoint: $viewpoint).accessibilityIdentifier("correctionViewpoint")
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                LabeledContent("本球判定", value: viewpoint.title(for: mark.zone))
                                Picker("判定", selection: $mark.isStrike) {
                                    Text("好球").tag(true); Text("坏球").tag(false)
                                }.pickerStyle(.segmented).accessibilityIdentifier("pitchStrikeToggle")
                                Text("移动落点后保留当前判定。").font(.caption).foregroundStyle(.secondary)
                            }.notebookPanel()
                            HStack {
                                Button("取消") { dismiss() }.buttonStyle(NotebookActionStyle())
                                Button("保存修正") {
                                    if save(mark) { dismiss() }
                                    else { issue = "修正未能保存，当前输入已保留。" }
                                }.buttonStyle(NotebookActionStyle(prominent: true)).accessibilityIdentifier("pitchCorrectionSave")
                            }
                        }
                    }
                    if let issue { Text(issue).font(.callout).foregroundStyle(.red) }
                }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("pitchCorrectionSheet")
                .background(Theme.paper).notebookPageTitle("修正投球")
        }
    }
}

private struct PitchViewpointPicker: View {
    @Binding var viewpoint: PitchViewpoint
    var body: some View {
        Picker("教练站位", selection: $viewpoint) {
            ForEach(PitchViewpoint.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented)
    }
}

private struct PitchReviewView: View {
    let pitches: [PitchMark]
    @Binding var viewpoint: PitchViewpoint
    var roundName = ""
    var ended = false
    @State private var index = 0
    @State private var playing = false
    var body: some View {
        Group {
            ScrollView {
                if pitches.indices.contains(index) {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            NotebookHeading(title: "逐球回看", detail: roundName)
                            Spacer()
                            Text(ended ? "本轮已结束" : "本轮记录").font(.caption).foregroundStyle(Notebook.fieldGreen)
                        }
                        NotebookColumns {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("投球落点").font(.headline)
                                Spacer()
                                Text("第 \(index + 1) / \(pitches.count) 球").font(.caption).foregroundStyle(.secondary)
                            }
                            PitchLocationMap(pitches: Array(pitches.prefix(index + 1)), viewpoint: viewpoint, readOnly: true, selectedIndex: index, ratio: 1.25) { _ in }
                            let mark = pitches[index]
                            HStack {
                                Label("好球", systemImage: "circle.fill").foregroundStyle(PitchLocationMap.strikeColor)
                                Label("坏球", systemImage: "circle").foregroundStyle(PitchLocationMap.ballColor)
                                Spacer()
                                Text("第 \(index + 1) 球 · \(viewpoint.title(for: mark.zone))")
                            }.font(.caption)
                            PitchViewpointPicker(viewpoint: $viewpoint).accessibilityIdentifier("replayViewpoint")
                            HStack {
                                Button("上一球") { playing = false; index -= 1 }.disabled(index == 0)
                                Spacer()
                                Button(playing ? "暂停" : "播放") {
                                    if !playing && index == pitches.count - 1 { index = 0 }
                                    playing.toggle()
                                }.disabled(pitches.count < 2).buttonStyle(NotebookActionStyle(prominent: true))
                                Spacer()
                                Button("下一球") { playing = false; index += 1 }.disabled(index + 1 >= pitches.count)
                            }.buttonStyle(NotebookActionStyle())
                        }
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Text("本轮球序").font(.headline)
                            ForEach(pitches.indices.reversed(), id: \.self) { i in
                                Button { playing = false; index = i } label: {
                                    HStack {
                                        Text(String(format: "%02d", i + 1)).monospacedDigit()
                                        Text(pitches[i].isStrike ? "好球" : "坏球")
                                        Spacer()
                                        Text(viewpoint.title(for: pitches[i].zone))
                                    }.padding(10).frame(minHeight: 44).background(i == index ? Notebook.inset : Notebook.paper)
                                }.buttonStyle(.plain).accessibilityIdentifier("replayPitch_"+String(i + 1))
                                Divider()
                            }
                        }
                        }
                    }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity).background(Theme.paper)
            .notebookPageTitle("逐球回看")
            .task(id: playing) {
                guard playing else { return }
                while index + 1 < pitches.count {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    index += 1
                }
                playing = false
            }
        }
    }
}
