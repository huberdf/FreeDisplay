# Phase 5: 色彩管理 ✅

> 核心价值：ICC 颜色描述文件切换、色彩模式管理

## 任务列表

- [x] 实现 ICC Profile 枚举 (`FreeDisplay/Services/ColorProfileService.swift`)
  - 实现提示：
    使用 ColorSync 框架枚举系统 ICC profiles：
    ```swift
    import ColorSync
    // 获取所有 ICC profile
    let profileIterator = ColorSyncProfileIterateInstalledProfiles()
    ```
    或使用文件系统扫描 ICC profile 目录：
    - `/Library/ColorSync/Profiles/`
    - `/System/Library/ColorSync/Profiles/`
    - `~/Library/ColorSync/Profiles/`
    获取当前显示器的 profile：`CGDisplayCopyColorSpace(displayID)` →
    `CGColorSpace.name` 获取名称。
    Profile 模型：`name: String`、`path: URL`、`colorSpace: String`（RGB/CMYK 等）。
  - 验证：能列出系统所有 ICC profile，包括 Display P3、sRGB、Adobe RGB 等

- [x] 实现 ICC Profile 切换 (`ColorProfileService` 扩展)
  - 实现提示：
    使用 ColorSync API 为指定显示器设置 profile：
    ```swift
    ColorSyncDeviceSetCustomProfiles(
      kColorSyncDisplayDeviceClass,
      deviceID,  // CGDirectDisplayID 转 CFUUIDRef
      profileInfo  // [kColorSyncDeviceDefaultProfileID: profileURL]
    )
    ```
    注意：需要通过 `CGDisplayCreateUUIDFromDisplayID` 获取 display UUID。
  - 验证：切换 profile 后显示器色彩明显变化

- [x] 实现颜色描述文件 UI (`FreeDisplay/Views/ColorProfileView.swift`)
  - 实现提示：
    可展开的"颜色描述文件"section。
    顶部显示当前 profile（如"彩色 LCD"），蓝色图标。
    下方分类列表：
    1. 当前显示器专属 profile
    2. "普通 RGB 描述文件"分组（蓝底白字标签）
    3. 所有系统 profile 列表（AAA、ACES CG Linear、Adobe RGB、Apple RGB...）
    每行：左侧圆形图标（⊙/⊕）+ profile 名称。
    点击即切换。
    仿照 BetterDisplay 截图的颜色描述文件区域布局。
  - 验证：profile 列表完整显示，点击可切换

- [x] 实现色彩模式 UI (`FreeDisplay/Views/ColorModeView.swift`)
  - 实现提示：
    可展开的"色彩模式"section。
    显示当前模式信息（如"内部 (8-bit)"）+ 标签（SDR/RGB/全范围）。
    列出可用选项：
    - 均一性校准（Uniformity Calibration）
    - GPU Dithering
    帧缓存类型选择：
    - 标准帧缓存、反色帧缓存、灰阶帧缓存、反色灰度帧缓存
    使用 `CGDisplayCopyDisplayMode` 获取当前色彩信息。
    帧缓存类型通过 `CGDisplayModeCopyPixelEncoding` 获取。
    仿照 BetterDisplay 截图的色彩模式区域。
  - 验证：色彩模式信息正确显示

## Phase 验收

- ICC profile 列表完整（包含截图中的所有 profile）
- profile 切换功能正常，色彩实际变化
- 色彩模式信息正确展示
- UI 布局与 BetterDisplay 截图一致

**完成后**: 建议运行 project-optimize 反思
