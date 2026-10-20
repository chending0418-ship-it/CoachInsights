import SwiftUI
struct ComparisonView: View {
    let session: AnalysisSession
    var body: some View {
        ScrollView {
            EmptyPanel(icon: "rectangle.split.2x1", title: "将两次动作放在一起",
                       detail: "对比功能准备中。\n之后可选择两段视频，在同一画面查看动作。")
        }.navigationTitle("双视频对比").navigationBarTitleDisplayMode(.inline)
    }
}
