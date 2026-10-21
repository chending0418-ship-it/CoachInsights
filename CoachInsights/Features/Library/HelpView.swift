import SwiftUI

struct HelpView:View {
    var body:some View {
        Form {
            Section("从视频开始") {
                Text("新建打击或投球记录，选择相册、文件或拍摄。导入会复制到本机；分析操作不会修改原片。相册慢动作优先保留源帧及展示时间，无法还原时会明确提示。")
                Text("在分析页用滑条定位，前后按钮逐帧移动。速度按导入后的展示时间定义。片段菜单设置起止帧，循环仅播放所选区间。")
            }
            Section("标注与关键帧") {
                Text("画面模式用双指缩放、单指平移；绘制模式拖动画直线、箭头、圆框或手绘。文字工具点选位置，角度工具依次点三次，第二点为顶点。")
                Text("选择工具点选标注后，拖动整体或白色控制点调整。单帧标注只在指定帧出现，片段标注覆盖当前所选片段。编辑自动保存在这份记录。动作节点可用建议名称或自定义。")
            }
            Section("双视频与人体分析") {
                Text("先导入两段视频，在对比页分别定位同一动作节点并设为同步点。共享时间 0 代表该节点。联动逐帧按左路实际帧时间推进，各路显示共享时间对应的帧。")
                Text("人体分析在本机运行；模拟器使用 MediaPipe Full，其他设备在 Vision 不可用时自动切换。框住单个人体后分析选定片段。缺失、多人或不确定结果留空；关节角度是二维画面估算，请人工复核点位。")
                Text(PoseGuidance.limitations)
            }
            Section("导出与隐私") {
                Text("截图包含当前帧可见标注，可选骨架与角度。视频使用 H.264、SDR、30 fps；慢放及双视频无声，单视频 1× 可选原声。通过系统分享菜单存储到文件或分享，也可另行授权保存到相册。")
                Text(PoseGuidance.exportNotice)
                Text("无需账号。视频、分析和离线模型均留在本机，不上传、不启用 iCloud 或跨设备同步。App 资料排除系统备份；删除 App 会删除其中的记录，请先导出所需结果。")
                Text("相机只在拍摄时使用；录音可选，拒绝麦克风仍可无声拍摄。相册仅用于所选素材导入或用户主动保存导出结果。系统相册可能由你的系统设置进行同步，这不等于 App 同步。")
            }
            Section("版本与开源组件") {
                Text("Coach Insights 1.0 (1) · iOS / iPadOS 17+")
                Text("MediaPipe Tasks 1.1.1 / Pose Landmarker Full v1，Apache License 2.0。模型随应用离线提供。")
                NavigationLink("开源许可") { ScrollView { Text(license).font(.caption.monospaced()).padding() }.navigationTitle("Apache 2.0") }
            }
        }.navigationTitle("使用说明与隐私").navigationBarTitleDisplayMode(.inline)
    }
    private var license:String {
        guard let url=Bundle.main.url(forResource:"MediaPipe-LICENSE",withExtension:"txt"),let text=try? String(contentsOf:url,encoding:.utf8) else { return "Apache License, Version 2.0 — https://www.apache.org/licenses/LICENSE-2.0" };return text
    }
}
