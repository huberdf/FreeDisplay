# Phase 13: 关键 Bug 修复

> 目标：修复用户反馈的三个功能性 Bug

## 任务列表

- [ ] 修复图像调整关闭后的残影问题
  - 实现提示：
    1. `ImageAdjustmentView.swift` 添加 `.onDisappear`：检查所有滑块是否在零位，如果不是则调用 `GammaService.shared.restoreColorSync()`
    2. `GammaService.swift` 的 `init()` 中注册 `NSApplication.willTerminateNotification` 观察者，回调里调用 `CGDisplayRestoreColorSyncSettings()`
    3. `AppDelegate.swift` 的 `applicationWillTerminate` 里也加一道保险：`CGDisplayRestoreColorSyncSettings()`
    4. 考虑添加 `saveState()` / `restoreState()` 方法到 GammaService，在 onDisappear 时保存当前调整值到 UserDefaults，onAppear 时恢复（这样关闭面板不丢设置，但 app 退出时完全清理）
  - 验证：调整伽马值 → 收起图像调整面板 → 屏幕恢复正常；强制退出 app → 屏幕恢复正常

- [ ] 修复 1920x1080 分辨率无法点击的问题
  - 实现提示：
    1. `DisplayModeListView.swift` 的 `switchTo()` 方法：去掉 `mode.id != display.currentDisplayMode?.id` 的静默 guard，改为：如果是当前模式，显示"已是当前模式"提示（用 `withAnimation` 闪一下高亮）
    2. 将 `ResolutionService.shared.setDisplayMode()` 调用改为 `Task { @MainActor in }`，在调用前设 `isSwitching = true`，await 完成后设 `isSwitching = false`
    3. `ResolutionService.swift` 的 `setDisplayMode` 改为 `async` 方法，内部用 `withCheckedContinuation` 包装 `CGConfigureDisplayWithDisplayMode` + `CGCompleteDisplayConfiguration`
    4. 添加失败反馈：如果 `setDisplayMode` 返回 false，显示错误提示
  - 验证：点击 1920x1080 → 显示 loading → 切换成功或显示错误信息；点击已是当前的模式 → 显示"已是当前模式"

- [ ] 修复 HiDPI 缩放模式不显示/需要重连的问题
  - 实现提示：
    1. `HiDPIService.swift` 的 `enableHiDPI()` 完成 plist 写入后，调用 `CGDisplayForceToMirror(displayID, 0)` 再 `CGDisplayForceToMirror(displayID, kCGNullDirectDisplay)` 来触发显示器重新枚举模式（参考 BetterDisplay 的做法）
    2. 如果上面的方法不可用，备选方案：用 `IOServiceRequestProbe` 通知 IOKit 重新扫描
    3. 刷新后调用 `DisplayMode.availableModes(for:)` 重新获取模式列表并更新 `display.availableModes`
    4. 在 `DisplayModeListView` 添加"刷新模式列表"按钮作为兜底
  - 验证：点击启用 HiDPI → 模式列表自动刷新，出现新的 HiDPI 缩放分辨率（如 1920x1080 HiDPI）

- [ ] 改进 DisplayMode 的 HiDPI 分类显示
  - 实现提示：
    1. `DisplayModeListView.swift` 的分组逻辑：增加"HiDPI 缩放模式"分组，专门展示 `isHiDPI && !isNative` 的模式
    2. 对于 2K 显示器（如用户的 HKC 2560x1440），HiDPI 缩放模式应该包含：1280x720 HiDPI（原生 2x）、更低分辨率的 HiDPI 模式
    3. 在每个模式行显示"逻辑分辨率 @ 实际像素密度"信息，帮助用户理解 HiDPI 含义
  - 验证：模式列表清晰分组显示"默认及原生模式"、"HiDPI 缩放模式"、"其他模式"

**Phase 验收**: 编译通过 + 以上四个验证场景全部满足
