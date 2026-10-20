# Coach Inside

面向棒球教练和家长的本地视频分析工具，覆盖打击与投球。

## 1.0 范围

- 同时支持 iPhone 和 iPad，视频与分析数据分别保存在各自设备。
- 不使用 iCloud 同步，不要求登录账号。
- 支持拍摄、导入、慢放、逐帧查看、画面标注和双视频对比。
- 球棒轨迹直接采用半自动流程：用户初始化、自动追踪、人工校正。
- 支持人体姿态叠加与分析结果导出分享。

## 当前进度

当前已完成第一轮 Mac 本机识别与追踪实验，尚未建立可发布的 iOS App。

人体姿态暂选 Apple Vision，保留 MediaPipe Full 的替换方案。球棒半自动追踪优先验证 BootsTAPIR 的 iOS 部署可行性。以上是阶段性选择；尚未完成 iPhone、iPad 真机性能、内存与识别质量验收。

## 仓库内容

| 路径 | 内容 |
| --- | --- |
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
