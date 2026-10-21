# Pinned MediaPipe Tasks native distribution

The checked-in package manifest is Google's [Package.swift](https://github.com/google-ai-edge/mediapipe/blob/0e152b35eeea3cc9e8b55886428982b82de5925b/Package.swift), pinned to the native 1.1.1 release URLs and SHA-256 checksums. Binary archives are fetched by Swift Package Manager; no framework binaries are stored in Git. `Sources/MediaPipeTasksCommon/Exports.swift` is the local shim needed for the Common Swift target. Static calculator registration requires the upstream `-all_load` linker setting and all upstream binary dependencies.

Actual 1.1.1 archives include arm64 iPhone/iPad and arm64 simulator slices. The project therefore excludes x86_64 simulator builds; use an Apple Silicon Mac or the arm64 GitHub Actions runner. The minimum App deployment target remains iOS/iPadOS 17.

The Full v1 model is prepared separately by `scripts/prepare_dependencies.py`, checksum verified and copied into the App at build time. Runtime inference is offline. The optional Heavy comparison model belongs only to the ignored test fixtures and is never an App resource.

Upstream [iOS setup](https://developers.google.com/edge/mediapipe/solutions/setup_ios), [Pose Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker), and Apache 2.0 license: [LICENSE](LICENSE). A copy of the license is displayed in the App.

## 随 App 提供的隐私资源

官方 1.1.1 二进制压缩包未携带隐私清单。App 另行携带其底层依赖的原始上游清单与许可：

- `CoachInsights/Resources/Abseil_Privacy.bundle`：来自 [Abseil 20260526.0](https://github.com/abseil/abseil-cpp/tree/20260526.0)，清单 SHA-256 `f232217ae9edf2ab6a541a28eff50cfe05303c2b4756fff95cca72eccbc3b898`。
- `CoachInsights/Resources/Protobuf_Privacy.bundle`：来自 [Protobuf v6.31.1](https://github.com/protocolbuffers/protobuf/tree/v6.31.1)，清单 SHA-256 `521eb6ef8430773e5c010e1838fe9dd8fa5d62b7b76d1cea8d7d8daadcb144e2`。

版本来源对应固定 MediaPipe 源码清单的 `MODULE.bazel`。两份清单按上游原文保留；本项目的文件时间、磁盘空间访问理由声明在 App 自己的清单中。MediaPipe 的静态 task graphs 并入 App 可执行文件，其余 6 个框架是动态框架，不能将整个 SDK 视为静态库。当前官方二进制未提供这 6 个动态框架的 dSYM；App 自己的 dSYM 在本地归档检查中匹配验证。此资源补充不代替 Apple 对 SDK 签名、隐私清单和上传的最终校验。
