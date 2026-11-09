import SwiftUI

struct FieldLogView: View {
    @EnvironmentObject private var store: FieldToolsStore
    let kind: FieldLogKind
    var recordID: UUID? = nil
    @State private var reset = false
    @State private var ending = false
    @State private var notice: String?
    @State private var correction: PitchSelection?
    @State private var visibleEventLimit = 30
    @State private var showHistory = false
    @State private var name = ""
    private struct PitchSelection: Identifiable { let id: Int; let mark: PitchMark; let number: Int }
    private var log: FieldLog? { store.log(kind: kind, id: recordID) }

    var body: some View {
        GeometryReader { geometry in
            if let log, kind == .bullpen, geometry.size.width >= 720, geometry.size.height >= 500 {
                bullpenStudio(log, size: geometry.size)
            } else {
                ScrollView {
                    if let log {
                        VStack(alignment: .leading, spacing: 8) {
                            header(log)
                            controls(log, availableHeight: geometry.size.height)
                            if kind == .bullpen {
                                recent(log)
                            } else {
                                DisclosureGroup(isExpanded: $showHistory) {
                                    recent(log, showTitle: false)
                                } label: {
                                    Text("本轮过程 · \(log.events.count)").font(.subheadline.weight(.semibold))
                                }.padding(.horizontal, 12).frame(minHeight: 44)
                            }
                        }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView("记录已不存在", systemImage: "folder.badge.questionmark")
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Theme.paper).navigationTitle(kind.tool.title).navigationBarTitleDisplayMode(.inline)
        .task(id: log?.id) { name = log?.name ?? "" }
        .onChange(of: name) { _, value in
            let limited = String(value.prefix(100))
            if limited != value { name = limited; return }
            if let log, log.name != value { change { $0.name = value } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let log { roundActions(log) }
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
        .sheet(item: $correction) { selection in
            PitchCorrectionView(mark: selection.mark, number: selection.number) { mark in
                change { $0.correctPitch(at: selection.id, zone: mark.zone, isStrike: mark.isStrike, location: mark.location) }
            }
        }
    }

    private func header(_ log: FieldLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(kind == .game ? "比赛名称（选填）" : "姓名或本轮名称（选填）", text: $name)
                .font(.subheadline).padding(.horizontal, 12).frame(minHeight: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .disabled(log.ended).accessibilityIdentifier("fieldName")
            HStack {
                Text(log.createdAt, style: .date).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(log.ended ? "已结束" : "本机自动保存").foregroundStyle(Theme.burgundy)
            }.font(.caption)
        }
    }

    @ViewBuilder private func controls(_ log: FieldLog, availableHeight: CGFloat) -> some View {
        switch kind {
        case .batting:
            VStack(alignment: .leading, spacing: 10) {
                Label("总次数 · \(log.events.count)", systemImage: "figure.baseball")
                    .font(.headline.monospacedDigit()).accessibilityIdentifier("battingTotal")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(BattingContact.allCases, id: \.self) { contact in
                        Button { change { $0.append(.batting(contact)) } } label: {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(contact.title).font(.subheadline.weight(.semibold))
                                    Text("\(log.count(contact))").font(.title2.weight(.semibold).monospacedDigit())
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "plus.circle").font(.body)
                            }.padding(12).frame(maxWidth: .infinity, minHeight: 66)
                                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).foregroundStyle(Theme.burgundy)
                            .accessibilityLabel(contact.title).accessibilityValue("\(log.count(contact))")
                            .accessibilityIdentifier("batting_" + contact.rawValue)
                    }
                }.disabled(log.ended || log.events.count >= FieldLog.eventLimit)
            }
        case .bullpen:
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("投球落点").font(.title3.bold())
                    Spacer()
                    Text("\(log.pitches.count) 球").font(.title2.weight(.semibold).monospacedDigit()).accessibilityIdentifier("bullpenTotal")
                }
                HStack(spacing: 0) {
                    pitchMetric("好球", value: "\(log.strikeCount)", color: PitchLocationMap.strikeColor)
                    pitchMetric("坏球", value: "\(log.pitches.count - log.strikeCount)", color: PitchLocationMap.ballColor)
                    pitchMetric("好球率", value: log.pitches.isEmpty ? "—" : "\(Int((Double(log.strikeCount) / Double(log.pitches.count) * 100).rounded()))%", color: .primary)
                    pitchMetric("出局", value: "\(log.outCount)", color: .primary)
                }.padding(.vertical, 8).background(.white, in: RoundedRectangle(cornerRadius: 12))
                PitchLocationMap(pitches: log.pitches) { point in change { $0.append(.pitch(PitchMark(point: point))) } }
                    .frame(maxWidth: min(400, max(220, (availableHeight - 210) * 1.04)))
                    .frame(maxWidth: .infinity)
                    .disabled(log.ended || log.events.count >= FieldLog.eventLimit)
                HStack(spacing: 12) {
                    Label("好球", systemImage: "circle.fill").foregroundStyle(PitchLocationMap.strikeColor)
                    Label("坏球", systemImage: "circle.fill").foregroundStyle(PitchLocationMap.ballColor)
                    Spacer(minLength: 0)
                    Text("捕手视角").foregroundStyle(.secondary)
                }.font(.caption)
            }
        case .game:
            let count = log.gameCount
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    gameTile("好球", action: .strike, value: count.strikes)
                    gameTile("坏球", action: .ball, value: count.balls)
                    gameTile("出局", action: .out, value: count.outs)
                }.disabled(log.ended || log.events.count >= FieldLog.eventLimit)
                HStack {
                    Text("换边 \(count.sides) 次").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("gameSides")
                    Spacer(minLength: 0)
                    Button("下一位打者", systemImage: "arrow.right") { change { $0.append(.game(.clearBatter)) } }
                        .font(.subheadline).buttonStyle(.bordered)
                        .disabled(log.ended || log.events.count >= FieldLog.eventLimit)
                        .accessibilityHint("清空当前好球与坏球")
                        .accessibilityIdentifier("gameNextBatter")
                }
                Text(count.notice ?? "点计数按钮加一")
                    .font(.footnote).foregroundStyle(count.notice == nil ? Color.secondary : Theme.burgundy)
                    .accessibilityIdentifier("gameBoundary")
            }
        }
    }

    private func gameTile(_ title: String, action: GameAction, value: Int) -> some View {
        Button { change { $0.append(.game(action)) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)").font(.title.weight(.semibold).monospacedDigit())
                    Spacer(minLength: 0)
                    Image(systemName: "plus.circle").font(.body)
                }
            }.padding(12).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).foregroundStyle(Theme.burgundy)
            .accessibilityLabel(title + "加一").accessibilityValue("\(value)")
            .accessibilityIdentifier("game_" + action.rawValue)
    }

    private func pitchMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value).font(.system(size: 26, weight: .semibold)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func bullpenStudio(_ log: FieldLog, size: CGSize) -> some View {
        let listWidth = min(300, size.width * 0.32)
        let mapWidth = min(size.width - listWidth - 52, max(180, size.height - 210) * 1.04)
        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                TextField("姓名或本轮名称（可选）", text: $name)
                    .font(.headline).textFieldStyle(.roundedBorder).frame(maxWidth: 320).disabled(log.ended)
                    .accessibilityIdentifier("fieldName")
                Text(log.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(log.pitches.count) 球").font(.title2.bold().monospacedDigit()).accessibilityIdentifier("bullpenTotal")
                Text(log.ended ? "已结束" : "自动保存").font(.caption).foregroundStyle(Theme.burgundy)
            }.frame(height: 44)
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        pitchMetric("好球", value: "\(log.strikeCount)", color: PitchLocationMap.strikeColor)
                        pitchMetric("坏球", value: "\(log.pitches.count - log.strikeCount)", color: PitchLocationMap.ballColor)
                        pitchMetric("好球率", value: log.pitches.isEmpty ? "—" : "\(Int((Double(log.strikeCount) / Double(log.pitches.count) * 100).rounded()))%", color: .primary)
                        pitchMetric("出局", value: "\(log.outCount)", color: .primary)
                    }.padding(.vertical, 10).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    PitchLocationMap(pitches: log.pitches) { point in change { $0.append(.pitch(PitchMark(point: point))) } }
                        .frame(width: mapWidth).disabled(log.ended || log.events.count >= FieldLog.eventLimit)
                    HStack(spacing: 12) {
                        Label("好球", systemImage: "circle.fill").foregroundStyle(PitchLocationMap.strikeColor)
                        Label("坏球", systemImage: "circle.fill").foregroundStyle(PitchLocationMap.ballColor)
                        Spacer(minLength: 0)
                        Text("捕手视角 · 手动落点").foregroundStyle(.secondary)
                    }.font(.caption)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity)
                ScrollView {
                    recent(log)
                }.frame(width: listWidth)
            }.frame(maxHeight: .infinity)
        }.padding(16)
    }

    private func roundActions(_ log: FieldLog) -> some View {
        VStack(spacing: 4) {
            if let notice {
                Text(notice).font(.caption).foregroundStyle(Theme.burgundy).accessibilityIdentifier("fieldNotice")
            }
            if log.events.count >= FieldLog.eventLimit {
                Text("本轮已达 10,000 次，可结束后开始新一轮。").font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                if log.ended {
                    Button("继续编辑") {
                        var next = log
                        next.ended = false
                        if store.update(next) { notice = nil }
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("fieldResume")
                } else {
                    Button { undo(log) } label: {
                        Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                    }.disabled(log.undoHistory.isEmpty).accessibilityLabel("撤销").accessibilityIdentifier("fieldUndo")
                    if kind == .bullpen {
                        Button("出局 +1") { change { $0.append(.bullpenOut) } }
                            .buttonStyle(.bordered).disabled(log.events.count >= FieldLog.eventLimit).accessibilityIdentifier("bullpenOut")
                    }
                    Spacer(minLength: 0)
                    Button("保存本轮") { if save(log) { notice = "已保存到记录" } }
                        .buttonStyle(.borderedProminent).disabled(log.events.isEmpty).accessibilityIdentifier("fieldSave")
                    Menu {
                        Button("结束本轮") { ending = true }.disabled(log.events.isEmpty).accessibilityIdentifier("fieldEnd")
                        Button("清零本轮", role: .destructive) { reset = true }.disabled(log.events.isEmpty).accessibilityIdentifier("fieldReset")
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.accessibilityLabel("本轮选项").accessibilityIdentifier("fieldOptions")
                }
            }.frame(maxWidth: 560)
        }.font(.subheadline).padding(.horizontal, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity).background(Theme.paper)
            .overlay(alignment: .top) { Divider() }
    }

    private func recent(_ log: FieldLog, showTitle: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showTitle { Text("本轮过程 · \(log.events.count)").font(.headline) }
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
                                    Text(mark.zone.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "pencil.circle")
                            }.frame(minHeight: 44)
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
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
    private func eventTitle(_ event: FieldEvent) -> String {
        switch event {
        case .batting(let contact): return contact.title
        case .bullpenOut: return "出局 +1"
        case .pitch(let mark): return mark.zone.title
        case .game(let action):
            switch action { case .strike: return "好球 +1"; case .ball: return "坏球 +1"; case .out: return "出局 +1"; case .clearBatter: return "下一位打者" }
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
    let number: Int
    let save: (PitchMark) -> Bool
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("修正同一球，球数保持不变").font(.subheadline).foregroundStyle(.secondary)
                    PitchLocationMap(pitches: [mark], correcting: true, sequence: number) { point in
                        mark.location = point; mark.zone = .at(point)
                    }.frame(maxWidth: 360)
                    HStack {
                        Text("落点：" + mark.zone.title)
                        Spacer()
                        Toggle("好球", isOn: $mark.isStrike).labelsHidden().accessibilityIdentifier("pitchStrikeToggle")
                        Text(mark.isStrike ? "好球" : "坏球").foregroundStyle(mark.isStrike ? PitchLocationMap.strikeColor : PitchLocationMap.ballColor)
                    }
                    Text("移动落点保持原判定；需要时单独切换好坏球。").font(.caption).foregroundStyle(.secondary)
                    if let issue { Text(issue).font(.callout).foregroundStyle(.red) }
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("pitchCorrectionSheet")
                .background(Theme.paper).navigationTitle("修正第 \(number) 球")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存修正") {
                            if save(mark) { dismiss() }
                            else { issue = "修正未能保存，当前输入已保留。请检查本机储存后重试，或取消返回。" }
                        }.accessibilityIdentifier("pitchCorrectionSave")
                    }
                }
        }
    }
}
