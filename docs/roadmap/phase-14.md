# Phase 14: 性能优化（消除卡顿）

> 目标：将所有 IOKit/CG 阻塞调用移出主线程，减少不必要的 SwiftUI 重绘

## 任务列表

- [ ] 将 BrightnessService 的 IOKit 调用移到后台线程
  - 实现提示：
    1. `BrightnessService.swift`：将 `getInternalBrightness()` 和 `setInternalBrightness()` 改为在专用 `DispatchQueue(label: "brightness")` 上执行
    2. 公开方法 `setBrightness()` 和 `refreshBrightness()` 改为 `async`，内部用 `withCheckedContinuation` 包装
    3. 调用处（`BrightnessSliderView`）用 `Task { await ... }` 调用，slider 的 `onEditingChanged` 触发 async 设置
    4. 加 debounce：slider 拖动过程中不发送，松手（onEditingChanged false）时才发送最终值
  - 验证：拖动亮度滑块 → 界面不卡顿，松手后亮度平滑变化

- [ ] 将 DisplayInfo.init 的 IOKit 查询移到后台
  - 实现提示：
    1. `DisplayInfo.swift`：构造器只设置 displayID 和基本 CG 属性（name 暂用 "Display \(id)"）
    2. 添加 `func loadDetails() async` 方法，在后台执行 `lookupDisplayName()` 和 `DisplayMode.availableModes()`
    3. `DisplayManager.refreshDisplays()` 先创建 DisplayInfo 对象（快速，不阻塞），然后 `Task { await display.loadDetails() }` 异步加载详情
    4. 加载完成后 `@MainActor` 更新 `@Published` 属性，触发 UI 刷新
  - 验证：插拔显示器 → 列表立刻出现新显示器（名称短暂显示为 ID），详情异步加载后更新名称和模式列表

- [ ] 将 ColorProfileService.enumerateProfiles 改为异步
  - 实现提示：
    1. `ColorProfileService.swift`：`enumerateProfiles()` 改为 `async` 方法，内部用 `Task.detached` 在后台扫描文件系统
    2. `ColorProfileView.swift`：`loadProfiles()` 用 `Task { profiles = await svc.enumerateProfiles() }`
    3. 加载期间显示 ProgressView 动画，profiles 为空时不显示"无描述文件"，而是显示加载动画
  - 验证：打开色彩管理面板 → 看到加载动画 → 描述文件列表异步填充

- [ ] 拆分 DisplayInfo 的 @Published 属性，减少级联重绘
  - 实现提示：
    1. 将 `DisplayInfo` 拆分：基础信息（name, displayID, isBuiltin 等不变属性）放在 struct 里
    2. 动态属性（brightness, currentDisplayMode 等）保留 @Published，但分组到专用的 ObservableObject 子对象
    3. 或者更简单的方案：在 `DisplayDetailView` 里，每个 Section 用 `EquatableView` 或 `.id()` 限制重绘范围
    4. 最简方案（推荐）：把每个 Section（亮度、分辨率、色彩等）提取为独立的 View struct，各自 `@ObservedObject` 只观察需要的属性。利用 SwiftUI 的 view identity 机制，collapsed section 不 observe
  - 验证：拖动亮度滑块时，用 Instruments 的 SwiftUI profiler 确认其他 Section 不重绘；或在其他 Section 的 body 里加 `let _ = print("xxx re-render")` 确认不被触发

- [ ] 移除 View body 中的同步 CG 调用
  - 实现提示：
    1. `DisplayDetailView.swift` 第 99 行 `Text(ColorProfileService.shared.currentColorSpaceName(...))` → 改为在 `onAppear` 时异步获取并存入 `@State var colorSpaceName: String`
    2. 第 125 行 `Text(ColorProfileService.shared.colorModeDescription(...))` → 同上
    3. 其他 Section header 中如有类似的同步服务调用，全部改为 `@State` + `onAppear`/`task {}` 模式
  - 验证：编译通过 + 打开 DisplayDetailView 无卡顿

- [ ] 优化 DDCService 批量读取性能
  - 实现提示：
    1. `DDCService.swift` 的 `readBatchVCPCodes()` 中 `Thread.sleep(forTimeInterval: 0.05)` → 改为 `try await Task.sleep(nanoseconds: 30_000_000)`（30ms，原来 50ms）
    2. 将方法改为 `async` 版本，用 `TaskGroup` 并行读取不相邻的 VCP codes（I2C 总线同一设备不能真并行，但可以用更小的间隔）
    3. 或者缓存策略：首次完整读取，之后只读取用户正在操作的 VCP code，其余用缓存值
  - 验证：打开集成控制面板 → 读取 11 个 VCP codes 时间从 ~550ms 降到 ~330ms

**Phase 验收**: 编译通过 + 所有面板打开/操作无明显卡顿（主观体验流畅）
