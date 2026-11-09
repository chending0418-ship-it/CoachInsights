# 棒球训练助手 iPad 首发设计提案

**2026-11-06 评审修正：** 用户认可专业工作室布局方向，但功能主结构应为私教／团训／随手工具，iPhone 继续保留。旧提案中的项目优先架构不作为现行功能依据。当前先完成 [功能核对和用户优先级](../../plans/v1.1-todo.md)，再继续设计开发。

2026-11-05。用户要求三套从视觉到操作逻辑均独立的方案，并结合宣传方向、产品调性和实际可实现性进行评审。当前为设计提案，未选择方向，未替换原生 App 界面。

## 三套方向

| 方案 | 核心组织方式 | 宣传重心 |
| --- | --- | --- |
| 原生资料库 | 本机资料 → 选择内容 → 直接编辑 | 可信赖、容易接近的训练资料与分析工具 |
| 专业工作室 | 项目 → 大画布工作区 → 连续操作 | 教练的场边观察、讲解与视频分析 |
| 轻松陪练 | 选择任务 → 可选引导 → 保存与继续练习 | 家长和球员一起看懂练习 |

每套包含首页、战术白板和视频分析，共九张效果图。三套分别保留自己的导航、视觉与交互方式，本轮没有混为一套。

## 阅读与交付

- [完整 PDF 说明](../../../artifacts/design/ipad-first/review/Drill-Buddy-iPad-design-review.pdf)：20 页，包含定位、九张效果图、实现范围、宣传方向、取舍与评审建议。
- [原生资料库总览](../../../artifacts/design/ipad-first/review/native-overview.png)、[专业工作室总览](../../../artifacts/design/ipad-first/review/studio-overview.png)、[轻松陪练总览](../../../artifacts/design/ipad-first/review/buddy-overview.png)。
- [独立打开的交互预览](../../../artifacts/design/ipad-first/review/preview.html)。三套同时展开，按各自入口打开白板与视频页。
- [完整评审包](../../../artifacts/design/ipad-first/review/Drill-Buddy-iPad-design-review.zip)：PDF、九张 2× PNG、三张总览、三张宣传方向应用、独立预览及源稿。

生成结果位于被忽略的 `artifacts/design/ipad-first/review/`。唯一编辑源稿在本目录；聊天中的交互预览是此源稿的输出副本。

## 可编辑源稿

- `proposal.json`：方案、文案、实现判断和验证边界。
- `prototype.html`：三套可操作的概念界面，内嵌示例图像，没有业务网络请求。
- `render.cjs`：输出九张 2× 截图、三张独立总览，并检查页面切换、拖动、试画、撤销、逐帧和引导完成。
- `render_marketing.cjs`：使用对应 UI 生成三张 3:4 宣传方向示意，不代替正式宣传图。
- `build_pdf.py`：读取方案和截图，生成说明 PDF，检查文本、页数与版面边界。
- `assets/`：内置 ImageGen 生成的虚构成人练习静帧、既有产品图标的尺寸适配副本及来源和完整提示词。未使用私有用户视频或真实未成年人素材。

## 复现

使用 Codex 工作区依赖提供的 Node、Python、Playwright、ReportLab 和 Poppler。浏览器默认使用本机 Chrome，可通过 `CHROME_EXECUTABLE` 指定路径。先用 visualize 技能的 `render.py` 将 `prototype.html` 包装为输出目录的 `preview.html`，再运行本目录的 `render.cjs` 和 `build_pdf.py`。交互预览重新生成时应将最新片段同步至聊天的可视化路径。

PDF 每次修改后都要渲染逐页检查。最终检查和文件哈希位于输出目录的 `qa/`、`prototype-checks.json` 和 `manifest.json`；浏览器原型验证不代表原生功能、Apple Pencil、真机性能或 AR 精度通过。

## 本轮实现判断

现有 `AnalysisWorkspace`、`AnalysisCanvas`、`TacticsDocument`、本机记录与导出能力可以复用；导航、面板、引导层和窗口适配属于主要新增工作。白板酒红画笔、线宽字段以及 PencilKit 特性尚未实现，需要兼容设计与专项验证。

完整来源在 PDF 末页与 `proposal.json`。本轮不修改工程、版本、设备支持范围、商店字段或线上官网；官网名称更新另见既有发布记录。
