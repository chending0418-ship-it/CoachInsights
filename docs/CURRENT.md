# 棒球训练助手 Drill Buddy 当前入口

## 1.1.0（Build 11）A 稿逐页整改

对照 Build 10 的本机核对表，修改 iPhone 34 项、iPad 37 项，包含场景与记录、投球修正及回看、计时、视频资料库与编辑工作区，以及教练内容的填写、预览和分享。两端各 45 项对照见 [Build 11 全页复核](../artifacts/validation/1.1.0-11-a/index.html)，包括 44 项 A 稿页面或状态和 1 项旧版白板。[逐页验收记录](validation/v1.1.0-build11-page-review.md)随此版本保存。相机实拍、AR 端点及距离待支持设备复核。TestFlight 由用户自行上传。本地签名归档和来源校验保存在 [Build 11 归档目录](../artifacts/releases/1.1.0-11/)。


## 1.1.0（Build 10）原生界面修订

针对 Build 9 的原生页面覆盖问题，以已选 A 稿的 46 个条目为核对表，排除只用于设计评审的页面目录，其余 45 个用户可见页面或操作状态逐项对应。横屏经典白板沿用此前核准的球场几何和操作方式。详见[1.1.0 发布功能计划](plans/1.1.0%20发布功能计划.md)。Build 9 归档仍单独保留。

本机逐页核对图册共 90 张原生截图，iPhone 与 iPad 各 45 张，可按页面名称检索。见 `artifacts/validation/1.1.0-10-pages/index.html`。对应 A 稿及原生截图可在同目录的 `compare.html` 并排查看。比赛使用深绿双队比分牌、局数与 B/S/O 灯位；打击使用总挥棒数和四张轨迹卡。Build 10 的本机归档及检查报告目录为 `artifacts/releases/1.1.0-10/`，TestFlight 由用户自行上传。

## 1.1.0（Build 9）TestFlight 候选版 · 2026-11-26

iPhone、iPad 共用场边训练工具箱，14 个正式工具入口全部可用。首页可继续牛棚记录，投球记录支持捕手后方、投手后方、好球率、单球修正与逐球回看。战术白板沿用横屏米白球场和酒红守位。个人计划、教练笔记、课后练习卡和团训计划可本机保存、重开、编辑及生成分享图片。团训按已保存的环节计时，支持暂停、延长、手动换段以及重开后继续。运行中的顺序与时长以启动时的计划为准。版本配置见 `Config/Build.xcconfig`。以下按日期保留以前版本的记录。


2026-11-09 用户确认：迄今的构建均为 Beta，包括 1.1 第 00 期 TestFlight 构建 1.1（5）。首次 App Store 正式发布版本号从 1.0.0 开始。正式发布时用 1.0.0 单独归档，构建号按当时 App Store Connect 的上传记录确定。

更新日期：2026-11-09。用户确认产品中文名为“棒球训练助手”，英文名为 Drill Buddy（原名：教练口袋 / Coach Insights），面向棒球教练、家长和球员。工程名 CoachInsights、Bundle ID、本机数据目录及版本号保持稳定。

本轮已同步 App 首页、帮助、白板图片署名、通知、相册权限错误提示及中英文系统展示名。官网更名已于 2026-11-05 部署，品牌文字 Logo 已同步，见[更名发布记录](../../../website/deploy/2026-11-05-drill-buddy-rename.md)；商店名称尚未发布更新；历史发布／验证记录及冻结品牌参考保留原名。更名后模拟器 Debug 构建通过，中英文名称资源、Bundle ID 与 1.0.1（4）已核对，证据位于 `artifacts/validation/name-change/`。命名依据见[品牌命名修订](../../../brand/specifications/1.2/README.md)。

2026-11-06 当前平台方向：先规划 iOS 的 iPhone 与 iPad，范围和规则明确后先完成 iOS 设计、开发与验收。Android Phone 是后续目标，视频模型、解码与分析结果的可行性尚未验证，不再承诺三端同期交付。

| 项目 | 当前依据 |
| --- | --- |
| 版本来源 | `Config/Build.xcconfig`：1.0.1（Build 4） |
| 用户确认已上传 | 1.0.1（Build 3） |
| Build 4 | 已有本地未签名归档与包检查报告保留在 `artifacts/build-4-main/`、`artifacts/testflight/`；本地材料不代表 Apple 上传成功 |
| 上传状态 | 本轮没有执行上传、审核或发行，Build 4 是否上传以用户确认或回执为准 |
| 版本交接 | [TestFlight 操作说明](releases/testflight-guide.md)、[Build 4 审查](releases/1.0.1/build-4-review.md) |
| iPad 首发 UI 评审 | 用户认可专业工作室的布局方向，但要求恢复私教／团训／随手工具结构，并保留 iPhone；当前先规划 iOS 双端，Android 后续预研。已按 [用户优先级](plans/v1.1-todo.md#三期功能与任务拆分2026-11-06) 分为 00／01／02 三期；用户本轮已授权 00 期开发，当前 iPad 宽窗口接入按三大场景组织的工作室侧栏，窄窗口保留紧凑导航；[旧提案](design/ipad-first/README.md) 保留为探索记录，其项目优先架构不作为现行依据 |
| 功能归属调整 | 2026-11-06：打击记录 T03、投球记录 T04 归随手工具；战术白板 Q03 归团训。入口及记录筛选已按归属调整，原编号与 00 期优先级保持；[针对性核心检查](validation/v1.1-entry-validation.md) 两端各 12 项通过。仓库／本地目录改名已按用户要求取消 |
| 三期实施计划 | 已按用户优先级拆分为当前 iOS 双端计划：[00 期](plans/v1.1-phase-00.md) 基础体验与场边工具、[01 期](plans/v1.1-phase-01.md) 个人训练计划、[02 期](plans/v1.1-phase-02.md) 教学内容与团训计划；T04 九宫格点位归 00。本轮已实现 00 期三种计数及其历史、落点地图、工作室导航与图片卡片公共能力，双端按最新适用用例统计 83 项通过、0 失败，iPhone 跳过 1 项 iPad 专属场景，通用设备 Release 编译通过；[00 期验证记录](validation/v1.1-phase-00-validation.md)。S02 保持 Pending；真机条件及完整性能验收保留 |
| 产品设计与待办 | [1.1 功能与模块 TODO](plans/v1.1-todo.md)：按模块编号逐项讨论；视频沿用 [1.0.1 TODO](plans/v1.0.1-todo.md) 与既有进度；[1.0 开发计划](plans/v1.0-development-plan.md)、[1.0 TODO 原文](archive/workspace-2026-11-04/TODO-before.md) 保留原状态 |
| 1.1 入口重构 | [场景入口与导航](plans/v1.1-toolbox-entry.md)：`codex/v1.1-toolbox-entry` 开发分支已接入私教／团训／随手工具入口和记录筛选，工具内容后续逐项完善；[双端针对性验证通过](validation/v1.1-entry-validation.md) |
| 1.1 已有工具 | 秒表、倒计时与 ARKit 测距归随手工具，已实现的横屏战术白板现归团训；[本轮验证](validation/v1.1-quick-tools-validation.md)。真实 AR 距离与精度仍需支持设备验证 |
| 试用反馈 | 投球页压缩为单屏操作，打击分类加轨迹图标，比赛计数增加主客比分。视频时间轴定位后可直接进入绘图。见 [00 期试用反馈调整](plans/v1.1-phase-00.md#2026-11-09-试用反馈调整)。 |
| 开屏 | 与记录大师共用 [Admin 开屏配置](https://baseballmaster.cc/admin/#launch)。发布的背景、文案、排期、时长与启停由 App 冷启动时在后台同步，下载验证成功后下次冷启动采用。iPhone 和 iPad 的系统启动页与内置默认图采用用户选定的 B 版复古球印。默认图的酒红标志取自品牌 1.3 的 `brand/specifications/1.3/assets/drill-buddy-horizontal.svg`（SHA-256 `02d1f55af1c3ce0f1674b72824b3b63316db6b2dacff98bb630937f4a038d112`），App 内 3× PNG 的 SHA-256 为 `5c7511742300adb6ab0abebe6cdb5c6cbefa1a3cf588830c41e47d16d149953f`。Admin 自定义背景上的反白标志取自 `brand/specifications/1.3/assets/drill-buddy-horizontal-reverse.svg`（SHA-256 `9f258d07728bd5797d79bc24f5069e3a914b030dd6dd821e6041151181b4459d`），在 App 内以 3× PNG 使用（SHA-256 `ef9bba2b017ed5dab7da6b9595ab9c3b1115bd580466f667e7fa5efe7d0d7503`）。 |
| 功能验证 | [1.0.1 验证](validation/v1.0.1-validation.md)、[姿态引擎验证](validation/pose-engine-validation.md) |
| 投球分析研究 | [iPhone 摄像头测速、转速、变化量与球种可行性](plans/iphone-pitch-analysis-feasibility.md)：已完成公开片段追踪、合成实验及 10,000 条 Statcast 的五特征转速回归；70 位新投手的 2057 球测试 MAE 约 208rpm，尚未接入 App 或通过真机精度验收 |
| 品牌与图标 | [公共产品品牌规范](../../../brand/COACH-POCKET.md)、[工程图标说明](../design/app-icon/README.md) |
| 目录整理 | [迁移记录](../../../management/MIGRATION.md)，工程、Bundle ID、1.0.1（4）配置保持不变 |

产品支持 iPhone 与 iPad；资料保存在本机，人体识别为辅助估算。1.1 已实现入口层级、记录筛选，以及秒表、倒计时、战术白板、测距、打击记录、投球落点与模拟比赛计数；已有视频分析／对比继续可用，其余 5 个工具标明待完善。计时工具保留当前状态；白板、主动保存的测距及三种计数历史接入记录。投球地图为捕手视角的手动图上落点，使用连续编号和好／坏球分色；不代表摄像头自动追踪或测速。公共图片卡片支持长内容分页、相册和系统分享，00 期通过明确的 Debug 示例验证，真实计划／笔记／练习卡在 01／02 接入；在线链接尚未接入。完整视频性能和长时验收继续按既有记录处理。发布配置仍为 1.0.1（4）。

本机 build/、artifacts/、私有视频、签名配置和历史 IPA 完整保留且继续被 Git 忽略。研究环境在新路径重新建立，原环境和迁移前目录保存在工作区 local/。

2026-11-06 追加布局评审：手机视频横屏大画布、iPad 竖屏上下对比、米白／酒红简洁白板已接入；白板仅参考用户图片的样式，保留 App 配色。边线已进一步改为沿一、三垒延伸，并统一外野弧线的透视几何；追加渲染及双端白板操作检查 3 项通过。实现、兼容规则与本轮独立验证见[视频与白板改版记录](validation/v1.1-media-whiteboard-validation.md)。此项是 00 期的后续迭代，原 83 项证据保留，不能当作改版后完整重跑结果。

2026-11-06 用户授权更新官网，本期功能介绍已作为[首批更新预告](https://baseballmaster.cc/coach-insights#first-update)发布，并按用户反馈扩为[10 张界面图库](https://baseballmaster.cc/coach-insights#screenshots)，覆盖视频分析、动作对比、打击／投球、模拟比赛、白板、秒表、倒计时和记录筛选。视频预览使用 CC0 公开演示素材，不使用私有视频。官网沿用当前已发布英文全名 Baseball Drill Buddy；App 展示名与发布状态沿用上表。

2026-11-09：1.1 第 00 期已提交 [App 草稿 PR #4](https://github.com/chending0418-ship-it/CoachInsights/pull/4)，以 [文档整理 PR #3](https://github.com/chending0418-ship-it/CoachInsights/pull/3) 的分支为审查基线。最新模拟器测试构建与 29 项核心用例通过；未合并、打包或上传。

两份原根目录 Organizer 导出已按包内实际版本归档至工作区 `local/releases/coach-insights/`；路径及 IPA 哈希见 [本地交付索引](../../../management/local-deliveries.json)。原名中的时间戳完整保留。

## 2026-11-26 场边记录与界面评审

新增 [T04-05 投球记录双站位](plans/v1.1-todo.md#t04-05-教练站在投手后方记录2026-11-26待实现)，待实现。以 Git 主线 1.1 Beta（Build 8）评审 iPhone 与 iPad 的现行界面；问题、验收场景与三个可操作方向见[界面与操作评审](design/2026-11-ui-review/README.md)。用户随后选定 A「场边速记」，确认投手后方的本垒板在图上方。手机与 iPad 的[全页高保真原型](design/2026-11-ui-review/a-full/index.html)作为设计依据；原生开发及视频分析故障复现另行安排。
