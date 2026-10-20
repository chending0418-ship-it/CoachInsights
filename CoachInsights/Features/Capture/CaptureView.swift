import SwiftUI

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            EmptyPanel(icon: "video", title: "准备记录下一次动作",
                       detail: "拍摄功能准备中。\n现在可以在分析记录中关联本机视频。")
        }.navigationTitle("拍摄").toolbar { Button("完成") { dismiss() } }
    }
}
