# Coach Insights app icon

定稿方案：v3，洞察之眼 + 棒球瞳孔，用户于 2026-10-20 确认采用。突出 Insights 的观察、分析与发现，同时保留明确的棒球元素；不使用 C 字母或教练形象。

配色：勃艮第红 #722F37、暖象牙白 #FFF8F0。图像不含字样与运动轨迹，外部圆角由 iOS 系统裁切。

生成方式：内置 image_gen 编辑，2026-10-20。当前生成原图为 coach-insights-icon-v3.png；App 使用 ../../CoachInsights/Assets.xcassets/AppIcon.appiconset/AppIcon.png（1024 × 1024、不透明 PNG）。尺寸转换仅用于原生资源打包。

验证：Release 模拟器构建通过，已在 iPhone 与 iPad 模拟器检查桌面图标。预览截图保存在忽略的 artifacts/icon-iphone-v3.png 与 artifacts/icon-ipad-v3.png。

## 完整生成提示词

```text
Use case: logo-brand, precise-object-edit.
Edit the supplied Coach Insights icon. The user likes emphasizing INSIGHTS/observation/diagnostic discovery, but a baseball element MUST also be unmistakable. Combine those two meanings in ONE simple, memorable mark.
Keep the existing deep burgundy full-bleed background, warm-ivory palette, clean offset upper-and-lower eye/aperture arcs, centered placement, and elegant geometric character. Change the central diamond/faceted pupil into a clearly recognizable BASEBALL. Make it a substantial warm-ivory circular ball, about 29–32 percent of the entire canvas width, centered in the eye. Show the iconic two opposing curved burgundy seam cuts with just three or four bold, clean stitches on each side. The seams must look like baseball seams, not a basketball grid or a tennis line. Flat premium logo rendering, no photorealistic texture. Leave ample burgundy negative space separating the ball from the two eye arcs so it reads clearly at small app-icon size. If necessary slightly open the inner eye space, while preserving the overall beautiful eye shape and balanced proportions. The ball is the 'pupil': the complete emblem should immediately say 'insight into baseball' / 'look closely at the baseball action'.
Remove the central diamond and the triangular facet completely. No letter C, no typography or initials, no coach/person, no medical symbols, no extra magnifier or scanner brackets, no bats or trajectory trails, no decorative AI sparkle. Do not add a second unrelated icon or scattered decorations. Keep it to ONE eye-shaped mark with a baseball pupil, highly legible at 48 pixels. Color: burgundy #722F37, warm ivory #FFF8F0, optional extremely restrained muted rose in the seams. Do not introduce green. Output one opaque square production app-icon image, preferably 1024x1024, with the background filling all corners, no pre-rounded outer tile, no surrounding white margin or mockup.
```
