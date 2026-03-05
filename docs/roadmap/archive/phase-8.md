# Phase 8: 屏幕镜像 ✅

> 核心价值：将一个显示器的内容镜像到另一个显示器

## 任务列表

- [x] 实现硬件镜像 (`FreeDisplay/Services/MirrorService.swift`)
  - 实现提示：
    macOS 原生支持硬件级屏幕镜像，通过 CoreGraphics API：
    ```swift
    func enableMirror(source: CGDirectDisplayID, target: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayMirrorOfDisplay(config, target, source)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    func disableMirror(displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
    ```
    检查是否正在镜像：`CGDisplayMirrorsDisplay(displayID)` 返回源显示器 ID，
    如果返回 `kCGNullDirectDisplay` 则未镜像。
    注意：硬件镜像要求两个显示器分辨率兼容。
  - 验证：启用镜像后两个显示器显示相同内容

- [x] 实现屏幕镜像 UI (`FreeDisplay/Views/MirrorView.swift`)
  - 实现提示：
    可展开的"屏幕镜像"section，仿照 BetterDisplay 截图：
    标题下方文字："将此显示器内容镜像到："
    列表显示可用目标显示器（如 "H2435Q"），每行左侧显示器图标。
    底部"停止镜像"按钮（置灰/可用状态切换）。
    选择目标后立即开始镜像。
  - 验证：选择目标显示器后镜像生效，点击停止后恢复

## Phase 验收

- 内建→外接镜像工作
- 外接→内建镜像工作
- 停止镜像恢复正常
- UI 与 BetterDisplay 截图一致

**完成后**: 建议运行 project-optimize 反思
