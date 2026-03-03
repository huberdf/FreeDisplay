# Phase 7: 显示器高级管理 ✅

> 核心价值：主显示屏切换、刘海管理、集成控制、管理显示器设置

## 任务列表

- [x] 实现"设为主显示屏"UI 和逻辑 (`FreeDisplay/Views/MainDisplayView.swift`)
  - 实现提示：
    在菜单中添加"设为主显示屏"选项（Ⓜ 图标），仿截图的蓝色 M 圆形图标。
    逻辑已在 Phase 4 的 ArrangementService 中实现（移到坐标原点）。
    此处做 UI 层：显示器列表中当前主显示屏旁显示 Ⓜ 标记。
    点击其他显示器的"设为主显示屏"按钮切换。
  - 验证：点击后 Dock 和菜单栏移到目标显示器

- [x] 实现"显示刘海"管理 (`FreeDisplay/Views/NotchView.swift`)
  - 实现提示：
    MacBook 有刘海（notch），影响分辨率和布局。
    功能：在分辨率列表中标注"刘海"标签（仿截图中的"刘海 60Hz 10bit"）。
    检测刘海：`NSScreen.safeAreaInsets.top > 0` 或检查设备型号。
    提供"隐藏刘海"选项：通过在刘海区域覆盖黑色条实现
    （创建一个 borderless、always-on-top 的黑色 NSWindow，覆盖刘海区域）。
  - 验证：内建屏分辨率旁正确显示"刘海"标签

- [x] 实现"集成控制"(DDC 扩展) (`FreeDisplay/Views/IntegratedControlView.swift`)
  - 实现提示：
    可展开的"集成控制"section，仿截图布局：
    - "从设备读取并更新"按钮：读取所有 DDC VCP code 并刷新 UI
    - "配置集成控制项..."按钮：弹出配置窗口
    DDCService 扩展：批量读取常用 VCP codes：
    0x10(亮度), 0x12(对比度), 0x14(色温选择), 0x16(视频增益R),
    0x18(视频增益G), 0x1A(视频增益B), 0x60(输入源), 0x62(音量),
    0x87(色彩饱和度), 0xD6(电源模式), 0xDC(显示模式)
    结果存储到 DisplayInfo 的 `ddcValues: [UInt8: UInt16]` 字典中。
  - 验证：点击"从设备读取"后外接显示器的 DDC 参数正确显示

- [x] 实现"管理显示器"设置 (`FreeDisplay/Views/ManageDisplayView.swift`)
  - 实现提示：
    可展开的"管理显示器"section，仿截图：
    - "配置显示..."：打开系统偏好设置的显示器面板
      `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings")!)`
    - "视觉识别"：在目标显示器上弹出全屏标识窗口（显示显示器名称 + ID），
      3 秒后自动关闭。用 NSWindow + NSScreen 定位到目标显示器。
    - 提示文本："使用 ⌥ Option + 点击显示菜单标题以快速识别。"
    - "连接时防止进入睡眠"：使用 `IOPMAssertionCreateWithName` 创建电源断言
      阻止系统睡眠（`kIOPMAssertionTypePreventSystemSleep`）。
  - 验证：点击"视觉识别"后目标显示器弹出识别窗口

## Phase 验收

- 主显示屏切换正常
- 刘海标签正确显示
- 集成控制可读取 DDC 参数
- 管理显示器的所有子功能工作

**完成后**: 建议运行 project-optimize 反思
