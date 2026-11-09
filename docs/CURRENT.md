# 棒球训练助手 Drill Buddy 当前入口

2026-11-09 用户确认：迄今的构建均为 Beta，包括 1.1 第 00 期 TestFlight 构建 1.1（5）。首次 App Store 正式发布版本号从 1.0.0 开始。正式发布时用 1.0.0 单独归档，构建号按当时 App Store Connect 的上传记录确定。

更新日期：2026-11-09。用户确认产品中文名为“棒球训练助手”，英文名为 Drill Buddy（原名：教练口袋 / Coach Insights），面向棒球教练、家长和球员。工程名 CoachInsights、Bundle ID、本机数据目录及版本号保持稳定。

本轮已同步 App 首页、帮助、白板图片署名、通知、相册权限错误提示及中英文系统展示名。官网更名已于 2026-11-05 部署，品牌文字 Logo 已同步，见[更名发布记录](../../../website/deploy/2026-11-05-drill-buddy-rename.md)；商店名称尚未发布更新；历史发布／验证记录及冻结品牌参考保留原名。更名后模拟器 Debug 构建通过，中英文名称资源、Bundle ID 与 1.0.1（4）已核对，证据位于 `artifacts/validation/name-change/`。命名依据见[品牌命名修订](../../../brand/specifications/1.2/README.md)。

2026-11-06 当前平台方向：先规划 iOS 的 iPhone 与 iPad，范围和规则明确后先完成 iOS 设计、开发与验收。Android Phone 是后续目标，视频模型、解码与分析结果的可行性尚未验证，不再承诺三端同期交付。

| 项目 | 当前依据 |
| --- | --- |
| 版本来源 | `Config/Build.xcconfig`：1.1（Build 5） |
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
| 功能验证 | [1.0.1 验证](validation/v1.0.1-validation.md)、[姿态引擎验证](validation/pose-engine-validation.md) |
| 品牌与图标 | [公共产品品牌规范](../../../brand/COACH-POCKET.md)、[工程图标说明](../design/app-icon/README.md) |
| 目录整理 | [迁移记录](../../../management/MIGRATION.md)，迁移时工程、Bundle ID 与当时的版本配置保持不变 |

产品支持 iPhone 与 iPad；资料保存在本机，人体识别为辅助估算。1.1 已实现入口层级、记录筛选，以及秒表、倒计时、战术白板、测距、打击记录、投球落点与模拟比赛计数；已有视频分析／对比继续可用，其余 5 个工具标明待完善。计时工具保留当前状态；白板、主动保存的测距及三种计数历史接入记录。投球地图为捕手视角的手动图上落点，使用连续编号和好／坏球分色；不代表摄像头自动追踪或测速。公共图片卡片支持长内容分页、相册和系统分享，00 期通过明确的 Debug 示例验证，真实计划／笔记／练习卡在 01／02 接入；在线链接尚未接入。完整视频性能和长时验收继续按既有记录处理。00 期 TestFlight 候选的发布配置为 1.1（5）。

本机 build/、artifacts/、私有视频、签名配置和历史 IPA 完整保留且继续被 Git 忽略。研究环境在新路径重新建立，原环境和迁移前目录保存在工作区 local/。

2026-11-06 追加布局评审：手机视频横屏大画布、iPad 竖屏上下对比、米白／酒红简洁白板已接入；白板仅参考用户图片的样式，保留 App 配色。边线已进一步改为沿一、三垒延伸，并统一外野弧线的透视几何；追加渲染及双端白板操作检查 3 项通过。实现、兼容规则与本轮独立验证见[视频与白板改版记录](validation/v1.1-media-whiteboard-validation.md)。此项是 00 期的后续迭代，原 83 项证据保留，不能当作改版后完整重跑结果。

2026-11-06 用户授权更新官网，本期功能介绍已作为[首批更新预告](https://baseballmaster.cc/coach-insights#first-update)发布，并按用户反馈扩为[10 张界面图库](https://baseballmaster.cc/coach-insights#screenshots)，覆盖视频分析、动作对比、打击／投球、模拟比赛、白板、秒表、倒计时和记录筛选。视频预览使用 CC0 公开演示素材，不使用私有视频。官网沿用当前已发布英文全名 Baseball Drill Buddy；App 展示名与发布状态沿用上表。

2026-11-09：1.1 第 00 期已提交 [App 草稿 PR #4](https://github.com/chending0418-ship-it/CoachInsights/pull/4)，以 [文档整理 PR #3](https://github.com/chending0418-ship-it/CoachInsights/pull/3) 的分支为审查基线。最新模拟器测试构建与 29 项核心用例通过；未合并、打包或上传。

两份原根目录 Organizer 导出已按包内实际版本归档至工作区 `local/releases/coach-insights/`；路径及 IPA 哈希见 [本地交付索引](../../../management/local-deliveries.json)。原名中的时间戳完整保留。

2026-11-09：用户启动 1.1 第 00 期 TestFlight 验收。本次候选使用 1.1（5），沿用原 Bundle ID，范围以 PR #4 的 00 期实现为准。01 期仍暂停。是否已可安装以 App Store Connect 处理及测试组状态为准。

2026-11-09：根据 1.1（5）的 TestFlight 真机反馈，在 `codex/v1.1-beta-feedback` 调整视频分析、选片页与三种计数页。进入绘图时恢复标注显示，绘制中独立刷新叠层。双端以截图像素验证箭头和圆框、切帧后隐藏与恢复，以及相邻缩略图点击区域互不重叠。三种计数的撤销、保存重开和投球纠错通过模拟器检查。手动全屏用例通过。模拟器自动转屏用例仍失败，iPhone 在原 Build 5 源码上也复现，留待真机复核。证据在 `artifacts/validation/beta-feedback/`。本轮为本机修复，等待下一次 Beta 打包与真机验收。
