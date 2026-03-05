# 踩坑经验 — SwiftUI / UI

> 更新: 2026-03-05

## SwiftUI / MenuBarExtra

- MenuBarExtra 需要 `.menuBarExtraStyle(.window)` 才能显示自定义 SwiftUI 视图（默认是 menu style 只支持 Button/Toggle）
- 隐藏 Dock 图标：在 project.yml 设 `INFOPLIST_KEY_LSUIElement: true`，不需要在 AppDelegate 里手动设

## UI 动画 / SwiftUI（Phase 12）

- `withAnimation(.easeInOut(duration: 0.2)) { state.toggle() }` 是触发展开/折叠动画的最简单方式，不需要 `.animation(_, value:)` 作用在整个容器上
- `.transition(.opacity.combined(with: .move(edge: .top)))` 用于展开内容的进出效果，视觉上像从按钮下方滑出
- 共享 icon 助手 `MenuItemIcon`（定义在 MenuBarView.swift）可在同一 Module 内所有 View 直接使用，不需要额外声明
- SwiftUI 中颜色语义化（绿色=保护/安全，红=流媒体，橙=亮度，灰=设置，紫=颜色管理）能有效传递功能语义，无需额外文字说明

## DDC 性能缓存（Phase 12）

- DDC I2C 读取延迟 50ms+，UI 重复触发读取会显著影响体验 → 用 `NSLock` + 字典缓存 + 5 秒 TTL 解决；写操作后立即失效对应缓存条目
- 缓存 key 为 `[CGDirectDisplayID: [UInt8: VCPCacheEntry]]` 双层字典，可按显示器和 VCP code 精确失效
- `NSLock.lock()` / `unlock()` 必须配对，建议用 `defer { lock.unlock() }` 但要注意提前 return 时 defer 会正确执行

## SwiftUI 性能

- `@Published` 属性变更会触发所有观察该 ObservableObject 的 View 重绘 → 拆分状态到多个小 ObservableObject 或用 `@State` 局部化
- View `body` 中不要放同步 IOKit/CG 调用（如 `CGDisplayCopyColorSpace`）→ 用 `@State` + `onAppear`/`task {}` 异步获取
- `isSwitching = true; syncCall(); isSwitching = false` 模式无效：SwiftUI 不会在同步代码中间渲染 → 必须用 async/await 让 SwiftUI 有机会重绘
- `@StateObject` 包装共享单例（`XXX.shared`）是反模式：每次 View 重建都可能创建新订阅 → 共享单例用 `@ObservedObject`
- `CGSetDisplayTransferByFormula` 设置的 gamma table 是内核级持久的，不会随 View 销毁自动恢复 → 必须在 `onDisappear` 和 app 退出时手动调 `CGDisplayRestoreColorSyncSettings()`
