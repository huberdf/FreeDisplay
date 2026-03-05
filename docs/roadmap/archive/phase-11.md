# Phase 11: 配置保护与自动亮度 ✅

> 核心价值：防止系统重置显示设置 + 环境光自动亮度

## 任务列表

- [x] 实现配置快照 (`FreeDisplay/Services/ConfigProtectionService.swift`)
  - 实现提示：
    保存当前显示器完整配置的快照：
    ```swift
    struct DisplayConfig: Codable {
        let displayID: UInt32
        let displayName: String
        let resolution: (width: Int, height: Int)
        let refreshRate: Double
        let rotation: Int
        let colorProfile: String
        let brightness: Double
        let contrast: Double
        let hdrEnabled: Bool
        let isMain: Bool
        let isMirrored: Bool
        let mirrorSource: UInt32?
        let origin: CGPoint
    }
    ```
    快照存储到 `~/Library/Application Support/FreeDisplay/configs/`，JSON 格式。
    支持多个命名快照（"日间配置"、"夜间配置"等）。
  - 验证：保存快照后 JSON 文件正确生成

- [x] 实现配置保护监控 (`ConfigProtectionService` 扩展)
  - 实现提示：
    仿照 BetterDisplay 截图的"配置保护"section，可选择保护项：
    - 分辨率、刷新率、色彩模式、HDR 色彩模式、旋转、
      颜色描述文件、HDR 颜色描述文件、HDR 状态、镜像、主显示屏状态
    使用 `CGDisplayRegisterReconfigurationCallback` 监听显示器配置变化。
    当检测到受保护项被改变时，自动恢复到快照值。
    启用/禁用所有保护的快捷按钮。
  - 验证：保护分辨率后，从系统设置改分辨率会被自动恢复

- [x] 实现配置保护 UI (`FreeDisplay/Views/ConfigProtectionView.swift`)
  - 实现提示：
    可展开的"配置保护"section，仿截图：
    保护项列表，每行一个 Toggle：
    分辨率(📺) / 刷新率(📡) / 色彩模式(🎨) / HDR色彩模式 / 旋转(🔄) /
    颜色描述文件(🎯) / HDR颜色描述文件 / HDR状态 / 镜像(📋) / 主显示屏状态(Ⓜ)
    底部：
    - "启用所有保护" / "禁用所有保护" 两个按钮
    - 说明文字："此应用程序所做设置受到保护。"
  - 验证：UI 与 BetterDisplay 截图一致

- [x] 实现自动亮度 (`FreeDisplay/Services/AutoBrightnessService.swift`)
  - 实现提示：
    macOS 内建显示器有环境光传感器。
    读取环境光：`IOServiceGetMatchingService` + `AppleLMUController` 读取 lux 值。
    或使用 `CBTrueToneClient`（私有框架）获取环境光数据。
    简化方案：使用 `IOReport` 框架或读取 IOKit 的 ambient light sensor 值。
    亮度映射曲线：lux → brightness 的对数映射，用户可调节曲线的偏移量。
    外接显示器的自动亮度：按内建传感器的值同步调整（通过 DDC）。
    设置选项："自动亮度"Toggle + 灵敏度滑块。
  - 验证：遮挡环境光传感器时屏幕亮度自动降低

- [x] 实现自动亮度 UI (`FreeDisplay/Views/AutoBrightnessView.swift`)
  - 实现提示：
    在菜单底部或显示器详情中添加"自动亮度"选项（Ⓐ蓝色图标），仿截图。
    Toggle 开关 + 可选的灵敏度滑块。
  - 验证：开关工作，亮度随环境光变化

## Phase 验收

- 配置保护全部保护项工作
- 系统变更受保护配置后自动恢复
- 自动亮度跟随环境光变化
- 所有设置持久化（重启后生效）

**完成后**: 建议运行 project-optimize 反思
