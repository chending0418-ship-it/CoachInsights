# 本机姿态引擎与质量验证

日期：2026-10-22。仅在 iPhone / iPad 模拟器运行，不要求真机。

## 已实现的选择

`PoseEngine` 将引擎隔离为可替换的 actor。默认尝试 Apple Vision；当前 iOS 26.1 模拟器缺少人体模型，且准备阶段可能停滞，因此模拟器直接使用 MediaPipe Pose Landmarker Full v1；实际 iOS 代码仍保留 Vision 优先及错误回退。SDK 为原生 MediaPipe Tasks 1.1.1，模型在构建前校验哈希并离线打包，不在运行时联网。引擎、版本、最低置信度、区域、片段和源文件哈希组成分析缓存条件；显示开关不触发重算。对比两路独立保存设置。

这解决了模拟器的识别可用性缺口，并未证明定位准确。按用户 2026-10-22 的明确决定，1.0 将人体识别定位为辅助估算，不再以原 90% 目标阻塞交付。Heavy v1 仅作为测试对照下载到忽略的测试目录，没有打入 App；其结果不足以支持替换 Full。

## 数据和方法

- 用户提供的 IMG_9673.mov：原始 3840 × 2160、78 帧，在原生离线 Full 上逐帧运行；可用关节帧数用于功能验证，不视为准确率。
- OpenBiomechanics 官方计算机视觉演示投球：补充 30 个时间点的本机调用与图像核查。它没有用于这里的坐标精度分母。
- Penn Action 公开人工标注：先用诊断集 12 段原片定位左右列顺序及区域问题，再冻结处理参数，用另外 12 段原片每段均匀取 5 帧；投球、打击各 30 帧。验收原片 ID 和逐项统计见 [数值记录](pose-quality-metrics.json)。没有按模型结果挑选帧。
- 采用一段视频固定的主体区域，区域为该片人体框并集加 5% 留边，用于模拟用户选定主体；检测时增加 20% 周边上下文，仅接受主体中心仍位于用户区域内的候选。多人不确定时留空。区域使用了人工人体框，属于有主体区域辅助的评估。
- 使用肩、肘、腕、髋、膝、踝 12 个同义关节，排除定义不同的 head / nose；不可见参考点单列，不进入可见点坐标分母。报告同时列出覆盖率、腕肘、疑似左右混淆及高置信错误，缺失可见点不能当作正确结果。
- 距离按原图像素计算，以人工逐帧人体框高度归一化；PCK@0.05 表示误差不大于该高度 5%。参考指标使用全部可见参考点作分母，另列仅已返回点的定位比例。
- MATLAB 坐标转为从 0 开始的像素。数据配套评估代码明确将 Penn 的 right/left 列换为标准 left/right；坐标和可见性一起按相同列解释。少量标注宽度为 481、无损视频为 480，转换显式按宽度比例修正，最大约 1 像素，不隐藏该差异。

## 结果与发布状态

独立验收集，两端原生推理结果一致（iPhone 16e、iPad mini A17 Pro，iOS 26.1 模拟器）：

| 模型 | 投球 PCK@0.05 / 覆盖率 | 打击 PCK@0.05 / 覆盖率 |
| --- | --- | --- |
| Full v1 | 70.0% / 85.6% | 74.5% / 98.7% |
| Heavy v1，对照 | 68.6% / 81.6% | 76.5% / 88.4% |

两个模型均未达到原计划 90% 的定位门槛。测试包含运动模糊、遮挡、复杂背景和不同镜头条件；这些结果既不证明所有清晰近景都失败，也不能用来承诺清晰近景已达标。模型置信分数不能当作真实定位误差。

2026-10-22 用户已明确接受辅助估算范围：骨架和角度需要人工复核，90% 不再是 1.0 发布门槛。V1-048 改为核查与如实记录识别表现、明确使用限制；V1-062 按该范围确认功能、双端测试及可复现构建。分析、对比、导出和帮助提示点位偏移、左右混淆、缺失及高置信错误；带可见骨架的预览、截图与视频保留“辅助估算 · 请复核”标识。原始精度数据不改写，不宣称已达 90% 或可用于三维测量、自动动作评分。

## 复现

```sh
# 可选研究环境，需要 numpy、opencv-python；不进入 App
.venv/bin/python scripts/prepare_pose_quality.py --include-heavy
python3 scripts/verify.py

# 原生 XCTest 的报告由 verify.py 自动复制到本机 artifacts
python3 scripts/check_pose_quality.py artifacts/iphone/pose-quality-measurements.json artifacts/iphone/pose-quality-heavy-measurements.json --output docs/pose-quality-metrics.json
```

质量脚本默认输出实测数据及是否达到历史参考目标，不因低于 90% 返回失败；数据不完整仍报错。仅研究时可追加 `--strict` 检查历史目标，低于目标返回非零。它不是 1.0 发布步骤。CI 无私有视频与可选公共测试帧时会显式跳过相应用例，不能当作定位精度证据。图像、视频、模型、参考坐标均保留在忽略目录。

## 来源

- [Google MediaPipe iOS 设置](https://developers.google.com/edge/mediapipe/solutions/setup_ios)、[Pose Landmarker 模型与配置](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker)。
- [Penn Action 官方项目](https://dreamdragon.github.io/PennAction/)，Weiyu Zhang、Menglong Zhu、Konstantinos Derpanis，ICCV 2013。
- [无损视频镜像及转换说明](https://huggingface.co/datasets/urzsi/Penn-Action-Lossless-MKV-Test-Subset)，固定修订 ea509384e8bf8cc04c9591c88a60db6bd8e591eb。
- [人工标注镜像及左右列转换依据](https://github.com/KacperM33/OKS_attack/blob/9758d0ac0df9b58f852ba3e76e1f32c4fa150f8d/oks_tools/measures.py#L239)。下载脚本固定源码修订，数值文件与视频哈希保存在本机 provenance。
- [OpenBiomechanics 官方媒体](https://github.com/drivelineresearch/openbiomechanics/releases/tag/cv-media-v1)。
