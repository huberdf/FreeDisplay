# Phase 6: 图像调整 ✅

> 核心价值：软件级色彩调整——对比度、伽马、增益、色温、RGB 独立通道

## 任务列表

- [x] 实现 Gamma Table 调整引擎 (`FreeDisplay/Services/GammaService.swift`)
  - 实现提示：
    macOS 通过 gamma table 实现软件级色彩调整。核心 API：
    ```swift
    // 获取当前 gamma table
    CGGetDisplayTransferByTable(displayID, capacity, &redTable, &greenTable, &blueTable, &sampleCount)
    // 设置自定义 gamma table
    CGSetDisplayTransferByTable(displayID, sampleCount, redTable, greenTable, blueTable)
    // 或使用公式模式（更常用）
    CGSetDisplayTransferByFormula(displayID,
      redMin, redMax, redGamma,
      greenMin, greenMax, greenGamma,
      blueMin, blueMax, blueGamma)
    ```
    封装成高层接口：
    - `setGamma(displayID, value: Double)` — 整体伽马（0.1~3.0，默认 1.0）
    - `setGain(displayID, value: Double)` — 整体增益（映射到 max 参数）
    - `setColorTemperature(displayID, kelvin: Int)` — 色温（转换为 RGB 比例）
    - `setRGBGamma(displayID, r/g/b: Double)` — 独立 RGB 伽马
    - `setRGBGain(displayID, r/g/b: Double)` — 独立 RGB 增益
    - `resetGamma(displayID)` — 重置 `CGDisplayRestoreColorSyncSettings()`
    色温到 RGB 转换：使用 Planckian locus 近似公式（Tanner Helland 算法），
    输入色温 K 值，输出 RGB 比例系数。
  - 验证：`setGamma(displayID, 0.5)` 后屏幕明显变亮/变暗

- [x] 实现对比度软件调整 (`GammaService` 扩展)
  - 实现提示：
    对比度通过调整 gamma table 的 min/max 范围实现：
    - 提高对比度：增大 max - min 差距
    - 降低对比度：缩小 max - min 差距
    公式：`min = 0.5 - contrast/2`，`max = 0.5 + contrast/2`，contrast 范围 0~1。
    注意：外接显示器还可以通过 DDC VCP 0x12 设置硬件对比度（Phase 2 已有 DDC 基础）。
  - 验证：调节对比度后画面对比度明显变化

- [x] 实现反转色彩 (`GammaService` 扩展)
  - 实现提示：
    反转色彩 = gamma table 中 min 和 max 互换：
    `CGSetDisplayTransferByFormula(displayID, 1,0,1, 1,0,1, 1,0,1)` 实现全反转。
    或使用辅助功能 API `CGDisplaySetInvertedPolarity(true)` 如果可用。
  - 验证：开启反转后屏幕颜色全部反转

- [x] 实现图像调整 UI (`FreeDisplay/Views/ImageAdjustmentView.swift`)
  - 实现提示：
    可展开的"图像调整"section，仿照 BetterDisplay 截图：
    垂直排列多个滑块组：
    1. 对比度 — Slider（⊙图标）0%
    2. 伽马值 — Slider（✦图标）0%
    3. 增益 — Slider（⚡图标）0%
    4. 色温 — Slider（🔥图标）0%
    5. 量化 — Slider（📊图标）无限
    ---分隔线---
    6. 伽马值(红色) R — Slider 0%
    7. 伽马值(绿色) G — Slider 0%
    8. 伽马值(蓝色) B — Slider 0%
    ---分隔线---
    9. 增益(红色) R — Slider 0%
    10. 增益(绿色) G — Slider 0%
    11. 增益(蓝色) B — Slider 0%
    ---
    ⚠️ "调整可能影响 HDR 内容！" 警告文本
    底部按钮：反转色彩 / 暂停颜色调整 / 重置图像调整
    每个 Slider 左侧有图标、标签，右侧显示百分比值。
  - 验证：UI 与 BetterDisplay 截图完全一致

- [x] 实现量化（Quantization）功能 (`GammaService` 扩展)
  - 实现提示：
    量化 = 减少色彩位深的视觉模拟。通过修改 gamma table 实现阶梯化：
    将 256 级灰度映射到 N 级（N = 量化等级），形成色阶效果。
    "无限"= 不量化（原始 256 级）。
  - 验证：量化设为低值时画面出现明显色阶

## Phase 验收

- 所有 11 个滑块功能正常
- 伽马/增益/色温调节屏幕色彩实际变化
- RGB 独立通道调节工作
- 反转色彩/暂停/重置按钮工作
- UI 与 BetterDisplay 图像调整截图一致

**完成后**: 建议运行 project-optimize 反思
