import SwiftUI
struct ExportView: View {
    let session: AnalysisSession
    var body: some View {
        ScrollView {
            EmptyPanel(icon: "square.and.arrow.up", title: "分享动作里的发现",
                       detail: "导出功能准备中。\n分析记录保存在当前设备，后续可导出分享。")
        }.navigationTitle("导出分析").navigationBarTitleDisplayMode(.inline)
    }
}
