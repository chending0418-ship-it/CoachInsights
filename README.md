# Coach Insights

面向棒球教练和家长的本地视频分析工具，覆盖打击与投球。

## 1.0 范围

- 同时支持 iPhone 和 iPad，视频与分析数据分别保存在各自设备。
- 不使用 iCloud 同步，不要求登录账号。
- 支持拍摄、导入、慢放、逐帧查看、画面标注和双视频对比。
- 支持人体姿态叠加与分析结果导出分享。

球棒轨迹、棒头/握柄自动追踪及专用轨迹校正工具已从 1.0 范围移除。通用画面标注仍支持直线、圆框与自由手绘。

## 开发执行

由 Codex 按任务依赖实现和验证，不设置人工开发排期。

- [1.0 TODO](TODO.md)：任务状态、完成条件与执行规则。
- [1.0 开发计划](docs/v1.0-development-plan.md)：产品行为、技术方案、实现顺序、双端验收与风险处理。

## 当前进度

已建立原生 Universal Xcode 工程，当前交付范围为 TODO A–C（工程与页面骨架、媒体基础、本机数据）。主题为勃艮第红 `#722F37`。完整拍摄、分析编辑、对比和导出在 D–J 继续实现。

开发与验收统一使用 iPhone、iPad 模拟器，不要求实体设备。人体引擎暂选 Apple Vision；当前 iOS 26.1 模拟器的 Vision 人体模型缺失，探针已明确报告不可用，尚未通过识别可用性或质量门禁。后续 H 阶段需解决模拟器推理，再进行人体质量验收；保留 MediaPipe Full 备选。

已有球棒追踪代码、数值结果及报告作为历史研究资料保留；BootsTAPIR 不作为当前 1.0 的开发或部署依赖。

## 构建与验证

使用 Xcode 打开 `CoachInsights.xcodeproj`，选择 `CoachInsights` scheme 与 iPhone / iPad 模拟器运行；最低部署版本为 iOS / iPadOS 17。当前验证环境为 Xcode 26.1.1、iOS 26.1。原生 App 无第三方依赖。

```sh
# 创建或复用项目专用模拟器，依次构建、运行单元与 UI 测试
python3 scripts/verify.py

# 可选：加入用户提供的本机回归视频；视频不会进入 Git
python3 scripts/verify.py --regression /absolute/path/IMG_9673.mov
```

可通过 `--device iphone` / `--device ipad` 选择一端，`--unit-only` 仅运行核心测试。日志、xcresult、探针 JSON 存放在忽略的 `artifacts/`，验证构建位于 `build/DerivedData/Build/Products/Debug-iphonesimulator/CoachInsights.app`；本轮另有不含测试资源与 Debug 探针的 Release 构建 `build/ReleaseData/Build/Products/Release-iphonesimulator/CoachInsights.app`。未提供私有视频时，该用例标记跳过，合成媒体测试照常运行。

[ABC 验收记录](docs/abc-validation.md) 说明当前能力、模拟器结果与后续门禁。自动工作流也运行同一入口；云端 CI 结果以 GitHub Actions 实际运行状态为准。

## 仓库内容

| 路径 | 内容 |
| --- | --- |
| `CoachInsights/` | SwiftUI 页面、UIKit 视频承载、原生媒体服务与本机数据层 |
| `CoachInsightsTests/` / `CoachInsightsUITests/` | 媒体、几何、数据安全与双端界面自动化 |
| `scripts/verify.py` | 仅使用模拟器的构建验证入口 |
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
