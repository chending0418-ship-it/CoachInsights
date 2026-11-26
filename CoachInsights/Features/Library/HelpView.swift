import SwiftUI

struct HelpView: View {
    private struct Question {
        let title: String
        let paragraphs: [String]
    }
    private let questions = [
        Question(title: "投手身后怎样记录？", paragraphs: [
            "在落点图旁选「投手后方」，本垒板在画面上方。切回捕手后方时，同一球左右镜像，高低、序号和好坏判定保持一致。"
        ]),
        Question(title: "怎样记球、修正或回看一轮训练？", paragraphs: [
            "打击记录按单轮累计滚地、平飞、高飞和挥空。投球记录可按教练站位选择捕手后方或投手后方。从投手后方看，本垒板在图的上方。切换视角时，已有落点按新站位显示。点击落点图记一球，细线九宫格内默认好球、外围默认坏球；落点按球序编号，点击球序可独立修正位置和好坏球，修正不增加总球数。好球率显示好球数占总投球数的百分比，出局单独计数。点「逐球回看」可按顺序复盘。",
            "比赛计数器记录好球、坏球与出局过程，三振自动加出局、四坏保送后清空好坏球、三出局清零并提示换边；可手动加分或直接修正比分和当前计数。三种计数均支持撤销、清零、保存本轮及结束本轮，历史可在记录页筛选、重开、继续编辑或删除。",
            "操作自动保存当前轮次；主动保存或结束后进入历史。最近 100 次操作支持撤销，修正和清零也可撤销，退出重开后继续保留。"
        ]),
        Question(title: "怎样计时、测距或使用白板？", paragraphs: [
            "秒表使用大数字显示，支持开始、停止、分段和复位。倒计时可设置时、分、秒，支持暂停和继续；离开页面后按实际时间继续，开启通知后可在后台收到结束提醒。系统静音、专注模式及通知设置可能影响提醒。",
            "战术白板进入横屏。选择模式可拖动防守队员和跑者；画笔模式拖动画线，路线工具拖动绘制箭头。底部可放置防守阵容、跑者和选择颜色。支持撤销、重做与清空，修改自动保存到本机记录；保存图片需要相册添加权限。",
            "测距使用 Apple ARKit。在支持的设备上移动相机识别表面，用准星对准起点和终点分别点击加号。距离为实景估算，请复核；模拟器无法验证真实距离。不需要位置权限，画面不会上传。"
        ]),
        Question(title: "怎样导入并慢放视频？", paragraphs: [
            "新建打击或投球记录，选择相册、文件或拍摄。导入会复制到本机；分析操作不会修改原片。相册慢动作优先保留源帧及展示时间，无法还原时会明确提示。",
            "在分析页用滑条定位，播放键两侧可逐帧移动。左下角的时间轴与片段可精细定位并设置起止帧。速度菜单可设置慢放与循环。",
            "手机横屏会扩大视频画布，也可点击全屏按钮进入或退出。横屏时工具浮在画面上，时间轴与片段可从工具按钮按需打开。"
        ]),
        Question(title: "怎样标注画面和保存动作节点？", paragraphs: [
            "画面模式用双指缩放、单指平移；绘制模式拖动画直线、箭头、圆框或手绘。文字工具点选位置，角度工具依次点三次，第二点为顶点。",
            "选择工具点选标注后，拖动整体或白色控制点调整。单帧标注只在指定帧出现，片段标注覆盖当前所选片段。编辑自动保存在这份记录。动作节点可用建议名称或自定义。"
        ]),
        Question(title: "怎样对齐两段视频或分析人体？", paragraphs: [
            "先导入两段视频，在对比页分别定位同一动作节点并设为同步点。共享时间 0 代表该节点。联动逐帧按左路实际帧时间推进，各路显示共享时间对应的帧。",
            "新对比默认自动布局：竖屏上下、横屏左右。也可手动固定为左右或上下；已有记录保留保存的布局，选择自动后随当前窗口变化。",
            "人体分析在本机运行；模拟器使用 MediaPipe Full，其他设备在 Vision 不可用时自动切换。框住单个人体后分析选定片段。缺失、多人或不确定结果留空；关节角度是二维画面估算，请人工复核点位。",
            PoseGuidance.limitations
        ]),
        Question(title: "怎样导出截图或视频？", paragraphs: [
            "截图包含当前帧可见标注，可选骨架与角度。视频使用 H.264、SDR、30 fps；慢放及双视频无声，单视频 1× 可选原声。通过系统分享菜单存储到文件或分享，也可另行授权保存到相册。",
            PoseGuidance.exportNotice
        ]),
        Question(title: "怎样把练习发给球员？", paragraphs: [
            "在私教里打开教练笔记或课后练习卡。保存内容后进入图片分享，核对每一页，再选择保存或分享。"
        ])
    ]
    @State private var expanded: Set<Int> = [0]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("使用指南").font(.caption).foregroundStyle(.secondary)
                Text("使用帮助").font(.title.bold()).padding(.bottom, 18)
                Divider()
                ForEach(questions.indices, id: \.self) { index in
                    let question = questions[index]
                    Button {
                        if expanded.contains(index) { expanded.remove(index) } else { expanded.insert(index) }
                    } label: {
                        HStack {
                            Text(question.title).font(.headline).multilineTextAlignment(.leading)
                            Spacer(); Image(systemName: expanded.contains(index) ? "chevron.up" : "chevron.down")
                        }.frame(minHeight: 50).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if expanded.contains(index) {
                        ForEach(question.paragraphs, id: \.self) { paragraph in
                            Text(paragraph).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4).padding(.bottom, 12)
                        }
                    }
                    Divider()
                }
                NavigationLink { LocalDataHelp() } label: { Label("隐私与本机数据", systemImage: "lock") }
                    .buttonStyle(DocumentButtonStyle()).padding(.vertical, 16)
                DisclosureGroup("版本与开源组件") {
                    VStack(alignment: .leading, spacing: 9) {
                Text("棒球训练助手 · Drill Buddy \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")) · iOS / iPadOS 17+")
                Text("MediaPipe Tasks 1.1.1 / Pose Landmarker Full v1，Apache License 2.0。模型随应用离线提供。")
                        NavigationLink("开源许可") {
                            ScrollView { Text(license).font(.caption.monospaced()).padding() }.notebookPageTitle("Apache 2.0")
                        }
                    }.font(.caption).padding(.vertical, 10)
                }
            }.padding(16).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(Notebook.paper).navigationTitle("使用帮助").navigationBarTitleDisplayMode(.inline)
    }
    private var license:String {
        guard let url=Bundle.main.url(forResource:"MediaPipe-LICENSE",withExtension:"txt"),let text=try? String(contentsOf:url,encoding:.utf8) else { return "Apache License, Version 2.0 — https://www.apache.org/licenses/LICENSE-2.0" };return text
    }
}

private struct LocalDataHelp: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("使用帮助").font(.caption).foregroundStyle(.secondary)
                Text("隐私与本机数据").font(.title.bold())
                Text("资料保存在本机").font(.headline).padding(.top, 12)
                Text("无需账号。视频、分析和离线模型均留在本机，不上传、不启用 iCloud 或跨设备同步。App 资料排除系统备份；删除 App 会删除其中的记录，请先导出所需结果。").font(.body).foregroundStyle(.secondary).lineSpacing(5)
                Text("相机、麦克风与相册").font(.headline).padding(.top, 12)
                Text("相机用于拍摄或 AR 测距；录音可选，拒绝麦克风仍可无声拍摄。相册仅用于所选素材导入或用户主动保存分析结果及白板图片。系统相册可能由你的系统设置进行同步，这不等于 App 同步。").font(.body).foregroundStyle(.secondary).lineSpacing(5)
                Text("主动分享").font(.headline).padding(.top, 12)
                Text("导出前可核对视频片段、球员姓名与教练署名。选择系统分享后，资料会发送到你选的 App 或联系人；选择保存到相册后，图片或视频会写入系统相册。").font(.body).foregroundStyle(.secondary).lineSpacing(5)
            }.padding(16).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(Notebook.paper).notebookPageTitle("隐私与本机数据")
    }
}
