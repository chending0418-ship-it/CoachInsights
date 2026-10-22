# Coach Insights

面向棒球教练和家长的本地视频分析工具，覆盖打击与投球。

## 1.0 范围

- 同时支持 iPhone 和 iPad，视频与分析数据分别保存在各自设备。
- 不使用 iCloud 同步，不要求登录账号。
- 支持拍摄、导入、慢放、逐帧查看、画面标注和双视频对比。
- 人体识别作为辅助估算，支持骨架 / 二维角度叠加与分析结果导出分享，点位需要人工复核。

球棒轨迹、棒头/握柄自动追踪及专用轨迹校正工具已从 1.0 范围移除。通用画面标注仍支持直线、圆框与自由手绘。

## 开发执行

由 Codex 按任务依赖实现和验证，不设置人工开发排期。

- [1.0 TODO](TODO.md)：任务状态、完成条件与执行规则。
- [1.0.1 测试版修改 TODO](docs/v1.0.1-todo.md)：参考 CoachNow 的视频观看与操作体验，规划播放流畅度、工具布局、双视频对比和无需订阅的分析流程；功能已实现，双端主要回归通过，完整性能与长时资源验收待人工测试；见 [1.0.1 验证记录](docs/v1.0.1-validation.md)。
- [1.0 开发计划](docs/v1.0-development-plan.md)：产品行为、技术方案、实现顺序、双端验收与风险处理。

## 当前进度

当前 1.0.1 (3) Release 已安装并启动于 iPhone / iPad 项目专用模拟器：优化视频观看与定位、绘图及对比交互，修复人体叠加拖动同步。双端主要回归已通过；用户取消后续长时自动测试，完整性能验收待人工测试。见 [1.0.1 验证记录](docs/v1.0.1-validation.md)。原 1.0 的 62 项 Todo 完成状态保留。

已接入完整的本机视频流程：拍摄 / 相册 / 文件导入、逐帧与五档慢放、可编辑标注、关键帧、双视频同步、离线骨架和二维角度、截图 / 单视频 / 双路合成导出。iPhone、iPad 共用原生 Universal 工程，主题为勃艮第红 `#722F37`，使用已确认的棒球瞳孔图标。

[1.0 验收记录](docs/v1.0-validation.md) 说明代码、测试和构建。2026-10-22 用户确认人体识别以**辅助估算**交付，原 90% 定位目标保留为研究参考，不作为 1.0 发布门槛。遮挡、模糊、侧身和多人场景可能出现点位偏移、左右肢混淆或缺失，高置信度也可能出错；请逐帧人工复核。分析、对比、导出和使用说明均提示限制，带骨架的导出保留估算标识。具体样本与 Full / Heavy 实测数据见 [姿态引擎验证](docs/pose-engine-validation.md)，不将原始结果表述为已达到 90%。

开发与验收统一使用模拟器，不要求真机。模拟器直接使用原生 MediaPipe Full，避开当前运行时缺少 Vision 模型及准备阶段停滞的问题；实际 iOS 代码保留 Vision 优先及错误回退。模型随 App 离线提供，视频不上传。历史球棒追踪研究保留查阅，没有进入 1.0 App。

## 构建与验证

使用 Apple Silicon Mac 与 Xcode 26.1.1 或兼容版本；最低部署目标 iOS / iPadOS 17。当前原生依赖的模拟器二进制仅支持 arm64，CI 使用 `macos-26` runner。

```sh
# 首次构建：校验并准备离线模型，再打开 Xcode 工程
python3 scripts/prepare_dependencies.py
python3 scripts/generate_project.py

# 两类专用模拟器，构建并运行单元 / UI 测试
python3 scripts/verify.py

# 可选本机回归片段；不进入 Git
python3 scripts/verify.py --regression /absolute/path/IMG_9673.mov

# 生成 Release 并安装到项目专用 iPhone / iPad 模拟器
python3 scripts/build_simulator_release.py --install
```

`--device iphone` / `--device ipad` 选择一端，`--unit-only` 运行核心测试。结果保存在忽略的 `artifacts/`；Release 位于 `build/ReleaseV1/Build/Products/Release-iphonesimulator/CoachInsights.app`。可选私有视频、公开质量样本或系统相册测试素材缺失时，相应用例明确跳过，不能视为识别质量通过。

公开人工标注质量集可使用含 numpy、opencv-python 的研究 Python 环境执行 `scripts/prepare_pose_quality.py --include-heavy`；依赖、帧和模型不进入原生 App。质量评估脚本与判定方式见姿态验证记录。SPM 原生依赖和许可见 [MediaPipe 包说明](Packages/MediaPipeTasks/README.md)。

## TestFlight

签名、App Store Connect 建档、归档、内部 / 外部测试步骤和可复制文案见 [TestFlight 操作说明](docs/testflight-guide.md)。版本号配置位于 `Config/Build.xcconfig`，当前为 `1.0.1 (3)`；本机 Team 可写入被 Git 忽略的 `Config/Signing.local.xcconfig`。

新版在最终签名前清理 Xcode 为静态 MediaPipe 框架生成的 6 个空外壳，以消除缺少 dSYM 的上传警告；SDK 实现仍静态链接，模型与分析逻辑保持不变。清理会检查代码、资源与运行时依赖，不满足条件则停止构建。详情见 [MediaPipe 打包说明](Packages/MediaPipeTasks/README.md)。旧的 `1.0 (1)` 归档与 TestFlight 构建不受修改。

```sh
# 本地未签名 iOS 归档与包检查，不签名、不上传、不连接设备
python3 scripts/prepare_testflight.py

# 可选：使用已准备的本机 Regression.mov 验证优化 Release 宿主中的真实人体识别
python3 scripts/verify_release_pose.py
```

结果位于 `artifacts/testflight/`。该检查不等于 Apple 上传校验，未签名归档不可直接分发；请由你在 Xcode 选择付费开发者 Team 后重新 Archive 并上传。隐私政策发布正文见 [隐私政策](docs/privacy-policy.md)，发布前填写真实联系邮箱。

## 仓库内容

| 路径 | 内容 |
| --- | --- |
| `CoachInsights/` | SwiftUI 页面、UIKit 视频承载、原生媒体服务与本机数据层 |
| `CoachInsightsTests/` / `CoachInsightsUITests/` | 媒体、几何、数据安全与双端界面自动化 |
| `scripts/verify.py` / `build_simulator_release.py` | 双端验证、Release 构建和安装 |
| `Packages/MediaPipeTasks/` | 固定原生 SDK 清单及许可，二进制不入 Git |
| `docs/v1.0-validation.md` / `pose-engine-validation.md` | 功能验收与人体估算的实测限制 |
| `TODO.md` | 1.0 开发任务与完成状态 |
| `docs/v1.0-development-plan.md` | 1.0 技术方案和验收依据 |
| `research/project_decisions.json` | 已确认的产品范围与阶段性技术选择 |
| `research/README.txt` | 研究说明和复现步骤 |
| `research/*.swift` | AVFoundation 解码、Vision 姿态与追踪实验 |
| `research/*.py` | MediaPipe、OpenCV、BootsTAPIR 对比及报告生成 |
| `research/fixtures/img_9673/` | 本次视频的人工初始化点与近似检查点 |
| `research/benchmarks/2026-10-20/summary.json` | 第一轮测试的数值汇总与限制说明 |
| `research/provenance.json` | 模型与第三方源码的来源及文件哈希 |
| `research/vendor/tapnet/` | 本次实验使用的官方 TAPIR 源码及许可 |

## 本地数据

原视频、解码帧、测试截图、生成视频与 HTML 报告、模型权重、虚拟环境均不纳入 Git。需要在本机准备素材与模型后，按研究说明重新生成结果。

第一轮实验只使用一个打击片段。人体检出率不等于关键点准确率；人工检查点是目视近似值；最模糊的高速挥棒帧不作为精确定位基准。Mac 实验耗时不能视为 iOS 性能。

## 第三方许可

TAPIR 第三方代码的原始许可保留在 `research/vendor/tapnet/LICENSE`；模型与源码来源记录在 `research/provenance.json`。本项目尚未指定整体开源许可。
