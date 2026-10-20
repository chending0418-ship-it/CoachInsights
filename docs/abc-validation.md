# 1.0 A–C 实现与模拟器验收

分支：codex/1.0-development。本轮为 V1-001–017。D–J 的完整拍摄、分析编辑、绘制、对比操作与导出保持未完成。仅使用模拟器。

## 实现位置

| TODO | 实现与证据 |
| --- | --- |
| A：001–002 | Universal、iOS / iPadOS 17+；App / unit / UI 三个 target；research 不在原生 target 中 |
| A：003–004 | Features 五个页面导航与空状态；紧凑导航、iPad 分栏；可滚动内容；勃艮第红 #722F37、暖白背景、浅玫瑰色选中态 |
| A：005 | scripts/verify.py、共享 scheme、GitHub Actions；测试时合成媒体；私有样本与截图不进入 Git |
| B：006–007 | MediaInspector、MediaTimeMap、PhotoVideoSource；真实 PTS、VFR、方向、编码、组合轨道源 / 展示时间映射，保留高帧率 |
| B：008–009 | FrameProvider、LatestTaskRunner、PlaybackCoordinator；零容差取帧 / seek、旧请求隔离；邻近帧 LRU、缩略图缓存、内存警告清理 |
| B：010 | VideoGeometry；规范化画面与画布坐标；裁切、镜像、旋转、缩放、平移及逆变换；预览 / 导出共用 |
| B：011 | Debug 技术探针、DualPlaybackCoordinator、VisionProbe；帧定位、共享时钟、实际播放推进、漂移和 Vision 可用性分别记录 |
| C：012–013 | 版本化 VideoAsset / AnalysisSession；Annotation / ComparisonSetup / PoseResult；SwiftData 显式关闭 CloudKit，无 iCloud entitlement |
| C：014–015 | 创建、重命名、搜索、日期 / 运动筛选、打开、删除；仓储保存片段、标注、关键帧、对比、姿态和画面设置完整快照 |
| C：016–017 | LocalFileStore / LibraryRepository；复制→分块 SHA-256→原子移动→数据库提交；引用删除、失败 rollback、staging / 孤立文件恢复 |

编辑快照的恢复是 C 的数据能力，编辑操作界面在 E–H 接入。当前文件关联入口用于本机素材管理；完整相册 / 文件导入的进度、取消与拍摄流程仍归 D。

## 时间与原件约定

- 保存整数 CMTime 值和时基，帧索引来自实际样本 PTS。跳过系统零样本边界标记；B 帧按展示时间排序。
- Photos adapter 从 original 获取源高帧率，单独检查 current 时间线。组合轨道完整保留源帧时才采用相册调整；若已渲染丢帧，退回原片时间线并明确提示。用 120fps 分段慢动作组合及 30fps 渲染替身验证。
- Adapter 返回 AVAsset 与时间策略；实际相册选择、组合轨道的持久复制与完整恢复属于 D。不把合成素材宣称为真实相册资源。
- 原件只复制，不修改相册或文件提供者。相同内容复用本机素材，最后引用删除后才清理副本。
- 数据库提交之前必须完成复制与媒体检查。中断副本可回收；启动恢复先完整读取记录并检查版本，未知版本不盲目清理。
- 缺失素材可重新关联内容哈希一致的原片。空间不足 / 读取错误保留已有记录并允许重试；资料库打不开时保留文件，不静默重建。

## 缓存与预览

分析图像最大边默认 1280，保留所有 PTS，不重编码原件或静默降成 30fps。帧缓存预算 64 MiB，缩略图预算 24 MiB、最大边 240；超预算项不入缓存。内存警告和主动清理也会使进行中的旧缓存写入失效；损坏缩略图重新生成。

当前短视频探针无需额外代理。长片段、HDR、长期双路播放与导出压力在 D–J 补测；如需代理，仍须保留原件及逐帧映射。缓存预算不等于 App 总内存。

## 自动化与回归门槛

统一入口：python3 scripts/verify.py。代码中的可复测要求：

- 30 / 60 / 120 / 240fps、VFR 的实际 PTS 与输入时间一致；方向尺寸正确；分段慢动作保留 120 个源帧，源 / 展示映射可往返。
- 索引步进可往返、首尾夹取正确；精确取帧 / seek 与 PTS 相符；旧任务即使晚完成也不能覆盖最终请求。
- 合成及私有 4K 探针取帧时间误差低于 0.1ms；合成单帧请求低于 2.5s 的阻塞门槛。交互延迟在 E 的连续拖动场景继续优化。
- 双路在共同主机时间启动，半速实际推进超过 0.1s；约 0.9s 采样窗口内漂移小于一帧（60fps 为 16.67ms，约 30fps 为 34ms）。长期循环、边界和完整对比操作在 G 验收。
- 缓存按预算驱逐，损坏缓存可重建；几何在不同画布、四种旋转、镜像、裁切、缩放、平移后可往返；角度按实际像素比例计算。
- 持久化重开恢复完整快照，共享素材删除安全、原件字节不变；覆盖低空间、缺失 / 重关联、中断 staging、孤立文件、未知版本和悬空引用。
- UI 覆盖创建、重命名、打开、对比 / 导出导航、横竖屏、重启恢复、删除及探针。截图附在 xcresult，留在本机。

这些是后续模块的正确性底线。模拟器性能仅在同类环境比较，不推断实体设备的相机、能耗或发热能力。

## Vision 可用性

本机 iOS 26.1 模拟器执行 VNDetectHumanBodyPoseRequest revision 1 时返回 com.apple.Vision Code 9。系统日志包含 Missing weights path cnn_human_pose.espresso.weights；显式选择 CPU 计算阶段仍无法初始化。

探针单独保存 visionStatus = runtimeUnavailable 和错误信息，识别耗时与关节结果为空。它既不是“没有人”，也不是识别质量通过。未知错误仍使探针失败。帧定位、双路播放继续独立验证。

B 的能力探测已有明确结论，H 的识别可用性和质量门禁尚未通过。后续必须在模拟器内解决模型可用性，或以相同素材评估可用替代引擎，然后核查打击 / 投球各至少 30 帧。目前没有投球样本或关节精度优势结论。

人体验收集以固定机位、单个主体、关节清晰可见组织，遮挡、多人、模糊单列。H 仍需验证可见关节误差不超过人体框高度 5% 的比例达到 90%，另记覆盖率、左右混淆及高置信错误。

## 环境与证据

- Xcode 26.1.1（17B100）、iOS 26.1（23B86）、Apple Silicon Mac。
- 项目专用 iPhone 16e、iPad mini（A17 Pro）模拟器；部署目标 17+，实际运行系统为 26.1。
- 私有回归片段 IMG_9673.mov：3840 × 2160、78 帧、约 2.602s；视频仅在本机忽略目录。
- 可安装 Universal 模拟器 Release 构建：build/ReleaseData/Build/Products/Release-iphonesimulator/CoachInsights.app；已在两端安装、启动并检查名称与主题，不包含测试视频或 Debug 探针。
- 日志 / xcresult / 探针 JSON：artifacts/iphone/、artifacts/ipad/。GitHub CI 以远程实际运行结果为准。

2026-10-20 双端均通过：共 31 个通过，1 个仅适用于 iPad 的窗口测试在 iPhone 标记不适用，0 失败。包含私有回归视频；每端 13 项核心测试，外加界面测试。

| 模拟器 | 测试结果 | 4K 取帧最小 / 平均 / 最大 | 双路时基最大漂移 | 采样驻留内存最大值 |
| --- | --- | --- | --- | --- |
| iPhone 16e | 15 通过 / 1 不适用 | 25.2 / 40.7 / 57.3 ms | 0.006 ms | 377.6 MiB |
| iPad mini (A17 Pro) | 16 通过 / 0 不适用 | 22.8 / 44.3 / 72.8 ms | 0.010 ms | 384.0 MiB |

五个采样帧的 PTS 最大误差两端均为 0ms；4K 图像缓存为 35.16 MiB。这里的漂移是播放器时基差，未宣称实际显示刷新精度；内存是探针采样期间的最大驻留值，不是系统连续峰值跟踪。探针资源回归上限为 1 GiB 驻留内存，帧缓存仍严格限制为 64 MiB。

iPad 窄窗口用 Debug 容器切换到 360 点视口及对应布局 trait，确认新建操作可达，再恢复宽视口；这覆盖内容重排，不宣称操作过系统窗口管理器。横竖屏另由原生模拟器旋转验证。

数值快照见 abc-metrics.json；原始 JSON、日志与截图保存在忽略的 artifacts 中。

## API 依据

- [Apple：共享时钟播放需关闭自动等待](https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling)
- [Apple：Vision 计算设备](https://developer.apple.com/documentation/vision/vnrequest/setcomputedevice(_:for:))
- [Apple：相册 current](https://developer.apple.com/documentation/photos/phvideorequestoptionsversion/current)、[original](https://developer.apple.com/documentation/photos/phvideorequestoptionsversion/original)
