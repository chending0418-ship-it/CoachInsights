# Pinned MediaPipe Tasks native distribution

The checked-in package manifest is Google's [Package.swift](https://github.com/google-ai-edge/mediapipe/blob/0e152b35eeea3cc9e8b55886428982b82de5925b/Package.swift), pinned to the native 1.1.1 release URLs and SHA-256 checksums. Binary archives are fetched by Swift Package Manager; no framework binaries are stored in Git. `Sources/MediaPipeTasksCommon/Exports.swift` is the local shim needed for the Common Swift target. Static calculator registration requires the upstream `-all_load` linker setting and all upstream binary dependencies.

Actual 1.1.1 archives include arm64 iPhone/iPad and arm64 simulator slices. The project therefore excludes x86_64 simulator builds; use an Apple Silicon Mac or the arm64 GitHub Actions runner. The minimum App deployment target remains iOS/iPadOS 17.

The Full v1 model is prepared separately by `scripts/prepare_dependencies.py`, checksum verified and copied into the App at build time. Runtime inference is offline. The optional Heavy comparison model belongs only to the ignored test fixtures and is never an App resource.

Upstream [iOS setup](https://developers.google.com/edge/mediapipe/solutions/setup_ios), [Pose Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker), and Apache 2.0 license: [LICENSE](LICENSE). A copy of the license is displayed in the App.

## 随 App 提供的隐私资源

官方 1.1.1 二进制压缩包未携带隐私清单。App 另行携带其底层依赖的原始上游清单与许可：

- `CoachInsights/Resources/Abseil_Privacy.bundle`：来自 [Abseil 20260526.0](https://github.com/abseil/abseil-cpp/tree/20260526.0)，清单 SHA-256 `f232217ae9edf2ab6a541a28eff50cfe05303c2b4756fff95cca72eccbc3b898`。
- `CoachInsights/Resources/Protobuf_Privacy.bundle`：来自 [Protobuf v6.31.1](https://github.com/protocolbuffers/protobuf/tree/v6.31.1)，清单 SHA-256 `521eb6ef8430773e5c010e1838fe9dd8fa5d62b7b76d1cea8d7d8daadcb144e2`。

版本来源对应固定 MediaPipe 源码清单的 `MODULE.bazel`。两份清单按上游原文保留；本项目的文件时间、磁盘空间访问理由声明在 App 自己的清单中。此资源补充不代替 Apple 对 SDK 签名、隐私清单和上传的最终校验。

## 静态链接与归档中的 dSYM

直接检查 1.1.1 下载内容可见，6 个 `.framework` 的原始二进制都是 `ar` 静态归档，task graphs 也是静态库。Xcode 26.1.1 会复制这些框架的外壳、删除其中的静态二进制，再为没有资源的外壳注入空的动态库。旧的 `1.0 (1)` 包因此包含 6 个没有对应 dSYM 的空动态库，并触发 `Upload Symbols Failed`。此前将这些构建产物视为上游动态框架的说明已更正。

从 `1.0 (2)` 起，App 最后的构建阶段执行 `scripts/mediapipe_static_packaging.py`，在最终签名前清理这些无用外壳。它逐个检查链接输入确实是静态归档、输出没有任何非空 Mach-O section 或导出符号、没有需要保留的资源，并扫描整个 App 的 Mach-O 运行时依赖。所有检查通过才删除已知的 6 个外壳；任一检查不符则构建失败，原内容保留。未来 SDK 变成动态库或加入资源时必须重新处理集成，不能放宽检查直接删除。

脚本仅修改本次构建产物，不修改 SPM 下载、原始 SDK、旧归档或已上传的包。App target 的脚本沙箱关闭以允许该构建阶段修改前面的嵌入阶段输出；代码签名、SDK 签名验证和符号上传均保持原流程。

MediaPipe 的实现仍来自上述固定版本的静态库并链接进 App，App 自己的 dSYM 必须保留且 UUID 匹配。本修正不生成或伪造 SDK dSYM，也无法恢复上游未提供的源码行号信息。归档检查额外要求无 MediaPipe 外壳、无对应动态依赖、所有实际嵌入的其他动态框架符号匹配。保护测试用真实编译的 Mach-O 二进制验证清理、幂等、保留代码/资源、依赖拒绝和符号链接保护。

依据：[Apple 静态框架说明](https://developer.apple.com/documentation/xcode/creating-a-static-framework)、[Apple 工程师对静态代码与 dSYM 的说明](https://developer.apple.com/forums/thread/761589)。
