# Phase 1: 显示器检测与菜单 UI ✅

> 核心价值：列出所有连接的显示器，展示基本信息，建立 UI 框架

## 任务列表

- [x] 实现 `DisplayInfo` 模型 (`FreeDisplay/Models/DisplayInfo.swift`)
  - 实现提示：属性包括 `displayID: CGDirectDisplayID`、`name: String`、
    `isBuiltin: Bool`、`isMain: Bool`、`isOnline: Bool`、`vendorNumber: UInt32`、
    `modelNumber: UInt32`、`serialNumber: UInt32`、`bounds: CGRect`、
    `pixelWidth: Int`、`pixelHeight: Int`、`rotation: Double`。
    用 `CGDisplayIsBuiltin()` / `CGDisplayIsMain()` 等 CG 函数获取。
    显示器名称通过 `IODisplayCreateInfoDictionary` 的 `kDisplayProductName` 获取。
  - 验证：能正确识别内建显示屏和 H2435Q 外接显示器名称

- [x] 实现 `DisplayManager` 检测逻辑 (`FreeDisplay/Services/DisplayManager.swift`)
  - 实现提示：`@Published var displays: [DisplayInfo]`。
    用 `CGGetOnlineDisplayList(16, &displayIDs, &count)` 获取所有在线显示器。
    监听 `CGDisplayRegisterReconfigurationCallback` 在显示器热插拔时自动刷新。
    启动时调用一次扫描。
  - 验证：插拔显示器时列表自动更新

- [x] 实现菜单栏主视图 (`FreeDisplay/Views/MenuBarView.swift`)
  - 实现提示：垂直 ScrollView，顶部是显示器列表（每个显示器一行，含名称 + 开关 Toggle），
    仿照 BetterDisplay 截图的布局：显示器名称在左，Toggle 开关在右。
    内建显示屏名称后加 Ⓜ 标记表示主显示器。
    使用 `@EnvironmentObject var displayManager: DisplayManager`。
    底部放"工具"分区和"退出 FreeDisplay"按钮。
  - 验证：菜单显示 H2435Q 和内建显示屏两行

- [x] 实现显示器详情展开区 (`FreeDisplay/Views/DisplayDetailView.swift`)
  - 实现提示：点击显示器行展开详情，使用 `DisclosureGroup` 或自定义展开动画。
    展开后显示功能列表（亮度、分辨率等），每个功能一个 section header。
    Phase 1 先放占位文本，后续 Phase 逐步实现。
    参照 BetterDisplay 截图的 section 列表样式（蓝色图标 + 文字 + 右箭头）。
  - 验证：点击显示器行展开，显示功能 section 列表

- [x] 显示器开关功能 (`FreeDisplay/Services/DisplayManager.swift`)
  - 实现提示：Toggle 控制显示器开关。外接显示器使用 DDC VCP code 0xD6 (Power Mode)
    发送 standby 命令。内建显示器使用 `IORegistryEntrySetCFProperty` 设置亮度为 0。
    注意：完整的 DDC 通信在 Phase 2 实现，此处可先用 `CGDisplayCapture` / `CGDisplayRelease` 模拟。
  - 验证：Toggle 关闭外接显示器时屏幕变黑

## Phase 验收

- 编译运行后菜单栏图标点击弹出面板
- 面板显示所有连接的显示器（名称正确）
- 显示器行可展开，展示功能 section 占位列表
- 底部有"退出 FreeDisplay"按钮且可用

**完成后**: 建议运行 project-optimize 反思
