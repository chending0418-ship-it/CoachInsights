"""Static local report; no external resources or analytics."""
import html
import json
from pathlib import Path
import statistics

B=Path(__file__).parent/'results'
s=json.loads((B/'summary.json').read_text())
frames=json.loads((B/'frames.json').read_text())
names={'vision':'Apple Vision 框追踪','vision_flow':'Apple Vision 稠密光流','opencv_lk':'OpenCV LK 光流',
 'opencv_csrt':'OpenCV CSRT','bootstapir_256':'BootsTAPIR · 首帧初始化',
 'bootstapir_corrected_256':'BootsTAPIR · 加两次人工校正'}
common=[12,21,60,77]
track_rows=''
for key,row in s['tracking'].items():
 checks={c['index']:c for c in row['checks']}
 values=[checks[i]['errorPx'] for i in common]
 track_rows+=f'<tr><td>{names[key]}</td>'+''.join(f'<td>{v:.0f}</td>' for v in values)+f'<td><strong>{statistics.mean(values):.0f}</strong></td></tr>'
pose_rows=''
for key,row in s['pose'].items():
 pose_rows+=f'<tr><td>{key}</td><td>{row["detectedFrames"]} / {row["frames"]}</td><td>{row["medianMSExcludingFirst"]:.1f} ms</td></tr>'
doc=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Coach Inside · 识别引擎第一轮实测</title>
<style>
:root{{color-scheme:light;--ink:#152532;--muted:#536473;--line:#dce5e8;--green:#136d54}}*{{box-sizing:border-box}}body{{margin:0;background:#eef3f4;color:var(--ink);font:16px/1.75 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}}main{{max-width:1120px;margin:32px auto;padding:36px 42px;background:white;border-radius:22px}}h1{{font-size:34px;line-height:1.25;margin:12px 0 16px}}h2{{font-size:23px;margin:36px 0 12px}}p{{margin:12px 0}}.eyebrow{{color:var(--green);font-weight:700;letter-spacing:.08em}}.muted{{color:var(--muted)}}.chips{{display:flex;gap:8px;flex-wrap:wrap}}.chips span{{background:#e8f3ed;color:#15533e;padding:5px 12px;border-radius:100px;font-size:14px}}.callout{{background:#eff7f3;border-left:4px solid #2c8966;padding:14px 18px;border-radius:0 12px 12px 0;margin:22px 0}}.note{{background:#fff5e8;padding:14px 18px;border-radius:12px}}table{{border-collapse:collapse;width:100%;margin:16px 0;font-size:14px}}th,td{{padding:12px 10px;text-align:left;border-bottom:1px solid var(--line)}}th{{background:#f1f5f6;font-weight:650}}.scroll{{overflow-x:auto}}video,img{{display:block;width:100%;height:auto;border-radius:12px;background:#101620;margin:16px 0}}a{{color:var(--green)}}code{{font:13px ui-monospace,monospace;background:#edf2f4;padding:2px 4px;border-radius:4px}}ul{{padding-left:24px}}footer{{border-top:1px solid var(--line);margin-top:36px;padding-top:18px;font-size:13px;color:var(--muted)}}@media(max-width:700px){{main{{margin:0;border-radius:0;padding:24px 18px}}h1{{font-size:27px}}th,td{{padding:9px 6px}}}}
</style><main>
<div class="eyebrow">COACH INSIDE / ENGINE STUDY 01 / 2026.10.20</div>
<h1>人体姿态与球棒半自动追踪<br>第一轮本机实测</h1>
<div class="chips"><span>1.0 支持 iPhone + iPad</span><span>各设备本地保存</span><span>无 iCloud 同步</span><span>球棒轨迹研究已归档</span></div>
<p class="muted">素材 IMG_9673.mov · 3840 × 2160 · {s['sample']['duration']:.3f} 秒 · 约 29.98 fps · 解码 78 帧。两组测试共用 1280 × 720 图像与原始帧时间戳。视频没有上传到云端推理服务。</p>
<div class="callout"><strong>范围更新 · 2026-10-20：</strong>1.0 已移除球棒轨迹、半自动棒头/握柄追踪及专用轨迹校正工具。保留拍摄、慢放、逐帧、通用标注、双视频对比与人体姿态分析。人体姿态暂选 Apple Vision，保留 MediaPipe Full 的替换接口；下文球棒追踪实验仅作为历史研究资料。</div>
<p>人体方案的选择依据是当前能力与集成成本。一个视频不足以证明人体模型的精度胜负，仍需在 iPhone / iPad 真机上验证。BootsTAPIR 不作为当前 1.0 的开发或部署依赖。</p>
<h2>人体姿态：三种方案均能持续检出人体</h2>
<table><thead><tr><th>方案</th><th>有人体输出的帧数</th><th>稳态接口耗时中位数</th></tr></thead><tbody>{pose_rows}</tbody></table>
<p class="muted">耗时来自 Mac Apple Silicon。Vision 使用系统默认计算路径，MediaPipe 使用 Python CPU / XNNPACK 路径；硬件后端未统一，且模型初始化与首帧不计入中位数。不能换算为 iPhone / iPad 速度，也不能用检出帧数代表准确率。</p>
<p>叠加中使用双方共有的 12 个肩、肘、腕、髋、膝、踝关键点。仅绘制各自质量分数达到 0.5 的点及连线，双方分数不可直接校准比较。本轮未验证 3D 骨架或三维关节角度。</p>
<video controls playsinline preload="metadata" poster="pose_contact_sheet.jpg" src="pose_comparison.mp4"></video>
<p>三者都能提供身体和下肢参考；遮挡、交叉持棒与快速挥臂阶段仍可能发生腕部定位误差。Vision 原生集成较轻；MediaPipe 的 33 个关键点在需要脚跟、脚尖等细节时值得继续验证。</p>
<h2>球棒追踪：点追踪优于通用框追踪，但模糊段仍不可靠</h2>
<p>所有无校正基线使用同一首帧，由人工目视点选棒头和握柄。框追踪以端点附近的小图块初始化，取框中心作为端点位置。BootsTAPIR 输入按官方示例缩放为 256 × 256，输出映射回 1280 × 720；显示画面保持原比例。</p>
<video controls playsinline preload="metadata" poster="semi_auto_demo.jpg" src="semi_auto_demo.mp4"></video>
<p class="muted">半自动工作流的离线模拟：左侧仅首帧初始化，右侧加入两次人工校正。画面裁切放大；红叉是待确认的原始预测，绿色轨迹只连接连续通过门限的点，遇到不可靠段会断开。尚未实现原生 iOS 修正界面。</p>
<p>下面保留六组方法的完整画面对比，供检查漂移和恢复情况。</p>
<video controls playsinline preload="metadata" poster="tracking_comparison.jpg" src="tracking_comparison.mp4"></video>
<p class="muted">彩色圆圈：原始预测通过该方法当前的质量门限；红叉：未通过；白圈：人工目视参考点。稠密光流本身没有提供端点质量门限。即使门限通过，也可能跟错物体。视频是调试视图，不是确认过的分析结论，按 8fps 放慢展示。</p>
<div class="scroll"><table><thead><tr><th>方法</th><th>第 12 帧</th><th>第 21 帧</th><th>第 60 帧</th><th>第 77 帧</th><th>平均偏差</th></tr></thead><tbody>{track_rows}</tbody></table></div>
<p class="muted">单位：1280 × 720 分析图像中的像素。四个方法间共用的非初始化、非校正检查点，数值越小越接近目视参考。人工目视参考的不确定度约 10–25 像素，不是专家精确标注。最模糊的快速挥棒帧没有纳入这些数字；不能据此声称整体准确率或高速击球段已经通过。</p>
<p>两次人工校正在第 18 帧（{frames[18]['seconds']:.3f}s）和第 42 帧（{frames[42]['seconds']:.3f}s）加入，校正帧从上表评价中排除。它们通过额外查询点并选择相应轨迹段模拟，尚不是已完成的 iOS 交互界面。校正后的后半段仍有低置信输出，需要用户确认，不能直接作为可靠路径。</p>
<p>同一检查点下，BootsTAPIR 的原始预测比四个传统基线更接近参考位置；两次修正后进一步改善。但它在拖影最重的挥棒过程中仍会失跟。握柄也会受双手遮挡影响，应单独验收，不能把棒头测试结果扩展为球棒方向已经可靠。</p>
<div class="note"><strong>关键限制：</strong>此素材约 30fps，快速挥棒出现扇形拖影。模糊帧中无法可靠确定唯一瞬时棒头位置。产品应保留未确认段，不能把模型猜测或插值包装为测量结果。</div>
<h2>历史交互设想（已移出 1.0）</h2>
<p>点选棒头 / 握柄 → 本机追踪 → 在时间轴标出待确认段 → 放大查看并拖动修正 → 更新轨迹 → 由用户确认后导出。iPhone 使用放大镜辅助点选；iPad 同时支持手指与 Apple Pencil，放大修正区域。两端功能保持一致，视频与分析数据分别存于各自设备。</p>
<h2>当前人体姿态验证与归档说明</h2>
<ul><li>后续引擎验证聚焦人体姿态与视频工具，不继续推进球棒追踪的 iOS 模型转换或专用修正界面。</li>
<li>在实际 iPhone 和 iPad 上检查人体姿态质量、处理耗时、内存和发热；模拟器不能替代真机验收。</li>
<li>人体测试素材需要覆盖左右手、不同机位、场地及投球动作，并加入高帧率视频。当前一个打击片段不足以证明普遍适用性。</li>
<li>保留本次球棒实验与两种输入尺寸的原始结果，供历史查阅；它们不构成当前 1.0 的交付范围。</li></ul>
<h2>依据与可复现材料</h2>
<p><a href="https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest">Apple Vision 人体姿态</a> · <a href="https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios">MediaPipe 官方 iOS 接入</a> · <a href="https://github.com/google-deepmind/tapnet">BootsTAPIR 官方实现与模型许可</a>。TAPIR 仓库说明本次使用的预训练模型与代码采用 Apache 2.0；仍需随最终版本保留对应许可文件。</p>
<p><a href="summary.json">汇总数据</a> · <a href="reference_points.json">目视参考与不确定度</a> · <a href="frames.json">原始帧时间戳</a> · <a href="tapir_coordinate_sanity.json">点坐标平移校验</a> · <a href="../README.txt">复现步骤</a></p>
<footer>本地可行性测试 · 仅一个输入视频 · 2D 姿态与二维轨迹 · 未建立精度基准集 · 尚未进行 iOS 真机性能验收</footer></main></html>'''
(B/'report.html').write_text(doc)
print(B/'report.html')
