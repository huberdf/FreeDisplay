# Phase 4: 屏幕旋转与显示器排列 ✅

> 核心价值：屏幕旋转和多显示器空间排列

## 任务列表

- [x] 实现屏幕旋转 (`FreeDisplay/Services/RotationService.swift`)
  - 实现提示：
    使用 `CGBeginDisplayConfiguration` → `CGConfigureDisplayOrigin` 配合旋转。
    macOS 的旋转通过 IOKit 设置：
    ```swift
    IOServiceRequestProbe(service, kIOFBSetTransform)  // 触发旋转
    ```
    或使用 `CGDisplayRotation()` 获取当前旋转角度，
    通过私有 API `CGSConfigureDisplayMode` 设置旋转。
    备选方案：使用 `displayplacer` CLI 工具的思路，通过 IOKit 直接操作。
    支持的角度：0°、90°、180°、270°。
  - 验证：选择 90° 旋转后显示器画面实际旋转

- [x] 实现屏幕旋转 UI (`FreeDisplay/Views/RotationView.swift`)
  - 实现提示：
    可展开的"屏幕旋转"section。
    四个选项：90°/180°/270° 旋转屏幕 + 关闭旋转。
    每个选项一行，左侧旋转方向箭头图标（↻/↓/←），右侧文字。
    当前旋转状态高亮。
    仿照 BetterDisplay 截图的屏幕旋转区域布局。
  - 验证：UI 显示四个旋转选项，点击后实际旋转

- [x] 实现显示器排列 (`FreeDisplay/Services/ArrangementService.swift`)
  - 实现提示：
    使用 `CGBeginDisplayConfiguration` → `CGConfigureDisplayOrigin(config, displayID, x, y)`
    → `CGCompleteDisplayConfiguration` 设置显示器在虚拟桌面中的位置。
    获取当前位置：`CGDisplayBounds(displayID)` 返回的 origin。
    多个显示器的坐标系：主显示器左上角为 (0,0)，其他显示器相对偏移。
  - 验证：代码调整显示器位置后，系统偏好设置中排列确实变化

- [x] 实现排列显示器 UI (`FreeDisplay/Views/ArrangementView.swift`)
  - 实现提示：
    可展开的"排列显示器"section。
    内容是一个网格视图，仿照 BetterDisplay 截图：
    灰色背景上显示显示器缩略图（蓝色矩形 + 名称），可拖拽。
    使用 SwiftUI 的 `.gesture(DragGesture())` 实现拖拽。
    显示器矩形的大小按实际分辨率等比缩放。
    拖拽结束后调用 ArrangementService 更新位置。
    网格背景用浅灰色方格表示虚拟桌面范围。
  - 验证：显示器排列视图与 BetterDisplay 截图布局一致，拖拽后位置更新

- [x] 设为主显示屏功能 (`FreeDisplay/Services/DisplayManager.swift` 扩展)
  - 实现提示：
    在 DisplayManager 中添加 `func setAsMainDisplay(_ displayID: CGDirectDisplayID)`。
    使用 `CGBeginDisplayConfiguration` → `CGConfigureDisplayOrigin(config, displayID, 0, 0)`
    将目标显示器移到原点位置（macOS 中主显示器 = 坐标原点的显示器）。
    其他显示器的坐标相应调整。
  - 验证：设为主显示器后，Dock 和菜单栏移到目标显示器

## Phase 验收

- 屏幕旋转四个方向都工作正常
- 显示器排列可视化拖拽正常
- 设为主显示屏功能正常
- UI 布局与 BetterDisplay 截图一致

**完成后**: 建议运行 project-optimize 反思
