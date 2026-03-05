# Phase 3: 分辨率管理与 HiDPI ✅

> 核心价值：分辨率切换和 HiDPI 支持，BetterDisplay 的核心卖点

## 任务列表

- [x] 实现分辨率模式枚举 (`FreeDisplay/Models/DisplayMode.swift`)
  - 实现提示：
    模型属性：`width: Int`、`height: Int`、`refreshRate: Double`、`bitDepth: Int`、
    `isHiDPI: Bool`、`isNative: Bool`、`ioDisplayModeID: Int32`。
    使用 `CGDisplayCopyAllDisplayModes(displayID, options)` 获取所有模式。
    options 字典加入 `kCGDisplayShowDuplicateLowResolutionModes: true` 以显示 HiDPI 模式。
    当前模式用 `CGDisplayCopyDisplayMode(displayID)` 获取。
    判断 HiDPI：`CGDisplayModeGetPixelWidth > CGDisplayModeGetWidth` 时为 HiDPI。
    显示格式仿照 BetterDisplay：`1470x956` + 标签（刘海/60Hz/10bit）。
  - 验证：能列出内建屏的所有模式，包括 1470x956(HiDPI)、2560x1664(原生) 等

- [x] 实现分辨率切换 (`FreeDisplay/Services/ResolutionService.swift`)
  - 实现提示：
    ```swift
    func setDisplayMode(_ mode: CGDisplayMode, for displayID: CGDirectDisplayID) -> Bool
    ```
    使用 `CGBeginDisplayConfiguration` → `CGConfigureDisplayWithDisplayMode` →
    `CGCompleteDisplayConfiguration(.permanently)` 三步切换。
    切换前保存当前模式，失败时回滚。
    注意：HiDPI 模式切换可能需要使用私有 API `CGSConfigureDisplayMode`
    或者通过创建自定义 timing 来注入 HiDPI 模式（Phase 10 虚拟显示器部分深入）。
  - 验证：切换分辨率后显示器实际分辨率变化

- [x] 实现分辨率滑块 UI (`FreeDisplay/Views/ResolutionSliderView.swift`)
  - 实现提示：
    仿照 BetterDisplay 截图的分辨率区域：水平 Slider + 右侧显示当前分辨率文本。
    Slider 的 step 对应可用模式列表的索引。
    左侧小显示器图标，右侧 `1470x956` 文本。
    拖动时实时预览分辨率文本变化，松手后切换。
  - 验证：拖动滑块显示分辨率文本变化

- [x] 实现显示模式列表 UI (`FreeDisplay/Views/DisplayModeListView.swift`)
  - 实现提示：
    可展开的"显示模式"section（仿照 BetterDisplay 截图布局）。
    分两组：
    1. "默认及原生模式"：原生分辨率 + 系统默认 HiDPI 模式
    2. "匹配默认过滤模式"：其他可用模式
    每个模式一行：图标(●/◉/⊙) + 分辨率文本 + 右侧标签（刘海/60Hz/10bit）。
    当前选中模式高亮（蓝色圆形图标）。
    点击即切换。
    添加"收藏"功能和"过滤..."按钮（仿截图的☆管理和⊙过滤）。
  - 验证：显示模式列表与 BetterDisplay 截图布局一致

- [x] HiDPI 模式注入 (`FreeDisplay/Services/HiDPIService.swift`)
  - 实现提示：
    外接显示器默认不提供 HiDPI 模式。需要通过以下方式启用：
    1. 使用 `CGVirtualDisplay` 创建匹配外接分辨率的虚拟显示器（推荐，Phase 10 完善）
    2. 或修改 IOKit display override plist 注入自定义分辨率
       路径：`/System/Library/Displays/Contents/Resources/Overrides/`
       格式：`DisplayVendorID-XXXX/DisplayProductID-XXXX`
    Phase 3 先实现方案 2（plist override），Phase 10 再用虚拟显示器方案增强。
    注意：macOS SIP 保护系统目录，需要引导用户关闭 SIP 或使用用户级 override。
  - 验证：外接显示器出现原本没有的 HiDPI 缩放模式

## Phase 验收

- 内建和外接显示器的分辨率模式列表完整显示
- 点击模式列表项可成功切换分辨率
- 分辨率滑块工作正常
- 显示模式列表 UI 与 BetterDisplay 风格一致

**完成后**: 建议运行 project-optimize 反思
