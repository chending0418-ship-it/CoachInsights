# 教练口袋 Coach Insights 当前入口

更新日期：2026-10-22。品牌中文名为“教练口袋”，工程及英文名称保留 Coach Insights。

| 项目 | 当前依据 |
| --- | --- |
| 版本来源 | `Config/Build.xcconfig`：1.0.1（Build 4） |
| 用户确认已上传 | 1.0.1（Build 3） |
| Build 4 | 已有本地未签名归档与包检查报告保留在 `artifacts/build-4-main/`、`artifacts/testflight/`；本地材料不代表 Apple 上传成功 |
| 上传状态 | 本轮没有执行上传、审核或发行，Build 4 是否上传以用户确认或回执为准 |
| 版本交接 | [TestFlight 操作说明](releases/testflight-guide.md)、[Build 4 审查](releases/1.0.1/build-4-review.md) |
| 产品设计与待办 | [1.0.1 TODO](plans/v1.0.1-todo.md)、[开发计划](plans/v1.0-development-plan.md)、[1.0 TODO 原文](archive/workspace-2026-11-04/TODO-before.md) |
| 功能验证 | [1.0.1 验证](validation/v1.0.1-validation.md)、[姿态引擎验证](validation/pose-engine-validation.md) |
| 品牌与图标 | [公共产品品牌规范](../../../brand/COACH-POCKET.md)、[工程图标说明](../design/app-icon/README.md) |
| 目录整理 | [迁移记录](../../../management/MIGRATION.md)，工程、Bundle ID、1.0.1（4）配置保持不变 |

产品支持 iPhone 与 iPad；视频及分析资料保存在本机，人体识别为辅助估算。完整性能和长时验收继续按既有记录处理，本轮只做迁移所需的本地编译、启动与包检查。

本机 build/、artifacts/、私有视频、签名配置和历史 IPA 完整保留且继续被 Git 忽略。研究环境在新路径重新建立，原环境和迁移前目录保存在工作区 local/。

两份原根目录 Organizer 导出已按包内实际版本归档至工作区 `local/releases/coach-insights/`；路径及 IPA 哈希见 [本地交付索引](../../../management/local-deliveries.json)。原名中的时间戳完整保留。
