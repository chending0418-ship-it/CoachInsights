# Coach Insights：TestFlight 上传

本地准备日期：2026-10-22。由你操作 Apple 账号、签名、上传与邀请；项目继续在 `codex/1.0-development`，不合并 `main`。

## 已准备的内容

| 项目 | 当前值 |
| --- | --- |
| App 名称 | Coach Insights |
| Bundle Identifier | `com.coachinsights.CoachInsights` |
| Version / Build | `1.0` / `2` |
| 支持设备 | iPhone、iPad，同一个 Universal App |
| 最低系统 | iOS / iPadOS 17.0 |
| 归档配置 | Release，arm64 iOS |
| 数据 | 本机保存，无账号、无 iCloud 同步 |
| 图标 | 已确认的勃艮第红棒球瞳孔图标 |

版本和 Bundle ID 的默认值在 `Config/Build.xcconfig`，生成工程不会重置该文件。本机 Team / Bundle ID 可写入 Git 忽略的 `Config/Signing.local.xcconfig`，参考同目录 `.example` 文件。

已提供离线模型、权限用途说明、App 隐私清单、Abseil / Protobuf 上游隐私清单及许可、非豁免加密声明。当前 App 仅用 Apple CryptoKit 的 SHA-256 对本机文件去重，不提供自定义加密或通信功能；`ITSAppUsesNonExemptEncryption = NO` 反映当前实现。以后添加网络、加密或更换 SDK 时重新核对。

`scripts/prepare_testflight.py` 构建**未签名 iOS 归档**，检查双端支持、SDK、图标、模型哈希、隐私文件、应用 dSYM 和测试素材隔离。报告在 `artifacts/testflight/preflight.json`，构建日志在同目录 `archive.log`。它不访问 Apple 账号，不执行签名、上传或邀请；未签名归档不能直接用于 TestFlight。Apple 的账号、SDK 签名和服务端校验仍需在你的正式上传流程完成。

## 1. 确认 Apple 开发者账号

1. 在 [Apple Developer 账号](https://developer.apple.com/account/) 确认加入有效的 **Apple Developer Program**。Xcode 免费 Personal Team 无法分发 TestFlight。
2. 登录 [App Store Connect](https://appstoreconnect.apple.com/)，如有待接受的协议，由 Account Holder 先完成。
3. Xcode → Settings → Accounts，登录这个开发者账号，确认能看到对应的付费 Team。

本机当前只检测到 Development 签名身份，未检测到 Distribution 身份；这不代表你的付费资格是否有效。上传时可由有权限的账号使用 Xcode 自动管理分发签名，无需先手工导出证书。

## 2. 注册 Bundle ID，并创建 App

如果你已经建立相同 Bundle ID 的 App，复用原记录。

1. 在 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → Identifiers → `+` → App IDs → App，注册 Explicit Bundle ID：`com.coachinsights.CoachInsights`，描述填写 Coach Insights。当前功能不需要额外启用 iCloud、推送等 capability。
2. App Store Connect → Apps → `+` → New App，填写：

| 字段 | 填写值 |
| --- | --- |
| Platforms | iOS（同时覆盖本项目的 iPhone 与 iPad） |
| Name | Coach Insights |
| Primary Language | 简体中文 |
| Bundle ID | 上一步注册的 `com.coachinsights.CoachInsights` |
| SKU | `coach-insights-ios`，或你账号中另一个未使用的内部编号 |
| User Access | 按你的团队需要选择 |

如果名称或 Bundle ID 已被占用，在**首次上传之前**决定可用的新值。Bundle ID 必须与 Xcode 最终归档一致；可在 `Signing.local.xcconfig` 设置 `COACH_INSIGHTS_BUNDLE_IDENTIFIER`，以后保持不变。不要为 iPhone、iPad 各建一个 App。

## 3. 在 Xcode 选择签名

打开 `/Users/JasonChan/Documents/CoachInsights/CoachInsights.xcodeproj`，等待 Package Dependencies 解析完成。本机已经准备好模型；换电脑或重新拉仓库时，先在仓库目录执行：

```sh
python3 scripts/prepare_dependencies.py
python3 scripts/generate_project.py
```

选择左侧项目 → TARGETS 中 **CoachInsights**：

1. Signing & Capabilities → 勾选 **Automatically manage signing**。
2. Team → 选择有效的付费开发者 Team。
3. 确认 Bundle Identifier 与 App Store Connect 的记录一致。
4. General 中确认 Version `1.0`、Build `2`。`1.0 (1)` 已上传，本次修正使用新的构建号；若 `2` 也已使用，先把 `Config/Build.xcconfig` 的 `CURRENT_PROJECT_VERSION` 改为比已上传构建更大的数。

为了以后运行生成脚本也保留 Team，建议复制 `Config/Signing.local.xcconfig.example` 为 `Config/Signing.local.xcconfig`，将 `DEVELOPMENT_TEAM` 的注释去掉，填写开发者账号 Membership details 中的真实 Team ID。该本机文件不会推送。仅在 Xcode 界面选择的 Team 在下次重新生成工程时会被清除；本次选择后可以直接归档，无需再次生成。

## 4. Archive 并上传

1. 顶部 Scheme 选 **CoachInsights**，运行目标选 **Any iOS Device (arm64)** 或对应的通用 iOS 目标。不要选 iPhone / iPad 模拟器。
2. 菜单 Product → Archive。无需连接真机，Archive 使用 Release 配置。
3. 完成后 Window → Organizer → Archives，选择**刚刚由你签名生成**的 CoachInsights 归档。不要选本项目脚本生成的 `CoachInsights-unsigned.xcarchive`。
4. 点击 **Distribute App**，选择 **TestFlight & App Store / App Store Connect**（名称随 Xcode 版本略有不同），按向导使用自动签名、上传符号并上传。如果走 Custom 流程，选择 App Store Connect → Upload。
5. 预计要邀请教练、家长等外部测试者时，使用上述普通分发选项；**TestFlight Internal Only** 会将这次构建限制为内部测试。
6. 完成向导中的校验与 Upload，保存成功结果。若有 Validate App 入口，可先校验。选择这里的 App Store Connect 分发不会自动把 App 公开上架。

当前使用 Xcode 26.1.1 / iOS 26.1 SDK，满足 Apple 已公布的 2026-04-28 起 iOS 26 SDK 或更高的最低上传要求。具体上传校验结果以 Apple 当时返回为准。

## 5. 在 TestFlight 中启用测试

回到 App Store Connect → Coach Insights → TestFlight，等待构建处理完成。若提示 Missing Compliance，查看其问题并按当前实际实现回答；工程已声明不使用非豁免加密。

**先给自己测试：** Internal Testing → `+` 建立组 → Add Builds 选择刚上传的 `1.0` 构建 → Invite Testers 选择你自己。内部测试者必须是拥有该 App 访问权限的 App Store Connect 用户。不要为了邀请家长而给他们后台开发者权限。

**邀请教练和家长：** 填写 Test Information（下面附可复制文案和需要你填写的联系信息），创建 External Testing 组，添加构建并提交 **TestFlight App Review**。首次外部构建需审核；审核通过并启用后，通过邮箱邀请或公开链接邀请。外部测试者不需要加入你的 App Store Connect 团队。

测试者在 iPhone / iPad 安装 [TestFlight](https://testflight.apple.com/)，通过邀请或链接安装 Coach Insights。每个构建可测试 90 天；之后需要上传新构建。两个设备的数据分别存储，不会互通。

## 本地验证记录

2026-10-22 使用 Xcode 26.1.1 完成 `1.0 (2)` Release iOS 未签名归档，21 项包检查全部通过。归档中的 App 约 39.91 MiB（不是 IPA 或 TestFlight 下载体积），离线模型 SHA-256 与固定值一致，应用 dSYM UUID 与可执行文件匹配，没有测试视频或 Debug 动态库。1024 × 1024 App 图标没有 alpha 通道。补充的两份第三方隐私资源实际进入归档。6 个空 MediaPipe 外壳已在最终签名前移除，缺少 dSYM 的嵌入框架为 0，应用也没有对它们的运行时动态依赖。

本次修正重新执行双端全量回归：81 项通过、0 失败、1 项 iPad 专用场景在 iPhone 上跳过；两端均实际执行打击 / 投球识别、标注、对比与导出。另有 9 项打包保护测试通过，以及 iPhone / iPad 各 1 项独立 Release 人体识别测试通过。Release 专项从新的构建目录开始，测试宿主开启 testability 以调用内部 API，没有给 App 开启 DEBUG 或加入素材生成工具。

同一配置的正式模拟器 Release 已重新构建，并在项目专用 iPhone 16e 与 iPad mini A17 Pro 模拟器安装、启动。详细验证见 `docs/v1.0-validation.md`。未执行 Apple 账号签名、上传或服务端校验，也不要求真机验收。

另用模拟器 ad-hoc 签名验证构建顺序为“嵌入框架签名 → 清理空外壳 → App 最终签名”，严格签名完整性检查通过；该检查不使用 Apple 账号证书。

## 6. 可复制的测试信息

### Beta App Description

```text
Coach Insights 是为棒球教练与家长设计的本机视频分析工具，支持 iPhone 和 iPad。

可拍摄或导入打击、投球视频，进行慢速播放、逐帧查看、画面标注和双视频对比，并导出截图或分析视频。

人体骨架和二维关节角度仅作辅助估算。遮挡、运动模糊、侧身或多人场景可能导致点位偏移、左右肢混淆或缺失；高置信度也可能出错，请逐帧人工复核。

无需注册账号。视频与分析记录保存在本机，不进行 iCloud 同步；用户可主动导出分享。本版本不包含球棒轨迹追踪。
```

### What to Test

```text
请重点测试：
1. 拍摄，或从相册、文件导入棒球打击/投球视频。
2. 慢放、逐帧拖动、循环区间与关键帧定位。
3. 直线、箭头、圆框、手绘、文字及角度标注，保存后重新打开。
4. 两个视频的同屏对比与同步点调整。
5. 人体骨架/二维角度的辅助估算及限制提示。请人工复核点位，不作为自动评分。
6. 截图、单路视频、双视频导出与分享。
7. iPhone/iPad 横竖屏布局，导入/导出取消后的恢复。

反馈时请附设备型号、系统版本、复现步骤与截图。视频素材只在你主动选择发送时分享，请先确认分享意愿。
```

### TestFlight App Review Notes

```text
No sign-in or demo account is required. All core analysis works offline.

To review: tap the + button in the video library, import a local video from Photos or Files (or record one), then open it for frame-by-frame playback and annotation. Import a second video to try side-by-side comparison. Use export to share a screenshot or rendered video.

Camera, microphone and photo-library permissions are requested only for the relevant user actions. Import from Files can be used without granting photo-library access.

Pose landmarks and 2D angles are auxiliary estimates, with limitations displayed in the app and a visible estimate label on pose exports. Manual review is required. The app does not provide medical diagnosis, automated motion scoring, or bat-trajectory tracking.

iPhone and iPad keep separate local libraries. There is no app account, cloud sync or in-app purchase.
```

Review Information 中取消需要登录的选项，填写**你自己的**联系人姓名、电话、邮箱；Feedback Email 也使用你能收信的地址。隐私政策正文已在 `docs/privacy-policy.md` 准备好，先替换联系邮箱，再由你发布到一个无需登录即可访问的 HTTPS 页面；若后台要求 Privacy Policy URL，填写真实可访问链接。该 Markdown 文件的本机路径不能用作 URL。

若填写 App Privacy，根据当前本机处理、不追踪、不上传视频或分析记录的实现核对“Data Not Collected”。用户主动导出到第三方，以及 TestFlight 自身依据 Apple 政策收集的诊断/反馈，需与 App 自有数据服务区分。依赖升级或加入统计服务后需重新核对，不能沿用旧申报。

## 后续构建与常见提示

- 每次上传前在 `Config/Build.xcconfig` 增加 `CURRENT_PROJECT_VERSION`，例如本次 `2` → 下次 `3`；同一测试阶段 Version 可保持 `1.0`。即使 Xcode 分发向导替你调整构建号，也以 App Store Connect 已使用的最大值为准更新配置。
- 只看到 Personal Team：先确认 Apple Developer Program 资格，或切换到有权限的付费团队。
- Bundle ID unavailable / profile mismatch：核对 Bundle ID 注册归属、Team 与后台 App，保持三者一致。
- 旧包的 6 条 MediaPipe dSYM 警告：原始 SDK 是静态库，Xcode 生成了没有必要保留的空动态框架。`1.0 (2)` 的构建阶段会验证并清理它们，应用自己的 dSYM 正常保留。请重新 Archive 并选择新归档上传，旧的 `1.0 (1)` 归档不会自动修正。若 SDK 将来加入代码、资源或动态依赖，保护检查会停止构建，不能关闭检查或创建空 dSYM 绕过。
- 隐私清单或 SDK 签名错误：本地文件存在检查不能代替 Apple 的服务端检查。保留具体 SDK 名称与 ITMS 错误码，不要通过删除声明或关闭安全校验绕过。
- 家长无法接受内部邀请：应使用外部组，完成 TestFlight App Review 后邀请。
- 不需要在这一步提交正式 App Store 版本；本次只启用 TestFlight 测试。

## Apple 官方依据

- [创建 App 记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Xcode 测试与发布分发](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [内部测试者](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [外部测试者与审核](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
- [填写测试信息](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)
- [SDK 最低上传要求](https://developer.apple.com/news/?id=ueeok6yw)
- [非豁免加密声明](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
