# Phase 10: 虚拟显示器 ✅

> 核心价值：创建 dummy display / 虚拟屏幕，扩展 HiDPI 支持

## 任务列表

- [x] 实现虚拟显示器创建 (`FreeDisplay/Services/VirtualDisplayService.swift`)
  - 实现提示：
    使用 macOS 14+ 的 `CGVirtualDisplay` API：
    ```swift
    import CoreGraphics

    let descriptor = CGVirtualDisplayDescriptor()
    descriptor.queue = DispatchQueue.global()
    descriptor.name = "FreeDisplay Virtual"
    descriptor.maxPixelsWide = 3840
    descriptor.maxPixelsHigh = 2160
    descriptor.sizeInMillimeters = CGSize(width: 600, height: 340) // 27 inch
    descriptor.productID = 0x1234
    descriptor.vendorID = 0x5678
    descriptor.serialNum = 0

    let display = CGVirtualDisplay(descriptor: descriptor)

    // 添加显示模式
    let settings = CGVirtualDisplaySettings()
    settings.hiDPI = 1  // 启用 HiDPI
    let mode = CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60)
    settings.modes = [mode, ...]
    display?.applySettings(settings)
    ```
    功能：
    - 创建虚拟显示器（指定名称、分辨率、DPI）
    - 销毁虚拟显示器
    - 列出当前活跃的虚拟显示器
    - 持久化配置（UserDefaults/JSON），启动时自动创建
    注意：虚拟显示器创建后系统会将其视为真实显示器，可用于 HiDPI 和 Sidecar 场景。
  - 验证：创建虚拟显示器后系统设置中出现新的显示器

- [x] 实现 HiDPI 增强（基于虚拟显示器）(`HiDPIService` 扩展)
  - 实现提示：
    Phase 3 中通过 plist override 实现 HiDPI，此处用虚拟显示器方案增强：
    1. 创建与外接显示器分辨率匹配的虚拟显示器（启用 HiDPI）
    2. 将外接显示器镜像到虚拟显示器
    3. 外接显示器继承虚拟显示器的 HiDPI 模式
    这是 BetterDisplay 实现 HiDPI 的核心方式——不需要修改系统文件，不需要 SIP。
    在 ResolutionService 中增加"高分辨率 (HiDPI)"开关，开启时自动创建配对虚拟显示器。
  - 验证：外接显示器开启 HiDPI 后分辨率列表出现缩放模式

- [x] 实现虚拟显示器管理 UI (`FreeDisplay/Views/VirtualDisplayView.swift`)
  - 实现提示：
    在"工具"区域添加"显示器和虚拟屏幕"入口（仿截图）。
    点击打开管理面板/窗口：
    - 当前虚拟显示器列表（名称、分辨率、状态）
    - "+"按钮添加新虚拟显示器（弹出配置表单：名称、分辨率、DPI）
    - 每行有删除按钮
    - 配置持久化选项（下次启动自动创建）
  - 验证：创建/删除虚拟显示器的全流程正常

- [x] 实现"高分辨率 (HiDPI)"一键开关 UI
  - 实现提示：
    在每个显示器的菜单区域添加"高分辨率 (HiDPI)"行（蓝色⊕图标），仿截图。
    开关 Toggle 控制：开启时自动创建配对虚拟显示器并镜像，
    关闭时销毁虚拟显示器并取消镜像。
    状态持久化到 UserDefaults。
  - 验证：开启 HiDPI 后外接显示器分辨率列表变化

## Phase 验收

- 虚拟显示器创建/销毁正常
- HiDPI 通过虚拟显示器方案生效
- 虚拟显示器管理 UI 完整
- 配置持久化工作（重启后恢复）

**完成后**: 建议运行 project-optimize 反思
