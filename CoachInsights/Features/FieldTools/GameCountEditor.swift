import SwiftUI

struct GameCountEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var awayRuns: String
    @State private var homeRuns: String
    @State private var strikes: Int
    @State private var balls: Int
    @State private var outs: Int
    @State private var saveFailed = false
    let save: (GameCountCorrection) -> Bool

    init(count: GameCountCorrection, save: @escaping (GameCountCorrection) -> Bool) {
        _awayRuns = State(initialValue: String(count.awayRuns))
        _homeRuns = State(initialValue: String(count.homeRuns))
        _strikes = State(initialValue: count.strikes)
        _balls = State(initialValue: count.balls)
        _outs = State(initialValue: count.outs)
        self.save = save
    }

    private var correction: GameCountCorrection? {
        guard let away = Int(awayRuns), let home = Int(homeRuns) else { return nil }
        let value = GameCountCorrection(awayRuns: away, homeRuns: home, strikes: strikes, balls: balls, outs: outs)
        return value.isValid ? value : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("比分") {
                    LabeledContent("客队") {
                        TextField("客队比分", text: $awayRuns)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editAwayScore")
                    }
                    LabeledContent("主队") {
                        TextField("主队比分", text: $homeRuns)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editHomeScore")
                    }
                }
                Section("当前计数") {
                    Stepper("好球 \(strikes)", value: $strikes, in: 0...2)
                    Stepper("坏球 \(balls)", value: $balls, in: 0...3)
                    Stepper("出局 \(outs)", value: $outs, in: 0...2)
                }
                if saveFailed {
                    Text("未能保存修改，请检查本机储存后重试。").foregroundStyle(.red)
                }
            }
            .navigationTitle("修改计数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let correction else { return }
                        if save(correction) { dismiss() } else { saveFailed = true }
                    }
                    .disabled(correction == nil)
                    .accessibilityIdentifier("saveGameCount")
                }
            }
        }
    }
}
