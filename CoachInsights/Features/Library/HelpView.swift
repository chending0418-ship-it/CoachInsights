import SwiftUI

struct HelpView:View {
    var body:some View {
        Form {
            Section("训练计数与历史") {
                Text("打击记录按单轮累计滚地、平飞、高飞和挥空。投球记录采用捕手视角，点击落点图记一球，细线九宫格内默认好球、外围默认坏球；落点按球序编号，点击球序可独立修正位置和好坏球，修正不增加总球数。牛棚出局单独计数。")
                Text("比赛计数器记录好球、坏球与出局过程，三振自动加出局、四坏保送后清空好坏球、三出局清零并提示换边；可手动加分或直接修正比分和当前计数。三种计数均支持撤销、清零、保存本轮及结束本轮，历史可在记录页筛选、重开、继续编辑或删除。")
                Text("操作自动保存当前轮次；主动保存或结束后进入历史。最近 100 次操作支持撤销，修正和清零也可撤销，退出重开后继续保留。")
            }
            Section("随手工具") {
                Text("秒表使用大数字显示，支持开始、停止、分段和复位。倒计时可设置时、分、秒，支持暂停和继续；离开页面后按实际时间继续，开启通知后可在后台收到结束提醒。系统静音、专注模式及通知设置可能影响提醒。")
                Text("战术白板进入横屏。选择模式可拖动防守队员和跑者；画笔模式拖动画线，路线工具拖动绘制箭头。底部可放置防守阵容、跑者和选择颜色。支持撤销、重做与清空，修改自动保存到本机记录；保存图片需要相册添加权限。")
                Text("测距使用 Apple ARKit。在支持的设备上移动相机识别表面，用准星对准起点和终点分别点击加号。距离为实景估算，请复核；模拟器无法验证真实距离。不需要位置权限，画面不会上传。")
            }
            Section("从视频开始") {
                Text("新建打击或投球记录，选择相册、文件或拍摄。导入会复制到本机；分析操作不会修改原片。相册慢动作优先保留源帧及展示时间，无法还原时会明确提示。")
                Text("在分析页用滑条定位，播放键两侧可逐帧移动。左下角的时间轴与片段可精细定位并设置起止帧。速度菜单可设置慢放与循环。")
                Text("手机横屏会扩大视频画布，也可点击全屏按钮进入或退出。横屏时工具浮在画面上，时间轴与片段可从工具按钮按需打开。")
            }
            Section("标注与关键帧") {
                Text("画面模式用双指缩放、单指平移；绘制模式拖动画直线、箭头、圆框或手绘。文字工具点选位置，角度工具依次点三次，第二点为顶点。")
                Text("选择工具点选标注后，拖动整体或白色控制点调整。单帧标注只在指定帧出现，片段标注覆盖当前所选片段。编辑自动保存在这份记录。动作节点可用建议名称或自定义。")
            }
            Section("双视频与人体分析") {
                Text("先导入两段视频，在对比页分别定位同一动作节点并设为同步点。共享时间 0 代表该节点。联动逐帧按左路实际帧时间推进，各路显示共享时间对应的帧。")
                Text("新对比默认自动布局：竖屏上下、横屏左右。也可手动固定为左右或上下；已有记录保留保存的布局，选择自动后随当前窗口变化。")
                Text("人体分析在本机运行；模拟器使用 MediaPipe Full，其他设备在 Vision 不可用时自动切换。框住单个人体后分析选定片段。缺失、多人或不确定结果留空；关节角度是二维画面估算，请人工复核点位。")
                Text(PoseGuidance.limitations)
            }
            Section("导出与隐私") {
                Text("截图包含当前帧可见标注，可选骨架与角度。视频使用 H.264、SDR、30 fps；慢放及双视频无声，单视频 1× 可选原声。通过系统分享菜单存储到文件或分享，也可另行授权保存到相册。")
                Text(PoseGuidance.exportNotice)
                Text("无需账号。视频、分析和离线模型均留在本机，不上传、不启用 iCloud 或跨设备同步。App 资料排除系统备份；删除 App 会删除其中的记录，请先导出所需结果。")
                Text("相机用于拍摄或 AR 测距；录音可选，拒绝麦克风仍可无声拍摄。相册仅用于所选素材导入或用户主动保存分析结果及白板图片。系统相册可能由你的系统设置进行同步，这不等于 App 同步。")
            }
            Section("版本与开源组件") {
                Text("棒球训练助手 · Drill Buddy \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")) · iOS / iPadOS 17+")
                Text("MediaPipe Tasks 1.1.1 / Pose Landmarker Full v1，Apache License 2.0。模型随应用离线提供。")
                NavigationLink("开源许可") { ScrollView { Text(license).font(.caption.monospaced()).padding() }.navigationTitle("Apache 2.0") }
            }
        }.navigationTitle("使用说明与隐私").navigationBarTitleDisplayMode(.inline)
    }
    private var license:String {
        guard let url=Bundle.main.url(forResource:"MediaPipe-LICENSE",withExtension:"txt"),let text=try? String(contentsOf:url,encoding:.utf8) else { return "Apache License, Version 2.0 — https://www.apache.org/licenses/LICENSE-2.0" };return text
    }
}
