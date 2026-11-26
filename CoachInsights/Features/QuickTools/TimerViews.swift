import SwiftUI
import AudioToolbox

private struct ClockButton: View {
    let title: String
    var color: Color = Theme.burgundy
    var subtle = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline)
                .foregroundStyle(subtle ? color : .white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(subtle ? Notebook.paper : color, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(subtle ? Notebook.rule : .clear) }
        }.buttonStyle(.plain)
    }
}

private struct TrainingClockDial: View {
    let fraction: Double
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 5
            guard radius > 0 else { return }
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(Notebook.rule), lineWidth: 2)
            for index in 0..<60 {
                let angle = Double(index) * .pi / 30 - .pi / 2
                let length: CGFloat = index.isMultiple(of: 5) ? 6 : 3
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                tick.addLine(to: CGPoint(x: center.x + cos(angle) * (radius - length), y: center.y + sin(angle) * (radius - length)))
                context.stroke(tick, with: .color(Notebook.rule), lineWidth: 1)
            }
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + min(1, max(0, fraction)) * 360), clockwise: false)
            context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct StopwatchView: View {
    @EnvironmentObject private var tools: QuickToolsStore
    private var watch: PocketStopwatch { tools.state.stopwatch }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.03, paused: !watch.isRunning)) { context in
            GeometryReader { geometry in
                let wide = geometry.size.width > geometry.size.height
                Group {
                    if wide {
                        HStack(spacing: 36) {
                            VStack { readout(context.date); controls }.frame(maxWidth: .infinity)
                            laps(context.date).frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 16) {
                            readout(context.date).frame(height: max(140, geometry.size.height * 0.40))
                            controls
                            laps(context.date)
                        }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 12)
            }
        }
        .background(Theme.paper).foregroundStyle(.primary).preferredColorScheme(.light).environment(\.colorScheme, .light)
        .navigationTitle("秒表").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.paper, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { QuickSaveIssueView() }
    }

    private func readout(_ now: Date) -> some View {
        let elapsed = watch.elapsed(at: now)
        return ZStack {
            TrainingClockDial(fraction: elapsed.truncatingRemainder(dividingBy: 60) / 60, color: Notebook.fieldGreen)
            VStack(spacing: 6) {
                Text(watch.isRunning ? "计时中" : elapsed > 0 ? "已暂停" : "准备计时")
                    .font(.caption).foregroundStyle(Notebook.fieldGreen)
                Text(PocketTimeFormat.stopwatch(elapsed))
                    .font(.system(size: 48, weight: .semibold, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.45)
                    .accessibilityLabel("已用时间 " + PocketTimeFormat.stopwatch(elapsed))
                    .accessibilityIdentifier("stopwatchTime")
            }.padding(.horizontal, 14)
        }.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack {
            ClockButton(title: watch.isRunning ? "分段" : "复位", subtle: true) {
                tools.updateStopwatch { value in
                    if value.isRunning { value.lap(at: Date()) } else { value.reset() }
                }
            }.accessibilityIdentifier("stopwatchLapReset")
            Spacer()
            ClockButton(title: watch.isRunning ? "停止" : "启动", color: Notebook.fieldGreen) {
                tools.updateStopwatch { value in
                    if value.isRunning { value.pause(at: Date()) } else { value.start(at: Date()) }
                }
            }.accessibilityIdentifier("stopwatchToggle")
        }.frame(maxWidth: 580)
    }

    private func laps(_ now: Date) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack { Text("分段记录").font(.headline); Spacer(); Text("\(watch.laps.count) 段").font(.caption.monospacedDigit()) }
                    .padding(.vertical, 10)
                if watch.laps.isEmpty && !watch.isRunning {
                    Text("开始计时后，可在每个训练环节结束时记一段。").font(.subheadline).foregroundStyle(.secondary)
                }
                if watch.isRunning {
                    lapRow(number: watch.laps.count + 1,
                        value: watch.elapsed(at: now) - (watch.laps.last?.total ?? 0), color: .primary)
                }
                ForEach(watch.laps.reversed()) { lap in
                    lapRow(number: lap.number, value: lap.duration, color: lapColor(lap))
                }
            }
        }.frame(maxWidth: 720).frame(maxWidth: .infinity).accessibilityIdentifier("stopwatchLaps")
    }

    private func lapRow(number: Int, value: TimeInterval, color: Color) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.burgundy.opacity(0.08))
            HStack {
                Text("分段 \(number)")
                Spacer()
                Text(PocketTimeFormat.stopwatch(value)).monospacedDigit()
            }.font(.system(size: 18)).foregroundStyle(color).padding(.vertical, 13)
        }
    }
    private func lapColor(_ lap: StopwatchLap) -> Color {
        guard watch.laps.count > 1 else { return .primary }
        if lap.id == watch.laps.min(by: { $0.duration < $1.duration })?.id { return Theme.burgundy }
        if lap.id == watch.laps.max(by: { $0.duration < $1.duration })?.id { return .secondary }
        return .primary
    }
}

struct CountdownView: View {
    @EnvironmentObject private var tools: QuickToolsStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var hours = 0
    @State private var minutes = 1
    @State private var seconds = 0
    @State private var customDuration = false
    private var countdown: PocketCountdown { tools.state.countdown }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            GeometryReader { geometry in
                let wide = geometry.size.width > geometry.size.height
                Group {
                    if wide {
                        HStack(spacing: 28) {
                            face(context.date).frame(maxWidth: .infinity)
                            VStack(spacing: 20) { controls(context.date); details }.frame(maxWidth: 340)
                        }
                    } else {
                        VStack(spacing: 22) {
                            face(context.date).frame(maxWidth: .infinity, maxHeight: .infinity)
                            controls(context.date)
                            details
                            Spacer(minLength: 8)
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 16)
            }
            .onChange(of: countdown.isFinished(at: context.date)) { _, finished in
                if finished && countdown.isRunning {
                    tools.completeCountdown()
                    if tools.notificationHint != nil { AudioServicesPlayAlertSound(1005) }
                }
            }
        }
        .background(Theme.paper).foregroundStyle(.primary).preferredColorScheme(.light).environment(\.colorScheme, .light)
        .navigationTitle("倒计时").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.paper, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { QuickSaveIssueView() }
        .onAppear {
            readDuration()
            if countdown.isFinished(at: Date()) { tools.completeCountdown() }
        }
        .sheet(isPresented: $customDuration) {
            NavigationStack {
                HStack(spacing: 0) {
                    durationWheel("时", selection: $hours, range: 0..<24, id: "countdownHours")
                    durationWheel("分", selection: $minutes, range: 0..<60, id: "countdownMinutes")
                    durationWheel("秒", selection: $seconds, range: 0..<60, id: "countdownSeconds")
                }.padding().navigationTitle("自定义时长").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("完成") { customDuration = false } }
            }.presentationDetents([.height(290)])
        }
        .onChange(of: hours) { _, _ in setDuration() }
        .onChange(of: minutes) { _, _ in setDuration() }
        .onChange(of: seconds) { _, _ in setDuration() }
        .onChange(of: scenePhase) { _, value in
            if value == .active && countdown.isFinished(at: Date()) { tools.completeCountdown() }
        }
    }

    @ViewBuilder private func face(_ now: Date) -> some View {
        let remaining = countdown.isConfigured ? countdown.duration : countdown.remaining(at: now)
        ZStack {
            TrainingClockDial(fraction: remaining / max(1, countdown.duration), color: Theme.burgundy)
            VStack(spacing: 8) {
                Text(countdown.isConfigured ? "设定时长" : countdown.isFinished(at: now) ? "时间到" : countdown.isRunning ? "计时中" : "已暂停")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(PocketTimeFormat.countdown(remaining))
                    .font(.system(size: 48, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.4)
                    .accessibilityIdentifier("countdownTime")
                if let end = countdown.deadline {
                    Label(end.formatted(date: .omitted, time: .shortened), systemImage: "bell").font(.caption)
                }
            }.padding(.horizontal, 16)
        }.aspectRatio(1, contentMode: .fit).frame(maxWidth: 360, maxHeight: 360)
            .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func durationWheel(_ unit: String, selection: Binding<Int>, range: Range<Int>, id: String) -> some View {
        HStack(spacing: 0) {
            Picker(unit, selection: selection) {
                ForEach(range, id: \.self) { Text(String($0)).font(.title).tag($0) }
            }.pickerStyle(.wheel).labelsHidden().accessibilityLabel(unit).accessibilityIdentifier(id)
            Text(unit).foregroundStyle(.secondary).padding(.trailing, 5)
        }.frame(maxWidth: .infinity).frame(height: 190)
    }
    private func preset(_ title: String, value: Int) -> some View {
        Button(title) {
            hours = value / 3600; minutes = (value / 60) % 60; seconds = value % 60
        }.font(.subheadline).buttonStyle(.bordered).tint(Theme.burgundy)
    }
    private func controls(_ now: Date) -> some View {
        HStack {
            ClockButton(title: "取消", subtle: true) { tools.updateCountdown { $0.cancel() } }
                .disabled(countdown.isConfigured).opacity(countdown.isConfigured ? 0.45 : 1)
                .accessibilityIdentifier("countdownCancel")
            Spacer()
            ClockButton(title: countdown.isRunning ? "暂停" : (countdown.isFinished(at: now) ? "再开始" : "开始"),
                        color: Theme.burgundy) {
                tools.updateCountdown({ value in
                    if value.isRunning { value.pause(at: Date()) }
                    else {
                        if value.isFinished(at: Date()) { value.cancel() }
                        value.start(at: Date())
                    }
                }, requestNotification: true)
            }.disabled(countdown.isConfigured && countdown.duration <= 0)
                .opacity(countdown.isConfigured && countdown.duration <= 0 ? 0.45 : 1)
                .accessibilityIdentifier("countdownToggle")
        }.frame(maxWidth: 600)
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if countdown.isConfigured {
                HStack { Text("快捷时长").font(.headline); Spacer(); Text(PocketTimeFormat.countdown(countdown.duration)).monospacedDigit() }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    preset("30 秒", value: 30); preset("1 分钟", value: 60)
                    preset("3 分钟", value: 180); preset("5 分钟", value: 300)
                }
                Button("自定义时长", systemImage: "pencil") { customDuration = true }.frame(maxWidth: .infinity, minHeight: 44)
            } else {
            HStack {
                Text("设定时长")
                Spacer()
                Text(PocketTimeFormat.countdown(countdown.duration)).foregroundStyle(.gray).monospacedDigit()
            }
            }
            Divider()
            Label("计时结束时提醒", systemImage: "bell")
            if let hint = tools.notificationHint {
                Text(hint).font(.caption).foregroundStyle(Theme.burgundy)
                Button("打开通知设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.font(.caption).tint(Theme.burgundy)
            }
        }.font(.subheadline).padding(18).frame(maxWidth: 600)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
    private func readDuration() {
        let total = Int(countdown.duration)
        hours = total / 3600; minutes = (total / 60) % 60; seconds = total % 60
    }
    private func setDuration() {
        guard countdown.isConfigured else { return }
        tools.updateCountdown { $0.duration = TimeInterval(hours * 3600 + minutes * 60 + seconds) }
    }
}

struct QuickSaveIssueView: View {
    @EnvironmentObject private var tools: QuickToolsStore
    var body: some View {
        if let issue = tools.issue {
            Text(issue).font(.caption).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity)
        }
    }
}
